import { supabase } from "@/lib/supabase";
import {
  listReadyOperations,
  markOperationConflict,
  markOperationFailed,
  markOperationSucceeded,
} from "@/db/outbox";

export async function flushOutbox(userId: string) {
  const operations = listReadyOperations(userId);

  for (const operation of operations) {
    try {
      const payload = JSON.parse(operation.payload) as Record<string, unknown>;
      if (operation.entity === "profiles" && operation.operation === "upsert") {
        const { id, ...updates } = payload;
        const { error } = await supabase
          .from("profiles")
          .update(updates)
          .eq("id", id as string)
          .eq("id", userId);
        if (error) throw error;
      } else if (operation.entity === "food_logs" && operation.operation === "upsert") {
        const { error } = await supabase.from("food_logs").upsert(payload, { onConflict: "id" });
        if (error) throw error;
      } else {
        throw new Error(`Unsupported outbox operation: ${operation.entity}/${operation.operation}`);
      }
      markOperationSucceeded(operation.operation_id);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown sync error";
      if (message.includes("409") || message.includes("412") || message.toLowerCase().includes("conflict")) {
        markOperationConflict(operation.operation_id, message);
        continue;
      }
      markOperationFailed(
        operation.operation_id,
        operation.attempts,
        message,
      );
    }
  }
}
