import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import "./global.css";

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <StatusBar style="light" />
      <Stack
        initialRouteName="welcome"
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: "#0a0a1a" },
          animation: "fade",
        }}
      >
        <Stack.Screen name="welcome" />
        <Stack.Screen name="signup" />
        <Stack.Screen name="signin" />
        <Stack.Screen name="onboarding" />
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="exercise-library" />
        <Stack.Screen name="exercise-detail" />
        <Stack.Screen name="ai-coach" options={{ presentation: "modal" }} />
        <Stack.Screen name="food-scanner" options={{ presentation: "modal" }} />
        <Stack.Screen name="active-workout" options={{ presentation: "fullScreenModal" }} />
        <Stack.Screen name="profile" options={{ animation: "slide_from_right" }} />
      </Stack>
    </GestureHandlerRootView>
  );
}
