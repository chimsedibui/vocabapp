// Single-user row store for VocabApp sync. The app does all merging; this
// Worker only authenticates, stores the newest version of each row and hands
// out changes in `seq` order.
//
// GET  /v1/status                          -> { seq }
// GET  /v1/pull?after=N&device=D&limit=L   -> { rows, cursor, more }
// POST /v1/push { device, rows: [{t,p,d,x,c}] } -> { accepted }

const PROTOCOL = '1';
const MAX_BODY = 1024 * 1024;
const MAX_ROWS = 500;

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
  if (!Number.isSafeInteger(after) || after < 0 || !device || !(limit > 0)) {
    return json({ error: 'request' }, 400);
  }
  // One transaction: the max seq and the page come from the same snapshot,
  // so jumping the cursor to `max` cannot skip rows written in between.
  const [top, page] = await env.DB.batch([
    env.DB.prepare('SELECT COALESCE(MAX(seq), 0) AS seq FROM rows'),
    env.DB.prepare(
      'SELECT tbl, pk, data, deleted, changed_at, seq FROM rows WHERE seq > ?1 AND device != ?2 ORDER BY seq LIMIT ?3',
    ).bind(after, device, limit),
  ]);
  const max = top.results[0].seq;
  const rows = page.results.map((r) => ({
    t: r.tbl, p: r.pk, d: r.data, x: r.deleted, c: r.changed_at, s: r.seq,
  }));
  const more = rows.length === limit;
  return json({ rows, cursor: more ? rows[rows.length - 1].s : Math.max(max, after), more });
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
  if (rows.length === 0) return json({ accepted: 0 });
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
       data = excluded.data, deleted = excluded.deleted,
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
