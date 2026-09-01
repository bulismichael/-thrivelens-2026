import { pool } from '../config/database';
import { readFileSync, existsSync } from 'fs';
import { join, resolve } from 'path';

async function migrate() {
  try {
    console.log('🔄 Running database migrations...');
    
    // Resolve init.sql: support both src (tsx) and dist (tsc) layouts
    const candidates = [
      join(__dirname, 'init.sql'),
      resolve(__dirname, '../../src/db/init.sql'),
      resolve(process.cwd(), 'src/db/init.sql'),
      resolve(process.cwd(), 'backend/src/db/init.sql'),
    ];
    const sqlPath = candidates.find(p => existsSync(p));
    if (!sqlPath) throw new Error(`init.sql not found. Tried: ${candidates.join(', ')}`);
    const initSQL = readFileSync(sqlPath, 'utf-8');
    await pool.query(initSQL);
    
    console.log('✅ Migrations completed successfully');
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

migrate();