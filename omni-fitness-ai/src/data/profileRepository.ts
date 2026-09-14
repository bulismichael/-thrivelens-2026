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
  if (error) throw error;
  await AsyncStorage.setItem(`profile:${userData.user.id}`, JSON.stringify(data));
  return data as Profile;
}

export async function updateCurrentProfile(update: ProfileUpdate) {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;
  if (!userData.user) throw new Error("You must be signed in to update your profile.");

  const payload = { id: userData.user.id, ...update };
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
    throw error;
  }
  await AsyncStorage.setItem(`profile:${userData.user.id}`, JSON.stringify(data));
  return data as Profile;
}

export async function clearAccountCache(userId: string) {
  const { clearUserOutbox } = await import("@/db/outbox");
  clearUserOutbox(userId);
  await AsyncStorage.removeItem(`profile:${userId}`);
}
