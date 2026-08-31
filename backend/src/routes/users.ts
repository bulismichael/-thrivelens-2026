import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { asyncHandler } from '../middleware/errorHandler';
import * as userController from '../controllers/userController';

const router = Router();

router.get('/', authenticate, asyncHandler(userController.getAllUsers));
router.get('/:id', authenticate, asyncHandler(userController.getUserById));
router.put('/:id', authenticate, asyncHandler(userController.updateUser));
router.delete('/:id', authenticate, asyncHandler(userController.deleteUser));

export default router;