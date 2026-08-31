import { pool } from '../config/database';
import { readFileSync } from 'fs';
import { join } from 'path';

async function migrate() {
  try {
    console.log('🔄 Running database migrations...');
    
    const initSQL = readFileSync(join(__dirname, 'init.sql'), 'utf-8');
    await pool.query(initSQL);
    
    console.log('✅ Migrations completed successfully');
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

migrate();