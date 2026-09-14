import { Stack, useRouter, useSegments } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { useEffect } from "react";
import { AuthProvider, useAuth } from "@/providers/AuthProvider";
import "./global.css";

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <AuthProvider>
        <StatusBar style="light" />
        <AuthGate />
      </AuthProvider>
    </GestureHandlerRootView>
  );
}

function AuthGate() {
  const { session, isLoading } = useAuth();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (isLoading) return;

    const rootSegment = segments[0];
    const isPublicRoute =
      rootSegment === "welcome" ||
      rootSegment === "signin" ||
      rootSegment === "signup" ||
      rootSegment === "forgot-password" ||
      rootSegment === "reset-password";

    if (!session && !isPublicRoute) {
      router.replace("/welcome");
    } else if (session && (rootSegment === "welcome" || rootSegment === "signin")) {
      router.replace("/(tabs)");
    }
  }, [isLoading, router, segments, session]);

  if (isLoading) return null;

  return (
    <Stack
      screenOptions={{
        headerShown: false,
        contentStyle: { backgroundColor: "#0a0a1a" },
        animation: "fade",
      }}
    >
      <Stack.Screen name="welcome" />
      <Stack.Screen name="signup" />
      <Stack.Screen name="signin" />
      <Stack.Screen name="forgot-password" />
      <Stack.Screen name="reset-password" />
      <Stack.Screen name="onboarding" />
      <Stack.Screen name="(tabs)" />
      <Stack.Screen name="exercise-library" />
      <Stack.Screen name="exercise-detail" />
      <Stack.Screen name="ai-coach" options={{ presentation: "modal" }} />
      <Stack.Screen name="food-scanner" options={{ presentation: "modal" }} />
      <Stack.Screen name="active-workout" options={{ presentation: "fullScreenModal" }} />
      <Stack.Screen name="profile" options={{ animation: "slide_from_right" }} />
    </Stack>
  );
}
