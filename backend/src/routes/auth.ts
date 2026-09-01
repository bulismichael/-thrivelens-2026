import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validation';
import { asyncHandler } from '../middleware/errorHandler';
import { authenticate } from '../middleware/auth';
import { authRateLimit } from '../middleware/rateLimiter';
import * as authController from '../controllers/authController';

const router = Router();

// Validation schemas
const registerValidation = [
  body('email').isEmail().normalizeEmail().withMessage('Valid email is required'),
  body('password')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters')
    .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .withMessage('Password must contain uppercase, lowercase, and number'),
  body('confirmPassword').custom((value, { req }) => {
    if (value !== req.body.password) {
      throw new Error('Passwords do not match');
    }
    return true;
  }),
];

const loginValidation = [
  body('email').isEmail().normalizeEmail().withMessage('Valid email is required'),
  body('password').notEmpty().withMessage('Password is required'),
];

const refreshValidation = [
  body('refreshToken').notEmpty().withMessage('Refresh token is required'),
];

const changePasswordValidation = [
  body('currentPassword').notEmpty().withMessage('Current password is required'),
  body('newPassword')
    .isLength({ min: 8 })
    .withMessage('New password must be at least 8 characters')
    .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .withMessage('New password must contain uppercase, lowercase, and number'),
];

// Routes
router.post('/register', authRateLimit, registerValidation, validate, asyncHandler(authController.register));
router.post('/login', authRateLimit, loginValidation, validate, asyncHandler(authController.login));
router.post('/refresh', authRateLimit, refreshValidation, validate, asyncHandler(authController.refresh));
router.post('/logout', authenticate, asyncHandler(authController.logout));
router.post('/change-password', authenticate, changePasswordValidation, validate, asyncHandler(authController.changePassword));
router.get('/me', authenticate, asyncHandler(authController.getMe));
router.post('/forgot-password', authRateLimit, [body('email').isEmail().normalizeEmail()], validate, asyncHandler(authController.forgotPassword));
router.post('/reset-password', authRateLimit, [
  body('token').notEmpty(),
  body('newPassword').isLength({ min: 8 }),
], validate, asyncHandler(authController.resetPassword));

export default router;