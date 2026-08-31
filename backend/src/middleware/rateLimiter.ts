import { Request, Response, NextFunction } from 'express';
import { RateLimitError } from '../utils/errors';

// Simple in-memory rate limiter (use Redis in production)
const requestCounts = new Map<string, { count: number; resetTime: number }>();

interface RateLimitOptions {
  windowMs: number;
  maxRequests: number;
  keyGenerator?: (req: Request) => string;
  skipSuccessfulRequests?: boolean;
  skipFailedRequests?: boolean;
}

export function rateLimit(options: RateLimitOptions) {
  const {
    windowMs = 15 * 60 * 1000, // 15 minutes
    maxRequests = 100,
    keyGenerator = (req) => req.ip || 'unknown',
    skipSuccessfulRequests = false,
    skipFailedRequests = false,
  } = options;

  return (req: Request, res: Response, next: NextFunction): void => {
    const key = keyGenerator(req);
    const now = Date.now();
    const record = requestCounts.get(key);

    if (!record || now > record.resetTime) {
      requestCounts.set(key, {
        count: 1,
        resetTime: now + windowMs,
      });
      return next();
    }

    if (record.count >= maxRequests) {
      const retryAfter = Math.ceil((record.resetTime - now) / 1000);
      res.setHeader('Retry-After', retryAfter.toString());
      throw new RateLimitError(`Too many requests. Try again in ${retryAfter} seconds.`);
    }

    record.count++;
    next();
  };
}

// Pre-configured rate limiters
export const authRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  maxRequests: 10, // 10 requests per window
  keyGenerator: (req) => `auth:${req.ip}`,
});

export const apiRateLimit = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  maxRequests: 60, // 60 requests per minute
  keyGenerator: (req) => `api:${req.ip}`,
});

export const uploadRateLimit = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  maxRequests: 20, // 20 uploads per hour
  keyGenerator: (req) => `upload:${req.ip}`,
});

// Cleanup old entries periodically
setInterval(() => {
  const now = Date.now();
  for (const [key, record] of requestCounts.entries()) {
    if (now > record.resetTime) {
      requestCounts.delete(key);
    }
  }
}, 5 * 60 * 1000); // Every 5 minutes