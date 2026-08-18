-- Public configuration for form dropdowns.
CREATE TABLE IF NOT EXISTS publication_forums (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT NOT NULL,
  forum_url TEXT NOT NULL UNIQUE,
  position INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS publication_accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT NOT NULL,
  account_key TEXT NOT NULL UNIQUE,
  position INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_publication_forums_active_position
ON publication_forums(active, position, id);

CREATE INDEX IF NOT EXISTS idx_publication_accounts_active_position
ON publication_accounts(active, position, id);
