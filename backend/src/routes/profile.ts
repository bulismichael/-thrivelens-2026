import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validation';
import { authenticate, loadUserProfile } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as profileController from '../controllers/profileController';

const router = Router();

// All profile routes require authentication
router.use(authenticate);
router.use(loadUserProfile);

const profileValidation = [
  body('age').isInt({ min: 13, max: 120 }).withMessage('Age must be between 13 and 120'),
  body('height').isFloat({ min: 50, max: 300 }).withMessage('Height must be between 50 and 300 cm'),
  body('sex').isIn(['male', 'female', 'other']).withMessage('Sex must be male, female, or other'),
  body('weight').isFloat({ min: 20, max: 500 }).withMessage('Weight must be between 20 and 500 kg'),
  body('activityLevel').isIn(['sedentary', 'light', 'moderate', 'active', 'very_active']).withMessage('Invalid activity level'),
  body('goal').isIn(['lose_weight', 'maintain', 'gain_muscle', 'improve_fitness']).withMessage('Invalid goal'),
  body('targetWeight').optional().isFloat({ min: 20, max: 500 }).withMessage('Target weight must be between 20 and 500 kg'),
];

router.get('/', asyncHandler(profileController.getProfile));
router.post('/', profileValidation, validate, asyncHandler(profileController.createOrUpdateProfile));
router.put('/', profileValidation, validate, asyncHandler(profileController.createOrUpdateProfile));
router.delete('/', asyncHandler(profileController.deleteProfile));
router.get('/nutrition-targets', asyncHandler(profileController.getNutritionTargets));

export default router;