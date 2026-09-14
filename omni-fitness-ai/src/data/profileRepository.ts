import { supabase } from "@/lib/supabase";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { enqueueOperation } from "@/db/outbox";

export type Profile = {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
  age: number | null;
  weight: number | null;
  height: number | null;
  gender: string | null;
  goal: string | null;
  activity_level: string | null;
  experience: string | null;
  calorie_target: number | null;
  protein_target: number | null;
  dietary_preference: string | null;
  training_days_per_week: number | null;
  session_duration_minutes: number | null;
  workout_location: string | null;
  workout_type: string | null;
  onboarding_completed: boolean;
  created_at: string;
  updated_at: string;
};

export type ProfileUpdate = Partial<
  Pick<
    Profile,
    | "display_name"
    | "avatar_url"
    | "age"
    | "weight"
    | "height"
    | "gender"
    | "goal"
    | "activity_level"
    | "experience"
    | "calorie_target"
    | "protein_target"
    | "dietary_preference"
    | "training_days_per_week"
    | "session_duration_minutes"
    | "workout_location"
    | "workout_type"
    | "onboarding_completed"
  >
>;

export async function getCurrentProfile() {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;
  if (!userData.user) throw new Error("You must be signed in to load your profile.");

  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", userData.user.id)
    .single();
  if (error) {
    const cached = await AsyncStorage.getItem(`profile:${userData.user.id}`);
    if (cached) return JSON.parse(cached) as Profile;
    throw error;
  }
  await AsyncStorage.setItem(`profile:${userData.user.id}`, JSON.stringify(data));
  return data as Profile;
}

export async function updateCurrentProfile(update: ProfileUpdate) {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;
  if (!userData.user) throw new Error("You must be signed in to update your profile.");

  const payload = { id: userData.user.id, ...update };
  const cachedProfile = await AsyncStorage.getItem(`profile:${userData.user.id}`);
  const optimistic = {
    ...(cachedProfile ? JSON.parse(cachedProfile) as Profile : { id: userData.user.id }),
    ...update,
    updated_at: new Date().toISOString(),
  };
  await AsyncStorage.setItem(`profile:${userData.user.id}`, JSON.stringify(optimistic));
  const { data, error } = await supabase
    .from("profiles")
    .update(update)
    .eq("id", userData.user.id)
    .select("*")
    .single();
  if (error) {
    enqueueOperation({
      operationId: `${userData.user.id}:profiles:${Date.now()}`,
      userId: userData.user.id,
      entity: "profiles",
      operation: "upsert",
      payload,
    });
    return optimistic as Profile;
  }
  await AsyncStorage.setItem(`profile:${userData.user.id}`, JSON.stringify(data));
  return data as Profile;
}

export async function clearAccountCache(userId: string) {
  const { clearUserOutbox } = await import("@/db/outbox");
  clearUserOutbox(userId);
  await AsyncStorage.removeItem(`profile:${userId}`);
}

export async function exportAccountData(userId: string) {
  const tables = ["profiles", "workout_plans", "workout_days", "workout_exercises", "workout_sessions", "workout_logs", "food_logs", "progress_logs", "notifications"] as const;
  const result: Record<string, unknown[]> = {};
  for (const table of tables) {
    const query = table === "profiles"
      ? supabase.from(table).select("*").eq("id", userId)
      : supabase.from(table).select("*").eq("user_id", userId);
    const { data, error } = await query;
    if (error) throw error;
    result[table] = data ?? [];
  }
  return result;
}

export async function deleteCurrentAccount() {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;
  if (!userData.user) throw new Error("You must be signed in to delete your account.");
  const { error } = await supabase.rpc("delete_current_account");
  if (error) throw error;
  await clearAccountCache(userData.user.id);
  await supabase.auth.signOut();
}
