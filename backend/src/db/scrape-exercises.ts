/**
 * Exercise Scraper for Muscle & Strength (No external deps)
 * 
 * Usage: npx tsx src/db/scrape-exercises.ts
 */

import { writeFileSync } from 'fs';
import { join } from 'path';

const BASE_URL = 'https://www.muscleandstrength.com';
const DELAY_MS = 1500;

const MUSCLE_GROUP_MAP: Record<string, string> = {
  'chest': 'chest', 'biceps': 'arms', 'triceps': 'arms', 'shoulders': 'shoulders',
  'lats': 'back', 'middle-back': 'back', 'lower-back': 'back', 'traps': 'back',
  'abs': 'core', 'obliques': 'core', 'quads': 'legs', 'hamstrings': 'legs',
  'glutes': 'legs', 'calves': 'legs', 'forearms': 'arms',
};

const DIFFICULTY_MAP: Record<string, string> = {
  'beginner': 'beginner', 'intermediate': 'intermediate', 'advanced': 'advanced',
};

const MUSCLE_GROUPS = [
  'chest', 'abs', 'shoulders', 'biceps', 'triceps',
  'quads', 'hamstrings', 'glutes', 'calves', 'forearms',
  'lats', 'middle-back', 'lower-back', 'traps'
];

async function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fetchPage(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Accept': 'text/html,application/xhtml+xml',
    },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.text();
}

function extractBetween(html: string, start: string, end: string): string {
  const s = html.indexOf(start);
  if (s === -1) return '';
  const e = html.indexOf(end, s + start.length);
  if (e === -1) return html.substring(s + start.length);
  return html.substring(s + start.length, e);
}

function _extractList(html: string, listStart: string): string[] {
  const items: string[] = [];
  const listIdx = html.indexOf(listStart);
  if (listIdx === -1) return items;
  
  const listHtml = html.substring(listIdx);
  const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/gi;
  let match;
  while ((match = liRegex.exec(listHtml)) !== null) {
    const text = match[1].replace(/<[^>]+>/g, '').trim();
    if (text && text.length > 5 && !text.includes('Share') && !text.includes('Subscribe')) {
      items.push(text);
    }
    if (items.length >= 15) break;
  }
  return items;
}

function _extractText(html: string, startMarker: string, endMarker?: string): string {
  const idx = html.indexOf(startMarker);
  if (idx === -1) return '';
  let text = html.substring(idx + startMarker.length);
  if (endMarker) {
    const endIdx = text.indexOf(endMarker);
    if (endIdx !== -1) text = text.substring(0, endIdx);
  }
  return text.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
}

async function getExerciseLinks(category: string): Promise<string[]> {
  const url = `${BASE_URL}/exercises/${category}`;
  console.log(`  Fetching category: ${category}`);
  
  const html = await fetchPage(url);
  const links: string[] = [];
  
  // Match exercise links like /exercises/something.html
  const linkRegex = /href="(\/exercises\/[^"]+\.html)"/gi;
  let match;
  while ((match = linkRegex.exec(html)) !== null) {
    const link = match[1];
    if (!links.includes(link) && !link.includes('category')) {
      links.push(link);
    }
  }
  
  return [...new Set(links)];
}

