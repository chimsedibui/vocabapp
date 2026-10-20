-- One row per replicated record. `seq` orders changes for incremental pulls.
CREATE TABLE IF NOT EXISTS rows (
  tbl TEXT NOT NULL,
  pk TEXT NOT NULL,
  data TEXT,
  deleted INTEGER NOT NULL DEFAULT 0,
  changed_at INTEGER NOT NULL,
  device TEXT NOT NULL,
  seq INTEGER NOT NULL,
  PRIMARY KEY (tbl, pk)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS rows_seq ON rows (seq);
