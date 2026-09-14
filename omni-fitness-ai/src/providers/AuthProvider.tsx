import type { Session } from "@supabase/supabase-js";
import * as Linking from "expo-linking";
import { useRouter } from "expo-router";
import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { PropsWithChildren } from "react";
import { applyAuthCallback } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { clearAccountCache } from "@/data/profileRepository";
import { flushOutbox } from "@/data/sync";

type AuthContextValue = {
  session: Session | null;
  isLoading: boolean;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: PropsWithChildren) {
  const router = useRouter();
  const [session, setSession] = useState<Session | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession().then(({ data, error }) => {
      if (error) {
        console.error("Unable to restore Supabase session", error);
      }
      if (mounted) {
        setSession(data.session);
        setIsLoading(false);
      }
    });

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (mounted) {
        setSession(nextSession);
        setIsLoading(false);
        if (nextSession?.user.id) {
          void flushOutbox(nextSession.user.id);
        }
      }
    });

    const linkingSubscription = Linking.addEventListener("url", ({ url }) => {
      applyAuthCallback(url)
        .then(({ type }) => {
          if (type === "recovery") {
            router.replace("/reset-password");
          }
        })
        .catch((error: unknown) => {
          console.error("Unable to apply auth callback", error);
        });
    });

    Linking.getInitialURL().then((url) => {
      if (!url) return;
      applyAuthCallback(url)
        .then(({ type }) => {
          if (type === "recovery") {
            router.replace("/reset-password");
          }
        })
        .catch((error: unknown) => {
          console.error("Unable to apply initial auth callback", error);
        });
    });

    return () => {
      mounted = false;
      data.subscription.unsubscribe();
      linkingSubscription.remove();
    };
  }, [router]);

  const value = useMemo(
    () => ({
      session,
      isLoading,
      signOut: async () => {
        const userId = session?.user.id;
        const { error } = await supabase.auth.signOut();
        if (error) throw error;
        if (userId) await clearAccountCache(userId);
      },
    }),
    [isLoading, session],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used inside AuthProvider");
  }
  return context;
}
