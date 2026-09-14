import { supabase } from "@/lib/supabase";
import {
  listReadyOperations,
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
      } else {
        throw new Error(`Unsupported outbox operation: ${operation.entity}/${operation.operation}`);
      }
      markOperationSucceeded(operation.operation_id);
    } catch (error) {
      markOperationFailed(
        operation.operation_id,
        operation.attempts,
        error instanceof Error ? error.message : "Unknown sync error",
      );
    }
  }
}
