import { Router } from 'express';
import { body, query } from 'express-validator';
import { validate } from '../middleware/validation';
import { authenticate, optionalAuth } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as exerciseController from '../controllers/exerciseController';

const router = Router();

// Public routes (with optional auth for personalized results)
router.get('/', optionalAuth, asyncHandler(exerciseController.getExercises));
router.get('/body-parts', asyncHandler(exerciseController.getBodyParts));
router.get('/:id', optionalAuth, asyncHandler(exerciseController.getExerciseById));

// Protected routes
router.post('/', authenticate, [
  body('name').trim().isLength({ min: 1, max: 255 }).withMessage('Name is required'),
  body('description').optional().trim(),
  body('bodyPart').isIn(['chest', 'back', 'shoulders', 'arms', 'legs', 'core', 'cardio', 'full_body']).withMessage('Invalid body part'),
  body('equipment').optional().isArray(),
  body('difficulty').isIn(['beginner', 'intermediate', 'advanced']).withMessage('Invalid difficulty'),
  body('instructions').optional().isArray(),
  body('muscleGroups').optional().isArray(),
  body('videoUrl').optional().isURL(),
  body('imageUrl').optional().isURL(),
], validate, asyncHandler(exerciseController.createExercise));

router.put('/:id', authenticate, asyncHandler(exerciseController.updateExercise));
router.delete('/:id', authenticate, asyncHandler(exerciseController.deleteExercise));

export default router;