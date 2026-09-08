import React, { useState } from "react";
import { View, ScrollView, Pressable, Alert } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { ChevronLeft, Settings, LogOut, Bell, Moon, Shield, HelpCircle, Camera } from "lucide-react-native";
import * as ImagePicker from "expo-image-picker";
import { Text, Card, Avatar } from "@/components/ui";

const menuItems = [
  { icon: Settings, label: "Settings", color: "#A0A0B0" },
  { icon: Bell, label: "Notifications", color: "#A0A0B0" },
  { icon: Moon, label: "Appearance", color: "#A0A0B0" },
  { icon: Shield, label: "Privacy & Security", color: "#A0A0B0" },
  { icon: HelpCircle, label: "Help & Support", color: "#A0A0B0" },
  { icon: LogOut, label: "Sign Out", color: "#FF3B30" },
];

export default function ProfileScreen() {
  const [imageUri, setImageUri] = useState<string | undefined>(undefined);

  const pickImage = async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== "granted") {
      Alert.alert("Permission needed", "Please grant camera roll access to change your profile photo.");
      return;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ["images"],
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.8,
    });

    if (!result.canceled && result.assets[0]) {
      setImageUri(result.assets[0].uri);
    }
  };

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 100 }}
        showsVerticalScrollIndicator={false}
      >
        <View className="flex-row items-center px-6 py-4">
          <Pressable
            onPress={() => router.back()}
            className="w-10 h-10 rounded-full bg-surface-elevated items-center justify-center mr-4"
          >
            <ChevronLeft size={20} color="#FFFFFF" />
          </Pressable>
          <Text variant="h2">Profile</Text>
        </View>

        <View className="items-center px-6 mb-8">
          <Pressable onPress={pickImage} className="relative">
            <Avatar uri={imageUri} initials="A" size="xl" />
            <View className="absolute -bottom-1 -right-1 w-8 h-8 rounded-full bg-primary items-center justify-center border-2 border-background">
              <Camera size={14} color="#FFFFFF" />
            </View>
          </Pressable>
          <Text variant="h2" className="mt-4">
            Alex Johnson
          </Text>
          <Text variant="body" className="text-text-secondary mt-1">
            alex.johnson@email.com
          </Text>
          <Text variant="caption" className="text-text-tertiary mt-1">
            Tap photo to change
          </Text>
        </View>

        <View className="px-6 mb-6">
          <Card variant="elevated">
            <View className="flex-row justify-between">
              <View className="items-center flex-1">
                <Text variant="stat" className="text-primary">
                  76.2
                </Text>
                <Text variant="caption" className="text-text-secondary">
                  Weight (kg)
                </Text>
              </View>
              <View className="items-center flex-1">
                <Text variant="stat" className="text-accent">
                  182
                </Text>
                <Text variant="caption" className="text-text-secondary">
                  Height (cm)
                </Text>
              </View>
              <View className="items-center flex-1">
                <Text variant="stat" className="text-success">
                  24
                </Text>
                <Text variant="caption" className="text-text-secondary">
                  Age
                </Text>
              </View>
            </View>
          </Card>
        </View>

        <View className="px-6">
          {menuItems.map((item, index) => (
            <Pressable
              key={index}
              className="flex-row items-center py-4 border-b border-border-light"
              onPress={() => {}}
            >
              <View className="w-10 h-10 rounded-full bg-surface-elevated items-center justify-center mr-4">
                <item.icon size={18} color={item.color} />
              </View>
              <Text variant="body" className={item.label === "Sign Out" ? "text-error" : "text-text-primary"}>
                {item.label}
              </Text>
            </Pressable>
          ))}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}
