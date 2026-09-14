import React from "react";
import { Tabs } from "expo-router";
import { View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Home, Dumbbell, BarChart3, Utensils, MapPin, Bot } from "lucide-react-native";

function TabIcon({ name, focused }: { name: string; focused: boolean }) {
  const icons: Record<string, React.ComponentType<{ size: number; color: string; strokeWidth?: number }>> = {
    Home,
    Workout: Dumbbell,
    Tracking: BarChart3,
    Nutrition: Utensils,
    Maps: MapPin,
    "AI Couch": Bot,
  };

  const Icon = icons[name] || Home;
  const color = focused ? "#208AEF" : "#6B6B80";

  return (
    <View style={{ alignItems: "center", justifyContent: "center" }}>
      <Icon size={24} color={color} strokeWidth={focused ? 2.5 : 2} />
    </View>
  );
}

export default function TabLayout() {
  const insets = useSafeAreaInsets();

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: "#208AEF",
        tabBarInactiveTintColor: "#6B6B80",
        tabBarStyle: {
          backgroundColor: "#141419",
          borderTopColor: "#2A2A35",
          borderTopWidth: 1,
          height: 60 + insets.bottom,
          paddingBottom: insets.bottom + 4,
          paddingTop: 8,
        },
        tabBarLabelStyle: {
          fontSize: 12,
          fontWeight: "600",
        },
        headerStyle: {
          backgroundColor: "#0A0A0F",
        },
        headerTintColor: "#FFFFFF",
        headerTitleStyle: {
          fontWeight: "700",
          fontSize: 20,
        },
        headerShadowVisible: false,
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: "Home",
          headerShown: false,
          tabBarIcon: ({ focused }) => <TabIcon name="Home" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="workout"
        options={{
          title: "Workout",
          headerShown: false,
          tabBarIcon: ({ focused }) => <TabIcon name="Workout" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="tracking"
        options={{
          title: "Tracking",
          headerShown: false,
          tabBarIcon: ({ focused }) => <TabIcon name="Tracking" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="nutrition"
        options={{
          title: "Nutrition",
          headerShown: false,
          tabBarIcon: ({ focused }) => <TabIcon name="Nutrition" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="maps"
        options={{
          title: "Maps",
          headerShown: false,
          tabBarIcon: ({ focused }) => <TabIcon name="Maps" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="ai-couch"
        options={{
          title: "AI Couch",
          headerShown: false,
          tabBarIcon: ({ focused }) => <TabIcon name="AI Couch" focused={focused} />,
        }}
      />
    </Tabs>
  );
}


