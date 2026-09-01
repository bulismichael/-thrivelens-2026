import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as aiController from '../controllers/aiController';

const router = Router();

router.use(authenticate);

router.get('/tips', asyncHandler(aiController.getTips));
router.patch('/tips/:id/read', asyncHandler(aiController.markTipAsRead));
router.post('/generate-tips', asyncHandler(aiController.generateTips));
router.post('/analyze-progress', asyncHandler(aiController.analyzeProgress));
router.post('/recipe-suggestions', asyncHandler(aiController.getRecipeSuggestions));
router.post('/workout-suggestions', asyncHandler(aiController.getWorkoutSuggestions));

export default router;