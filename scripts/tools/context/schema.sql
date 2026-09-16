CREATE TABLE IF NOT EXISTS volumes (
  name TEXT PRIMARY KEY,
  description TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS records (
  id TEXT PRIMARY KEY,
  volume TEXT NOT NULL REFERENCES volumes(name),
  title TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL DEFAULT '',
  tags TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS records_volume ON records(volume);
CREATE INDEX IF NOT EXISTS records_created ON records(created_at);
CREATE INDEX IF NOT EXISTS records_title ON records(title);
