/**
 * Seed database with scraped exercises
 * 
 * Usage: npx tsx src/db/seed-scraped.ts
 */

import { pool } from '../config/database';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

interface ScrapedExercise {
  name: string;
  description: string;
  bodyPart: string;
  equipment: string[];
  difficulty: string;
  muscleGroups: string[];
  instructions: string[];
  tips: string[];
  imageUrl: string;
  sourceUrl: string;
  exerciseType: string;
  isCustom: boolean;
}

async function seedScraped() {
  const filePath = join(__dirname, 'scraped-exercises.json');
  
  if (!existsSync(filePath)) {
    console.error('❌ scraped-exercises.json not found. Run npm run db:scrape first.');
    process.exit(1);
  }
  
  try {
    console.log('🌱 Seeding database with scraped exercises...');
    
    const rawData = readFileSync(filePath, 'utf-8');
    const exercises: ScrapedExercise[] = JSON.parse(rawData);
    
    console.log(`Found ${exercises.length} exercises to seed`);
    
    let seeded = 0;
    let skipped = 0;
    
    for (const exercise of exercises) {
      try {
        // Skip if name is empty
        if (!exercise.name || exercise.name.trim() === '') {
          skipped++;
          continue;
        }
        
        // Check if exercise already exists
        const existingCheck = await pool.query(
          'SELECT id FROM exercises WHERE name = $1 AND is_custom = false',
          [exercise.name]
        );
        
        if (existingCheck.rows.length > 0) {
          console.log(`⏭ Skipping duplicate: ${exercise.name}`);
          skipped++;
          continue;
        }
        
        await pool.query(
          `INSERT INTO exercises (
            name, description, body_part, equipment, difficulty, 
            muscle_groups, instructions, image_url, is_custom
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false)`,
          [
            exercise.name,
            exercise.description || `${exercise.name} exercise targeting ${exercise.muscleGroups.join(', ')}`,
            exercise.bodyPart,
            exercise.equipment,
            exercise.difficulty,
            exercise.muscleGroups,
            exercise.instructions.length > 0 ? exercise.instructions : [`Perform ${exercise.name} as shown`],
            exercise.imageUrl,
          ]
        );
        
        seeded++;
        console.log(`✓ ${exercise.name}`);
      } catch (error: any) {
        console.error(`✗ Error seeding ${exercise.name}:`, error.message);
      }
    }
    
    console.log(`\n==========================================`);
    console.log(`✅ Seeded ${seeded} exercises`);
    console.log(`⏭ Skipped ${skipped} exercises`);
    console.log(`📊 Total in database will be checked next...`);
    
    // Count total exercises
    const countResult = await pool.query('SELECT COUNT(*) FROM exercises WHERE is_custom = false');
    console.log(`📋 Total exercises in database: ${countResult.rows[0].count}`);
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }
}

seedScraped();