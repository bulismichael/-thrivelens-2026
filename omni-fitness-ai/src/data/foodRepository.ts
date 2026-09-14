import { supabase } from "@/lib/supabase";

export type FoodLog = {
  id: string;
  user_id: string;
  logged_at: string;
  meal_type: string;
  food_name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

export async function getTodayFoodSummary() {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const { data, error } = await supabase
    .from("food_logs")
    .select("calories, protein, carbs, fat")
    .gte("logged_at", start.toISOString());
  if (error) throw error;

  return (data as Pick<FoodLog, "calories" | "protein" | "carbs" | "fat">[]).reduce(
    (summary, log) => ({
      calories: summary.calories + (log.calories ?? 0),
      protein: summary.protein + (log.protein ?? 0),
      carbs: summary.carbs + (log.carbs ?? 0),
      fat: summary.fat + (log.fat ?? 0),
    }),
    { calories: 0, protein: 0, carbs: 0, fat: 0 },
  );
}
