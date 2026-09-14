import * as Linking from "expo-linking";
import * as WebBrowser from "expo-web-browser";
import type { Provider, Session } from "@supabase/supabase-js";
import { supabase } from "./supabase";

WebBrowser.maybeCompleteAuthSession();

export const authRedirectUrl = Linking.createURL("auth/callback", {
  scheme: "omnifitnessai",
});

function getCallbackParams(url: string) {
  const parsed = Linking.parse(url);
  const fragment = url.split("#")[1] ?? "";
  const fragmentParams = new URLSearchParams(fragment);
  const queryParams = new URLSearchParams(parsed.queryParams as Record<string, string>);

  return {
    accessToken: fragmentParams.get("access_token") ?? queryParams.get("access_token"),
    refreshToken: fragmentParams.get("refresh_token") ?? queryParams.get("refresh_token"),
    type: fragmentParams.get("type") ?? queryParams.get("type"),
  };
}

export async function applyAuthCallback(url: string): Promise<{
  session: Session | null;
  type: string | null;
}> {
  const { accessToken, refreshToken, type } = getCallbackParams(url);

  if (!accessToken || !refreshToken) {
    return { session: null, type };
  }

  const { data, error } = await supabase.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken,
  });

  if (error) {
    throw error;
  }

  return { session: data.session, type };
}

export async function signInWithProvider(provider: Provider) {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo: authRedirectUrl,
      skipBrowserRedirect: true,
    },
  });

  if (error) {
    throw error;
  }

  const result = await WebBrowser.openAuthSessionAsync(data.url, authRedirectUrl);

  if (result.type !== "success") {
    return null;
  }

  const { session } = await applyAuthCallback(result.url);
  return session;
}
