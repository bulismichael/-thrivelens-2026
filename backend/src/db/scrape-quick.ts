/**
 * Quick scraper test - just chest exercises
 */
import { writeFileSync } from 'fs';
import { join } from 'path';

const BASE_URL = 'https://www.muscleandstrength.com';
const DELAY_MS = 1500;

async function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fetchPage(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.text();
}

async function scrapeExercise(path: string): Promise<any> {
  const url = `${BASE_URL}${path}`;
  const html = await fetchPage(url);
  
  const h1Match = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  const name = h1Match ? h1Match[1].replace(/<[^>]+>/g, '').replace(/Video Exercise Guide/g, '').trim() : '';
  
  let targetMuscle = '';
  const tMatch = html.match(/Target Muscle Group[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i) ||
                 html.match(/Target Muscle Group[\s\S]*?<[^>]*>([\s\S]*?)<\/[^>]*>/i);
  if (tMatch) targetMuscle = tMatch[1].replace(/<[^>]+>/g, '').trim();
  
  let equipment = 'Bodyweight';
  const eMatch = html.match(/Equipment Required[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i) ||
                 html.match(/Equipment Required[\s\S]*?<[^>]*>([\s\S]*?)<\/[^>]*>/i);
  if (eMatch) equipment = eMatch[1].replace(/<[^>]+>/g, '').trim();
  
  let difficulty = 'Beginner';
  const dMatch = html.match(/Experience Level[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i) ||
                 html.match(/Experience Level[\s\S]*?<[^>]*>([\s\S]*?)<\/[^>]*>/i);
  if (dMatch) difficulty = dMatch[1].replace(/<[^>]+>/g, '').trim();
  
  let secondaryMuscles = '';
  const sMatch = html.match(/Secondary Muscles[\s\S]*?<[^>]*>([\s\S]*?)<\/[^>]*>/i);
  if (sMatch) secondaryMuscles = sMatch[1].replace(/<[^>]+>/g, '').trim();
  
  let description = '';
  const overviewMatch = html.match(/<h2[^>]*>[^<]*Overview[^<]*<\/h2>([\s\S]*?)(?:<h2|<h3)/i);
  if (overviewMatch) description = overviewMatch[1].replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim().substring(0, 300);
  
  const instructions: string[] = [];
  const instrMatch = html.match(/<h[23][^>]*>[^<]*Instructions[^<]*<\/h[23]>([\s\S]*?)(?:<h[23]|<\/article)/i);
  if (instrMatch) {
    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/gi;
    let match;
    while ((match = liRegex.exec(instrMatch[1])) !== null) {
      const text = match[1].replace(/<[^>]+>/g, '').trim();
      if (text.length > 10) instructions.push(text);
    }
  }
  
  let imageUrl = '';
  const imgMatch = html.match(/content="(https:\/\/cdn\.muscleandstrength\.com[^"]+)"/i);
  if (imgMatch) imageUrl = imgMatch[1];
  
  const bodyPartMap: Record<string, string> = {
    'chest': 'chest', 'biceps': 'arms', 'triceps': 'arms', 'shoulders': 'shoulders',
    'lats': 'back', 'middle-back': 'back', 'lower-back': 'back', 'traps': 'back',
    'abs': 'core', 'obliques': 'core', 'quads': 'legs', 'hamstrings': 'legs',
    'glutes': 'legs', 'calves': 'legs', 'forearms': 'arms',
  };
  
  const bodyPart = bodyPartMap[targetMuscle.toLowerCase()] || 'full_body';
  
  const equipMap: Record<string, string[]> = {
    'Barbell': ['Barbell'], 'Dumbbell': ['Dumbbells'], 'Kettlebell': ['Kettlebell'],
    'Cables': ['Cable Machine'], 'Machine': ['Machine'], 'Bodyweight': ['Bodyweight'],
  };
  
  return { name, description, bodyPart, equipment: equipMap[equipment] || ['Other'], 
           difficulty: difficulty.toLowerCase(), muscleGroups: [targetMuscle, secondaryMuscles].filter(Boolean),
           instructions, imageUrl, sourceUrl: url };
}

async function main() {
  console.log('🏋️ Scraping chest exercises...\n');
  
  const html = await fetchPage(`${BASE_URL}/exercises/chest`);
  const links: string[] = [];
  const linkRegex = /href="(\/exercises\/[^"]+\.html)"/gi;
  let match;
  while ((match = linkRegex.exec(html)) !== null) {
    if (!links.includes(match[1]) && !match[1].includes('category')) links.push(match[1]);
  }
  
  console.log(`Found ${links.length} chest exercises\n`);
  
  const exercises: any[] = [];
  for (const link of links.slice(0, 10)) { // Just first 10
    try {
      const ex = await scrapeExercise(link);
      if (ex.name) {
        exercises.push(ex);
        console.log(`✓ ${ex.name} [${ex.bodyPart}] - ${ex.equipment.join(', ')}`);
      }
      await sleep(DELAY_MS);
    } catch (err: any) {
      console.error(`✗ ${link}: ${err.message}`);
    }
  }
  
  const outputPath = join(__dirname, 'scraped-exercises.json');
  writeFileSync(outputPath, JSON.stringify(exercises, null, 2));
  console.log(`\n✅ Saved ${exercises.length} exercises to ${outputPath}`);
}

main().catch(console.error);