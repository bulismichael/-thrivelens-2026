import { Request, Response, NextFunction } from 'express';
import { config } from '../config';
import { ValidationError, isAppError } from '../utils/errors';
import { ZodError } from 'zod';

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  _next: NextFunction
): void {
  console.error('Error:', {
    message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
  });

  // Handle Zod validation errors
  if (err instanceof ZodError) {
    const errors = err.errors.map(e => ({
      field: e.path.join('.'),
      message: e.message,
    }));
    res.status(400).json({
      success: false,
      error: 'Validation failed',
      errors,
    });
    return;
  }

  // Handle known application errors
  if (isAppError(err)) {
    const response: any = {
      success: false,
      error: err.message,
    };

    if (err instanceof ValidationError) {
      response.errors = err.errors;
    }

    if (config.nodeEnv === 'development') {
      response.stack = err.stack;
    }

    res.status(err.statusCode).json(response);
    return;
  }

  // Handle PostgreSQL errors
  if (err.message.includes('duplicate key value violates unique constraint')) {
    res.status(409).json({
      success: false,
      error: 'A record with this value already exists',
    });
    return;
  }

  if (err.message.includes('foreign key constraint')) {
    res.status(400).json({
      success: false,
      error: 'Referenced resource does not exist',
    });
    return;
  }

  // Handle database connection errors
  const msg = err.message || '';
  const isDbConnectionError = 
    msg.includes('ECONNREFUSED') || 
    msg.includes('ETIMEDOUT') ||
    msg.includes('connection') ||
    msg.includes('AggregateError') ||
    (err as any).code === 'ECONNREFUSED' ||
    (err as any).code === 'ETIMEDOUT' ||
    err.name === 'AggregateError';

  if (isDbConnectionError) {
    res.status(503).json({
      success: false,
      error: 'Database unavailable. Please try again later.',
      ...(config.nodeEnv === 'development' && { detail: msg || err.stack?.split('\n')[0] }),
    });
    return;
  }

  // Default to 500 for unknown errors
  const safeMessage = msg || 'Internal server error';
  res.status(500).json({
    success: false,
    error: config.nodeEnv === 'development' ? safeMessage : 'Internal server error',
    ...(config.nodeEnv === 'development' && { stack: err.stack }),
  });
}

export function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({
    success: false,
    error: `Route ${req.method} ${req.path} not found`,
  });
}

export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<any>
) {
  return (req: Request, res: Response, next: NextFunction): void => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}