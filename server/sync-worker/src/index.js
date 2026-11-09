// Single-user row store for VocabApp sync. The app does all merging; this
// Worker only authenticates, stores the newest version of each row and hands
// out changes in `seq` order.
//
// GET  /v1/status                          -> { seq }
// GET  /v1/pull?after=N&device=D&limit=L[&schema=S&app=V&platform=P]
//                                         -> { rows, cursor, more, devices }
// POST /v1/push { device, rows: [{t,p,d,x,c}], schema? } -> { accepted }
//
// `schema` is the app's DB version. Apps before DB v6 do not send it, so it
// defaults to LEGACY_SCHEMA. Rows go down without the columns that client does
// not know yet, and an older client's push keeps those columns on the server,
// so a device on an old app keeps syncing instead of rejecting newer rows.

const PROTOCOL = '1';
const MAX_BODY = 1024 * 1024;
const MAX_ROWS = 500;
const LEGACY_SCHEMA = 5;
const DEVICES_TABLE = `CREATE TABLE IF NOT EXISTS devices (
  device TEXT PRIMARY KEY, schema INTEGER NOT NULL, app TEXT, platform TEXT,
  seen_at INTEGER NOT NULL) WITHOUT ROWID`;

// Columns added to replicated tables, by the DB version that added them.
const ADDED_COLUMNS = {
  6: { review_events: ['session_id', 'shown_at', 'flipped_at'] },
};

/** Columns per table that a client on [schema] does not have. */
function unknownColumns(schema) {
  const out = {};
  for (const [version, tables] of Object.entries(ADDED_COLUMNS)) {
    if (Number(version) <= schema) continue;
    for (const [table, columns] of Object.entries(tables)) {
      (out[table] ??= []).push(...columns);
    }
  }
  return out;
}

function readSchema(value) {
  const n = Number(value ?? LEGACY_SCHEMA);
  return Number.isSafeInteger(n) && n >= 1 && n <= 1000 ? n : null;
}

function downgrade(data, columns) {
  if (!columns || data === null) return data;
  const row = JSON.parse(data);
  for (const c of columns) delete row[c];
  return JSON.stringify(row);
}

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });

async function authorized(request, env) {
  const expected = env.SYNC_TOKEN;
  const header = request.headers.get('authorization') ?? '';
  if (!expected || expected.length < 24 || !header.startsWith('Bearer ')) {
    return false;
  }
  const enc = new TextEncoder();
  const a = enc.encode(header.slice(7));
  const b = enc.encode(expected);
  return a.byteLength === b.byteLength && crypto.subtle.timingSafeEqual(a, b);
}

function validRow(r) {
  return (
    r &&
    typeof r.t === 'string' && r.t.length <= 64 &&
    typeof r.p === 'string' && r.p.length > 0 && r.p.length <= 256 &&
    Number.isSafeInteger(r.c) && r.c >= 0 &&
    (r.x === 0 || r.x === 1) &&
    (r.x === 1 ? r.d === null : typeof r.d === 'string' && r.d.length <= 512 * 1024)
  );
}

async function pull(url, env) {
  const after = Number(url.searchParams.get('after') ?? '0');
  const device = url.searchParams.get('device') ?? '';
  const limit = Math.min(Number(url.searchParams.get('limit') ?? MAX_ROWS), MAX_ROWS);
  const schema = readSchema(url.searchParams.get('schema'));
  const app = (url.searchParams.get('app') ?? '').slice(0, 32) || null;
  const platform = (url.searchParams.get('platform') ?? '').slice(0, 32) || null;
  if (!Number.isSafeInteger(after) || after < 0 || !device || device.length > 64 ||
      !(limit > 0) || schema === null) {
    return json({ error: 'request' }, 400);
  }
  // One transaction: the max seq and the page come from the same snapshot,
  // so jumping the cursor to `max` cannot skip rows written in between.
  const [, top, page, , devices] = await env.DB.batch([
    // Workers deployed before the device table only need a redeploy.
    env.DB.prepare(DEVICES_TABLE),
    env.DB.prepare('SELECT COALESCE(MAX(seq), 0) AS seq FROM rows'),
    env.DB.prepare(
      'SELECT tbl, pk, data, deleted, changed_at, seq FROM rows WHERE seq > ?1 AND device != ?2 ORDER BY seq LIMIT ?3',
    ).bind(after, device, limit),
    env.DB.prepare(
      `INSERT INTO devices (device, schema, app, platform, seen_at) VALUES (?1, ?2, ?3, ?4, ?5)
       ON CONFLICT (device) DO UPDATE SET schema = excluded.schema, app = excluded.app,
         platform = excluded.platform, seen_at = excluded.seen_at`,
    ).bind(device, schema, app, platform, Date.now()),
    env.DB.prepare('SELECT device, schema, app, platform, seen_at FROM devices ORDER BY seen_at DESC LIMIT 20'),
  ]);
  const max = top.results[0].seq;
  const hidden = unknownColumns(schema);
  const rows = page.results.map((r) => ({
    t: r.tbl, p: r.pk, d: downgrade(r.data, hidden[r.tbl]), x: r.deleted, c: r.changed_at, s: r.seq,
  }));
  const more = rows.length === limit;
  return json({
    rows,
    cursor: more ? rows[rows.length - 1].s : Math.max(max, after),
    more,
    devices: devices.results,
  });
}

