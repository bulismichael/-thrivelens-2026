import express from 'express';
import cors, { CorsOptions } from 'cors';
import { config } from './config';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';
import { apiRateLimit } from './middleware/rateLimiter';
import { sanitizeInput } from './middleware/validation';
import authRoutes from './routes/auth';
import userRoutes from './routes/users';
import profileRoutes from './routes/profile';
import exerciseRoutes from './routes/exercises';
import workoutRoutes from './routes/workouts';
import mealRoutes from './routes/meals';
import progressRoutes from './routes/progress';
import aiRoutes from './routes/ai';
import recipeRoutes from './routes/recipes';
import nutritionPlanRoutes from './routes/nutritionPlans';
import workoutPlanRoutes from './routes/workoutPlans';
import { closePool, pool } from './config/database';

const app = express();

// Trust proxy for rate limiting behind reverse proxy
app.set('trust proxy', 1);

// CORS: support array origins + expo schemes
const corsOptions: CorsOptions = {
  credentials: config.cors.credentials,
  origin: (origin, callback) => {
    const allowed = config.cors.origin;
    // Allow requests with no origin (mobile apps, curl)
    if (!origin) return callback(null, true);
    if (allowed === true) return callback(null, true);
    if (Array.isArray(allowed)) {
      const isAllowed = allowed.some(pattern => {
        if (pattern.includes('*')) {
          const regex = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
          return regex.test(origin);
        }
        return pattern === origin;
      });
      // In development, allow Expo and localhost variations
      if (!isAllowed && config.nodeEnv === 'development') {
        if (origin.includes('localhost') || origin.includes('127.0.0.1') || origin.startsWith('exp://')) {
          return callback(null, true);
        }
      }
      return callback(null, isAllowed);
    }
    return callback(null, allowed === origin);
  },
};

// Request logger
app.use((req, res, next) => {
  const start = Date.now();
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.url} -> ${res.statusCode} (${duration}ms)`);
  });
  next();
});

// Middleware
app.use(cors(corsOptions));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(sanitizeInput);
app.use(apiRateLimit);

// Root & API info
app.get('/', (_req, res) => {
  res.json({
    name: 'ThriveLens API',
    version: '1.0.0',
    status: 'running',
    docs: '/api/health',
    timestamp: new Date().toISOString(),
  });
});

app.get('/api', (_req, res) => {
  res.json({
    name: 'ThriveLens API',
    version: '1.0.0',
    endpoints: ['/api/auth', '/api/profile', '/api/exercises', '/api/workouts', '/api/meals', '/api/progress', '/api/ai', '/api/recipes', '/api/nutrition-plans', '/api/workout-plans'],
    health: '/api/health',
  });
});

// Simple ping without DB for connectivity test
app.get('/api/ping', (_req, res) => {
  res.json({ pong: true, timestamp: new Date().toISOString() });
});
app.post('/api/ping', (req, res) => {
  res.json({ pong: true, body: req.body, timestamp: new Date().toISOString() });
});

async function getHealth() {
  let dbStatus: 'ok' | 'error' = 'ok';
  let dbLatencyMs: number | null = null;
  try {
    const start = Date.now();
    await pool.query('SELECT 1');
    dbLatencyMs = Date.now() - start;
  } catch {
    dbStatus = 'error';
  }
  return {
    status: dbStatus === 'ok' ? 'ok' : 'degraded',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    uptime: process.uptime(),
    services: {
      database: dbStatus,
      dbLatencyMs,
    },
  };
}

// Health check with DB probe
app.get('/health', async (_req, res) => {
  res.json(await getHealth());
});

app.get('/api/health', async (_req, res) => {
  res.json(await getHealth());
});

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/profile', profileRoutes);
app.use('/api/exercises', exerciseRoutes);
app.use('/api/workouts', workoutRoutes);
app.use('/api/meals', mealRoutes);
app.use('/api/progress', progressRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/recipes', recipeRoutes);
app.use('/api/nutrition-plans', nutritionPlanRoutes);
app.use('/api/workout-plans', workoutPlanRoutes);

// 404 handler
app.use(notFoundHandler);

// Error handler
app.use(errorHandler);

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully');
  await closePool();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT received, shutting down gracefully');
  await closePool();
  process.exit(0);
});

void app.listen(config.port, () => {
  console.log(`🚀 ThriveLens backend running on port ${config.port} in ${config.nodeEnv} mode`);
  console.log(`📚 API available at http://localhost:${config.port}/api`);
  console.log(`🏥 Health check at http://localhost:${config.port}/api/health`);
  if (!config.openai.apiKey) {
    console.warn('⚠️  OPENAI_API_KEY not set — AI features will return 503');
  }
});

export default app;