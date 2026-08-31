import express from 'express';
import cors from 'cors';
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
import { closePool } from './config/database';

const app = express();

// Trust proxy for rate limiting behind reverse proxy
app.set('trust proxy', 1);

// Middleware
app.use(cors(config.cors));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(sanitizeInput);
app.use(apiRateLimit);

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    version: '1.0.0',
  });
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

const server = app.listen(config.port, () => {
  console.log(`🚀 Server running on port ${config.port} in ${config.nodeEnv} mode`);
  console.log(`📚 API available at http://localhost:${config.port}/api`);
});

export default app;