async function push(request, env) {
  const text = await request.text();
  if (text.length > MAX_BODY) return json({ error: 'request' }, 413);
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return json({ error: 'request' }, 400);
  }
  const rows = body?.rows;
  if (typeof body?.device !== 'string' || !body.device || !Array.isArray(rows) ||
      rows.length > MAX_ROWS || !rows.every(validRow)) {
    return json({ error: 'request' }, 400);
  }
  const schema = readSchema(body.schema);
  if (schema === null) return json({ error: 'request' }, 400);
  if (rows.length === 0) return json({ accepted: 0 });
  // An older client sends rows without the newer columns; keep the server's
  // values for those instead of erasing them.
  const keep = Object.entries(unknownColumns(schema));
  const data = keep.length === 0
    ? 'excluded.data'
    : `CASE ${keep.map(([table, columns]) =>
        `WHEN rows.tbl = '${table}' AND excluded.data IS NOT NULL AND rows.data IS NOT NULL
         THEN json_set(excluded.data, ${columns.map((c) =>
          `'$.${c}', json_extract(rows.data, '$.${c}')`).join(', ')})`).join(' ')}
       ELSE excluded.data END`;
  // A single statement keeps the free-plan limit of 50 queries per request
  // and is atomic. Seq values continue after the current maximum; an older
  // version of a row (by changed_at) never replaces a newer one.
  const result = await env.DB.prepare(
    `INSERT INTO rows (tbl, pk, data, deleted, changed_at, device, seq)
     SELECT json_extract(value, '$.t'), json_extract(value, '$.p'),
            json_extract(value, '$.d'), json_extract(value, '$.x'),
            json_extract(value, '$.c'), ?1,
            (SELECT COALESCE(MAX(seq), 0) FROM rows) + key + 1
     FROM json_each(?2) WHERE true
     ON CONFLICT (tbl, pk) DO UPDATE SET
       data = ${data}, deleted = excluded.deleted,
       changed_at = excluded.changed_at, device = excluded.device, seq = excluded.seq
     WHERE excluded.changed_at >= rows.changed_at`,
  ).bind(body.device, JSON.stringify(rows)).run();
  return json({ accepted: result.meta.changes ?? 0 });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!(await authorized(request, env))) return json({ error: 'auth' }, 401);
    if (request.headers.get('x-sync-protocol') !== PROTOCOL) {
      return json({ error: 'protocol' }, 426);
    }
    try {
      if (request.method === 'GET' && url.pathname === '/v1/status') {
        const top = await env.DB.prepare('SELECT COALESCE(MAX(seq), 0) AS seq FROM rows').first();
        return json({ seq: top.seq, protocol: PROTOCOL });
      }
      if (request.method === 'GET' && url.pathname === '/v1/pull') return await pull(url, env);
      if (request.method === 'POST' && url.pathname === '/v1/push') return await push(request, env);
      return json({ error: 'not_found' }, 404);
    } catch (error) {
      // Free-plan daily limits surface as D1 errors; the app keeps its queue.
      const message = String(error?.message ?? error);
      const quota = /limit|exceed|quota|too many/i.test(message);
      console.error(message);
      return json({ error: quota ? 'quota' : 'server' }, quota ? 503 : 500);
    }
  },
};
