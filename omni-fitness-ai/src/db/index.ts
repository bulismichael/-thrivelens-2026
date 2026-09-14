// src/db/index.ts
import { openDatabaseSync } from 'expo-sqlite';
import { drizzle } from 'drizzle-orm/expo-sqlite';
import * as schema from './schema';

const expoDb = openDatabaseSync('omni-fitness.db');

export const db = drizzle(expoDb, { schema });
