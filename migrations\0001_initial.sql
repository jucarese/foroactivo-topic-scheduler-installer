-- Gestor de publicaciones v1
CREATE TABLE IF NOT EXISTS scheduled_topics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  forum_url TEXT NOT NULL,
  publish_at TEXT NOT NULL,
  author TEXT NOT NULL,
  return_url TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  published_url TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processing_at TEXT,
  last_error TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  topic_id INTEGER,
  post_id INTEGER,
  published_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_scheduled_topics_status_publish
ON scheduled_topics(status, publish_at);

CREATE INDEX IF NOT EXISTS idx_scheduled_topics_created
ON scheduled_topics(created_at);
