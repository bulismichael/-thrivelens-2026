import jwt from 'jsonwebtoken';
import { config } from '../config';

export interface JWTPayload {
  userId: string;
  email: string;
  type: 'access' | 'refresh';
}

export function generateAccessToken(userId: string, email: string): string {
  return jwt.sign(
    { userId, email, type: 'access' },
    config.jwt.secret,
    { expiresIn: config.jwt.accessTokenExpiry }
  );
}

export function generateRefreshToken(userId: string, email: string): string {
  return jwt.sign(
    { userId, email, type: 'refresh' },
    config.jwt.secret,
    { expiresIn: config.jwt.refreshTokenExpiry }
  );
}

export function verifyToken(token: string): JWTPayload | null {
  try {
    return jwt.verify(token, config.jwt.secret) as JWTPayload;
  } catch {
    return null;
  }
}

export function decodeToken(token: string): JWTPayload | null {
  try {
    return jwt.decode(token) as JWTPayload;
  } catch {
    return null;
  }
}

export function getTokenExpiry(token: string): Date | null {
  const decoded = decodeToken(token);
  if (!decoded || !decoded.exp) return null;
  return new Date(decoded.exp * 1000);
}