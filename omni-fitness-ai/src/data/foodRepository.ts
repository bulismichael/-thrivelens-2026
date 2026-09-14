import { supabase } from "@/lib/supabase";
import { enqueueOperation } from "@/db/outbox";

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

export type NewFoodLog = Omit<FoodLog, "id" | "user_id"> & { id?: string };

export async function addFoodLog(input: NewFoodLog) {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;
  if (!userData.user) throw new Error("You must be signed in to log food.");
  const payload = {
    id: input.id ?? `${userData.user.id}:food:${Date.now()}`,
    user_id: userData.user.id,
    ...input,
  };
  const { data, error } = await supabase.from("food_logs").insert(payload).select("*").single();
  if (error) {
    enqueueOperation({
      operationId: `${userData.user.id}:food_logs:${payload.id}`,
      userId: userData.user.id,
      entity: "food_logs",
      operation: "upsert",
      payload,
    });
    return payload as FoodLog;
  }
  return data as FoodLog;
}

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
