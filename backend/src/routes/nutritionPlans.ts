import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validation';
import { authenticate } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as nutritionPlanController from '../controllers/nutritionPlanController';

const router = Router();

router.use(authenticate);

const nutritionPlanValidation = [
  body('name').trim().isLength({ min: 1, max: 255 }).withMessage('Name is required'),
  body('dailyCalories').isInt({ min: 800 }).withMessage('Daily calories must be at least 800'),
  body('dailyProtein').isFloat({ min: 0 }).withMessage('Daily protein must be non-negative'),
  body('dailyCarbs').isFloat({ min: 0 }).withMessage('Daily carbs must be non-negative'),
  body('dailyFat').isFloat({ min: 0 }).withMessage('Daily fat must be non-negative'),
  body('meals').isArray({ min: 1 }).withMessage('At least one meal required'),
  body('meals.*.mealType').isIn(['breakfast', 'lunch', 'dinner', 'snack']).withMessage('Invalid meal type'),
  body('meals.*.targetCalories').isInt({ min: 0 }).withMessage('Target calories must be non-negative'),
  body('meals.*.targetProtein').isFloat({ min: 0 }).withMessage('Target protein must be non-negative'),
  body('meals.*.targetCarbs').isFloat({ min: 0 }).withMessage('Target carbs must be non-negative'),
  body('meals.*.targetFat').isFloat({ min: 0 }).withMessage('Target fat must be non-negative'),
  body('meals.*.foods').isArray().withMessage('Foods must be an array'),
];

router.get('/', asyncHandler(nutritionPlanController.getNutritionPlans));
router.get('/active', asyncHandler(nutritionPlanController.getActiveNutritionPlan));
router.get('/:id', asyncHandler(nutritionPlanController.getNutritionPlanById));
router.post('/', nutritionPlanValidation, validate, asyncHandler(nutritionPlanController.createNutritionPlan));
router.put('/:id', asyncHandler(nutritionPlanController.updateNutritionPlan));
router.patch('/:id/activate', asyncHandler(nutritionPlanController.activateNutritionPlan));
router.delete('/:id', asyncHandler(nutritionPlanController.deleteNutritionPlan));
router.post('/generate', asyncHandler(nutritionPlanController.generateNutritionPlan));

export default router;