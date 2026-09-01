import dotenv from 'dotenv';
import { existsSync } from 'fs';
import { resolve } from 'path';

// Robust dotenv loading: support running from root, backend/, or Docker
const envPaths = [
  resolve(process.cwd(), 'backend/.env'),
  resolve(process.cwd(), '.env'),
  resolve(__dirname, '../../.env'),
  resolve(__dirname, '../../../.env'),
];
for (const p of envPaths) {
  if (existsSync(p)) {
    dotenv.config({ path: p, override: false });
    // Load first found but continue to allow override:false so root .env doesn't wipe backend/.env
    break;
  }
}
// Fallback: try default dotenv (cwd)
dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  
  database: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    username: process.env.DB_USER || 'thrivelens',
    password: process.env.DB_PASSWORD || 'thrivelens_dev_password',
    name: process.env.DB_NAME || 'thrivelens',
    ssl: process.env.DB_SSL === 'true',
  },
  
  jwt: {
    secret: process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production',
    accessTokenExpiry: process.env.JWT_ACCESS_EXPIRY || '15m',
    refreshTokenExpiry: process.env.JWT_REFRESH_EXPIRY || '7d',
  },
  
  openai: {
    apiKey: process.env.OPENAI_API_KEY || '',
    model: process.env.OPENAI_MODEL || 'gpt-4o',
  },
  
  cors: {
    origin: (() => {
      const raw = process.env.CORS_ORIGIN || 'http://localhost:8081,http://localhost:19006,http://localhost:3000,exp://*';
      const origins = raw.split(',').map(s => s.trim()).filter(Boolean);
      // In development, allow all origins if wildcard or empty
      if (process.env.NODE_ENV === 'development' && origins.includes('*')) return true as const;
      return origins;
    })(),
    credentials: true,
  },
  
  upload: {
    maxFileSize: parseInt(process.env.MAX_FILE_SIZE || '10485760', 10), // 10MB
    allowedMimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/heic'],
  },
  
  redis: {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379', 10),
    password: process.env.REDIS_PASSWORD || undefined,
  },
};