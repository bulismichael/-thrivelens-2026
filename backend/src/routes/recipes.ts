import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validation';
import { authenticate, optionalAuth } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as recipeController from '../controllers/recipeController';

const router = Router();

const recipeValidation = [
  body('name').trim().isLength({ min: 1, max: 255 }).withMessage('Name is required'),
  body('description').optional().trim(),
  body('prepTime').isInt({ min: 0 }).withMessage('Prep time must be non-negative'),
  body('cookTime').isInt({ min: 0 }).withMessage('Cook time must be non-negative'),
  body('servings').isInt({ min: 1 }).withMessage('Servings must be at least 1'),
  body('caloriesPerServing').isInt({ min: 0 }).withMessage('Calories must be non-negative'),
  body('proteinPerServing').isFloat({ min: 0 }).withMessage('Protein must be non-negative'),
  body('carbsPerServing').isFloat({ min: 0 }).withMessage('Carbs must be non-negative'),
  body('fatPerServing').isFloat({ min: 0 }).withMessage('Fat must be non-negative'),
  body('ingredients').isArray({ min: 1 }).withMessage('At least one ingredient required'),
  body('ingredients.*.name').trim().isLength({ min: 1 }).withMessage('Ingredient name required'),
  body('ingredients.*.quantity').isFloat({ min: 0.1 }).withMessage('Quantity must be positive'),
  body('ingredients.*.unit').trim().isLength({ min: 1 }).withMessage('Unit required'),
  body('instructions').isArray({ min: 1 }).withMessage('At least one instruction required'),
  body('tags').optional().isArray(),
];

// Public routes
router.get('/', optionalAuth, asyncHandler(recipeController.getRecipes));
router.get('/search', optionalAuth, asyncHandler(recipeController.searchRecipes));
router.get('/:id', optionalAuth, asyncHandler(recipeController.getRecipeById));

// Protected routes
router.post('/', authenticate, recipeValidation, validate, asyncHandler(recipeController.createRecipe));
router.put('/:id', authenticate, asyncHandler(recipeController.updateRecipe));
router.delete('/:id', authenticate, asyncHandler(recipeController.deleteRecipe));
router.post('/:id/save', authenticate, asyncHandler(recipeController.saveRecipe));
router.delete('/:id/save', authenticate, asyncHandler(recipeController.unsaveRecipe));
router.get('/user/saved', authenticate, asyncHandler(recipeController.getSavedRecipes));

export default router;