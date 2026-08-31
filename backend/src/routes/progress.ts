import { Router } from 'express';
import { body, query } from 'express-validator';
import { validate } from '../middleware/validation';
import { authenticate } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as progressController from '../controllers/progressController';

const router = Router();

router.use(authenticate);

const weightEntryValidation = [
  body('weight').isFloat({ min: 20, max: 500 }).withMessage('Weight must be between 20 and 500 kg'),
  body('date').isISO8601().withMessage('Valid date is required'),
  body('note').optional().trim(),
];

router.get('/metrics', asyncHandler(progressController.getProgressMetrics));
router.get('/weight-history', asyncHandler(progressController.getWeightHistory));
router.post('/weight', weightEntryValidation, validate, asyncHandler(progressController.addWeightEntry));
router.put('/weight/:id', weightEntryValidation, validate, asyncHandler(progressController.updateWeightEntry));
router.delete('/weight/:id', asyncHandler(progressController.deleteWeightEntry));
router.get('/charts/weight', asyncHandler(progressController.getWeightChartData));
router.get('/charts/nutrition', asyncHandler(progressController.getNutritionChartData));
router.get('/charts/workouts', asyncHandler(progressController.getWorkoutChartData));

export default router;