import { Router } from 'express';
import { body, query } from 'express-validator';
import { validate } from '../middleware/validation';
import { authenticate } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as mealController from '../controllers/mealController';

const router = Router();

router.use(authenticate);

const mealValidation = [
  body('name').optional().trim(),
  body('mealType').isIn(['breakfast', 'lunch', 'dinner', 'snack']).withMessage('Invalid meal type'),
  body('date').isISO8601().withMessage('Valid date is required'),
  body('foods').isArray({ min: 1 }).withMessage('At least one food item is required'),
  body('foods.*.name').trim().isLength({ min: 1 }).withMessage('Food name is required'),
  body('foods.*.quantity').isFloat({ min: 0.1 }).withMessage('Quantity must be positive'),
  body('foods.*.unit').trim().isLength({ min: 1 }).withMessage('Unit is required'),
  body('foods.*.calories').isInt({ min: 0 }).withMessage('Calories must be non-negative'),
  body('foods.*.protein').isFloat({ min: 0 }).withMessage('Protein must be non-negative'),
  body('foods.*.carbs').isFloat({ min: 0 }).withMessage('Carbs must be non-negative'),
  body('foods.*.fat').isFloat({ min: 0 }).withMessage('Fat must be non-negative'),
  body('imageUrl').optional().isURL(),
];

router.get('/', asyncHandler(mealController.getMeals));
router.get('/daily-summary', asyncHandler(mealController.getDailySummary));
router.get('/:id', asyncHandler(mealController.getMealById));
router.post('/', mealValidation, validate, asyncHandler(mealController.createMeal));
router.put('/:id', mealValidation, validate, asyncHandler(mealController.updateMeal));
router.delete('/:id', asyncHandler(mealController.deleteMeal));
router.post('/analyze', asyncHandler(mealController.analyzeFoodImage));

export default router;