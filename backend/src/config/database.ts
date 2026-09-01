import pg from 'pg';
import { config } from '../config';

const { Pool } = pg;

export const pool = new Pool({
  host: config.database.host,
  port: config.database.port,
  user: config.database.username,
  password: config.database.password,
  database: config.database.name,
  ssl: config.database.ssl ? { rejectUnauthorized: false } : false,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle client', err);
  // Do not exit process; log and continue (pool will handle reconnection)
});

pool.on('connect', () => {
  if (config.nodeEnv === 'development') {
    console.log('[DB] Pool client connected');
  }
});

// Startup connectivity probe (non-blocking, informs operator)
(async () => {
  try {
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    console.log('[DB] Connectivity OK -', `${config.database.host}:${config.database.port}/${config.database.name}`);
  } catch (err: any) {
    console.warn('[DB] ⚠️  Database unavailable at startup - running in degraded mode');
    console.warn(`[DB]    Tried ${config.database.host}:${config.database.port}/${config.database.name} — ${err.message?.split('\n')[0] || err}`);
    console.warn('[DB]    API will respond 503 for DB-dependent routes until Postgres is reachable');
    console.warn('[DB]    Fix: docker-compose up -d postgres redis  OR set DB_HOST correctly');
  }
})();

export async function query<T extends pg.QueryResultRow = pg.QueryResultRow>(text: string, params?: any[]): Promise<pg.QueryResult<T>> {
  const start = Date.now();
  const res = await pool.query<T>(text, params);
  const duration = Date.now() - start;
  console.log('Executed query', { text: text.substring(0, 100), duration, rows: res.rowCount });
  return res;
}

export async function getClient(): Promise<pg.PoolClient> {
  const client = await pool.connect();
  return client;
}

export async function transaction<T>(callback: (client: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function closePool(): Promise<void> {
  await pool.end();
}