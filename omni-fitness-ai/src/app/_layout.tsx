import { Stack, useRouter, useSegments } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { useEffect } from "react";
import { AuthProvider, useAuth } from "../providers/AuthProvider";
import "../global.css";

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

    const publicRoutes = ["welcome", "signin", "signup", "forgot-password", "reset-password"];
    const authEntryRoutes = ["welcome", "signin", "signup"];

    const isPublicRoute = segments.some((segment) => publicRoutes.includes(segment));
    const isAuthEntryRoute = segments.some((segment) => authEntryRoutes.includes(segment));

    if (!session && !isPublicRoute) {
      router.replace("/welcome");
    } else if (session && isAuthEntryRoute) {
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