async function scrapeExercise(path: string): Promise<any> {
  const url = `${BASE_URL}${path}`;
  const html = await fetchPage(url);
  
  // Extract name from <h1>
  const h1Match = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  const name = h1Match ? h1Match[1].replace(/<[^>]+>/g, '').replace(/Video Exercise Guide/gi, '').trim() : '';
  
  // Extract profile items from the exercise profile section
  let targetMuscle = '';
  let equipment = 'Bodyweight';
  let difficulty = 'Beginner';
  let secondaryMuscles = '';
  
  // Look for "Target Muscle Group" and similar labels
  const targetMatch = html.match(/Target Muscle Group[\s\S]*?<[^>]*>([\s\S]*?)<\/[^>]*>/i);
  if (targetMatch) targetMuscle = targetMatch[1].replace(/<[^>]+>/g, '').trim();
  
  const equipMatch = html.match(/Equipment Required[\s\S]*?<[^>]*>([\s\S]*?)<\/[^>]*>/i);
  if (equipMatch) equipment = equipMatch[1].replace(/<[^>]+>/g, '').trim();
  
  const diffMatch = html.match(/Experience Level[\s\S]*?<[^>]*>([\s\S]*?)<\/[^>]*>/i);
  if (diffMatch) difficulty = diffMatch[1].replace(/<[^>]+>/g, '').trim();
  
  const secondaryMatch = html.match(/Secondary Muscles[\s\S]*?<[^>]*>([\s\S]*?)<\/[^>]*>/i);
  if (secondaryMatch) secondaryMuscles = secondaryMatch[1].replace(/<[^>]+>/g, '').trim();
  
  // If no profile found, try alternative extraction
  if (!targetMuscle) {
    // Look for exercise profile list items
    const profileSection = extractBetween(html, 'exercise-profile', '</ul>');
    if (profileSection) {
      const tMatch = profileSection.match(/Target Muscle Group[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i);
      if (tMatch) targetMuscle = tMatch[1].replace(/<[^>]+>/g, '').trim();
    }
  }
  
  // Extract description
  let description = '';
  const overviewMatch = html.match(/<h2[^>]*>[^<]*Overview[^<]*<\/h2>([\s\S]*?)(?:<h2|<h3)/i);
  if (overviewMatch) {
    description = overviewMatch[1].replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim().substring(0, 500);
  }
  
  // Extract instructions
  const instructions: string[] = [];
  const instrMatch = html.match(/<h2[^>]*>[^<]*Instructions[^<]*<\/h2>([\s\S]*?)(?:<h2|<h3)/i) ||
                     html.match(/<h3[^>]*>[^<]*Instructions[^<]*<\/h3>([\s\S]*?)(?:<h2|<h3)/i);
  if (instrMatch) {
    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/gi;
    let match;
    while ((match = liRegex.exec(instrMatch[1])) !== null) {
      const text = match[1].replace(/<[^>]+>/g, '').trim();
      if (text.length > 10) instructions.push(text);
    }
  }
  
  // Extract tips
  const tips: string[] = [];
  const tipsMatch = html.match(/<h2[^>]*>[^<]*Tips[^<]*<\/h2>([\s\S]*?)(?:<h2|<h3)/i) ||
                    html.match(/<h3[^>]*>[^<]*Tips[^<]*<\/h3>([\s\S]*?)(?:<h2|<h3)/i);
  if (tipsMatch) {
    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/gi;
    let match;
    while ((match = liRegex.exec(tipsMatch[1])) !== null) {
      const text = match[1].replace(/<[^>]+>/g, '').trim();
      if (text.length > 10) tips.push(text);
    }
  }
  
  // Extract image
  let imageUrl = '';
  const imgMatch = html.match(/<meta[^>]*property="og:image"[^>]*content="([^"]+)"/i) ||
                   html.match(/content="([^"]+)"[^>]*property="og:image"/i);
  if (imgMatch) imageUrl = imgMatch[1];
  
  // Map body part
  const bodyPartKey = targetMuscle.toLowerCase().replace(/\s+/g, '-');
  const bodyPart = MUSCLE_GROUP_MAP[bodyPartKey] || 'full_body';
  
  // Map equipment
  const equipMap: Record<string, string[]> = {
    'Barbell': ['Barbell'], 'Dumbbell': ['Dumbbells'], 'Kettlebell': ['Kettlebell'],
    'Cables': ['Cable Machine'], 'Bands': ['Resistance Bands'], 'Machine': ['Machine'],
    'Bodyweight': ['Bodyweight'], 'Smith Machine': ['Smith Machine'],
    'EZ Bar': ['EZ Bar'], 'Exercise Ball': ['Exercise Ball'],
  };
  const equipArray = equipMap[equipment] || ['Other'];
  
  // Map difficulty
  const diffKey = difficulty.toLowerCase();
  const diffMapped = DIFFICULTY_MAP[diffKey] || 'beginner';
  
  // Combine muscle groups
  const muscleGroups = [targetMuscle];
  if (secondaryMuscles) {
    secondaryMuscles.split(',').forEach(m => {
      const t = m.trim();
      if (t) muscleGroups.push(t);
    });
  }
  
  return {
    name,
    description,
    bodyPart,
    equipment: equipArray,
    difficulty: diffMapped,
    muscleGroups,
    instructions: instructions.length > 0 ? instructions : [`Perform ${name} with proper form`],
    tips,
    imageUrl,
    sourceUrl: url,
  };
}

async function main() {
  console.log('🏋️ Exercise Scraper for Muscle & Strength');
  console.log('==========================================\n');
  
  const allExercises: any[] = [];
  const scrapedPaths = new Set<string>();
  
  for (const muscleGroup of MUSCLE_GROUPS) {
    console.log(`\n--- ${muscleGroup.toUpperCase()} ---`);
    
    try {
      const links = await getExerciseLinks(muscleGroup);
      console.log(`  Found ${links.length} exercises`);
      
      for (const link of links) {
        if (scrapedPaths.has(link)) continue;
        
        try {
          const exercise = await scrapeExercise(link);
          if (exercise.name && exercise.name.length > 2) {
            allExercises.push(exercise);
            scrapedPaths.add(link);
            console.log(`  ✓ ${exercise.name} [${exercise.bodyPart}]`);
          }
          await sleep(DELAY_MS);
        } catch (err: any) {
          console.error(`  ✗ Error: ${err.message}`);
        }
      }
    } catch (err: any) {
      console.error(`  ✗ Category error: ${err.message}`);
    }
  }
  
  const outputPath = join(__dirname, 'scraped-exercises.json');
  writeFileSync(outputPath, JSON.stringify(allExercises, null, 2));
  
  console.log(`\n==========================================`);
  console.log(`✅ Scraped ${allExercises.length} exercises`);
  console.log(`📁 Saved to: ${outputPath}`);
}

main().catch(console.error);