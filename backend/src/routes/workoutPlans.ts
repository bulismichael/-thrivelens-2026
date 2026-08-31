import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validation';
import { authenticate } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as workoutPlanController from '../controllers/workoutPlanController';

const router = Router();

router.use(authenticate);

const workoutPlanValidation = [
  body('name').trim().isLength({ min: 1, max: 255 }).withMessage('Name is required'),
  body('description').optional().trim(),
  body('daysPerWeek').isInt({ min: 1, max: 7 }).withMessage('Days per week must be 1-7'),
  body('sessions').isArray({ min: 1 }).withMessage('At least one session required'),
  body('sessions.*.dayOfWeek').isInt({ min: 0, max: 6 }).withMessage('Day of week must be 0-6'),
  body('sessions.*.name').trim().isLength({ min: 1 }).withMessage('Session name is required'),
  body('sessions.*.estimatedDuration').isInt({ min: 10 }).withMessage('Duration must be at least 10 minutes'),
  body('sessions.*.exercises').isArray({ min: 1 }).withMessage('At least one exercise required'),
  body('sessions.*.exercises.*.exerciseId').isUUID().withMessage('Valid exercise ID required'),
  body('sessions.*.exercises.*.sets').isInt({ min: 1 }).withMessage('Sets must be at least 1'),
  body('sessions.*.exercises.*.reps').trim().isLength({ min: 1 }).withMessage('Reps required'),
  body('sessions.*.exercises.*.restTime').isInt({ min: 0 }).withMessage('Rest time required'),
];

router.get('/', asyncHandler(workoutPlanController.getWorkoutPlans));
router.get('/active', asyncHandler(workoutPlanController.getActiveWorkoutPlan));
router.get('/:id', asyncHandler(workoutPlanController.getWorkoutPlanById));
router.post('/', workoutPlanValidation, validate, asyncHandler(workoutPlanController.createWorkoutPlan));
router.put('/:id', asyncHandler(workoutPlanController.updateWorkoutPlan));
router.patch('/:id/activate', asyncHandler(workoutPlanController.activateWorkoutPlan));
router.delete('/:id', asyncHandler(workoutPlanController.deleteWorkoutPlan));
router.post('/generate', asyncHandler(workoutPlanController.generateWorkoutPlan));

export default router;