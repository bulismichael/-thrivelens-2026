import * as SQLite from "expo-sqlite";

const database = SQLite.openDatabaseSync("thrivelens.db");

database.execSync(`
  PRAGMA foreign_keys = ON;
  CREATE TABLE IF NOT EXISTS outbox (
    operation_id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL,
    entity TEXT NOT NULL,
    operation TEXT NOT NULL,
    payload TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TEXT NOT NULL,
    base_version TEXT,
    deleted_at TEXT,
    last_error TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS outbox_ready_idx
    ON outbox(user_id, status, next_attempt_at);
`);

export { database };
