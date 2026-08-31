import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validation';
import { authenticate } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as workoutController from '../controllers/workoutController';

const router = Router();

router.use(authenticate);

const workoutSessionValidation = [
  body('name').trim().isLength({ min: 1, max: 255 }).withMessage('Workout name is required'),
  body('scheduledDate').isISO8601().withMessage('Valid scheduled date is required'),
  body('exercises').isArray({ min: 1 }).withMessage('At least one exercise is required'),
  body('exercises.*.exerciseId').isUUID().withMessage('Valid exercise ID is required'),
  body('exercises.*.sets').isArray({ min: 1 }).withMessage('At least one set is required'),
  body('exercises.*.sets.*.reps').optional().isInt({ min: 1, max: 1000 }),
  body('exercises.*.sets.*.weight').optional().isFloat({ min: 0 }),
  body('exercises.*.sets.*.duration').optional().isInt({ min: 1 }),
  body('exercises.*.sets.*.distance').optional().isFloat({ min: 0 }),
  body('exercises.*.sets.*.restTime').optional().isInt({ min: 0 }),
  body('notes').optional().trim(),
];

router.get('/', asyncHandler(workoutController.getWorkoutSessions));
router.get('/upcoming', asyncHandler(workoutController.getUpcomingWorkouts));
router.get('/history', asyncHandler(workoutController.getWorkoutHistory));
router.get('/:id', asyncHandler(workoutController.getWorkoutSessionById));
router.post('/', workoutSessionValidation, validate, asyncHandler(workoutController.createWorkoutSession));
router.put('/:id', asyncHandler(workoutController.updateWorkoutSession));
router.patch('/:id/complete', asyncHandler(workoutController.completeWorkoutSession));
router.delete('/:id', asyncHandler(workoutController.deleteWorkoutSession));

// Exercise set updates within a workout
router.patch('/:sessionId/exercises/:exerciseId/sets/:setId', asyncHandler(workoutController.updateExerciseSet));

export default router;