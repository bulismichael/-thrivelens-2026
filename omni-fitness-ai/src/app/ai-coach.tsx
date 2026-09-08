import React, { useState } from "react";
import { View, ScrollView, Pressable, TextInput } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { Text, Card, Button } from "@/components/ui";

const suggestedPrompts = [
  "Create my workout",
  "Plan my meals",
  "What should I eat today?",
  "Adjust my workout",
  "I'm tired today",
  "What can I make with my food?",
  "Analyze my progress",
];

const sampleMessages = [
  {
    id: "1",
    role: "user",
    content: "I only have chicken, rice and eggs this week. Can you make me a meal plan?",
  },
  {
    id: "2",
    role: "ai",
    content: "Absolutely. I'll build a 7-day plan around what you already have while keeping your protein target in mind.",
  },
];

export default function AICoachScreen() {
  const [message, setMessage] = useState("");
  const [messages, setMessages] = useState(sampleMessages);

  const handleSend = () => {
    if (!message.trim()) return;

    const newMessage = {
      id: Date.now().toString(),
      role: "user",
      content: message,
    };

    setMessages((prev) => [...prev, newMessage]);
    setMessage("");

    // Simulate AI response
    setTimeout(() => {
      const aiResponse = {
        id: (Date.now() + 1).toString(),
        role: "ai",
        content: "I understand. Let me create a personalized plan for you based on your goals and available ingredients.",
      };
      setMessages((prev) => [...prev, aiResponse]);
    }, 1000);
  };

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      {/* Header */}
      <View className="flex-row items-center justify-between px-6 py-4 border-b border-border">
        <Pressable onPress={() => router.back()}>
          <Text variant="body" className="text-primary">
            ← Back
          </Text>
        </Pressable>
        <View className="items-center">
          <Text variant="h3">OMNI AI</Text>
          <Text variant="caption" className="text-text-secondary">
            Your personal fitness coach
          </Text>
        </View>
        <View className="w-12" />
      </View>

      {/* Messages */}
      <ScrollView
        className="flex-1 px-6"
        contentContainerStyle={{ paddingVertical: 16 }}
        showsVerticalScrollIndicator={false}
      >
        {messages.map((msg) => (
          <View
            key={msg.id}
            className={`mb-4 ${msg.role === "user" ? "items-end" : "items-start"}`}
          >
            <View
              className={`max-w-[85%] rounded-2xl px-4 py-3 ${
                msg.role === "user"
                  ? "bg-primary rounded-tr-sm"
                  : "bg-surface-elevated rounded-tl-sm"
              }`}
            >
              {msg.role === "ai" && (
                <View className="flex-row items-center gap-2 mb-2">
                  <View className="w-6 h-6 rounded-full bg-ai-glow/30 items-center justify-center">
                    <Text variant="caption" className="text-ai-glow text-xs">
                      AI
                    </Text>
                  </View>
                  <Text variant="caption" className="text-ai-glow">
                    OMNI AI
                  </Text>
                </View>
              )}
              <Text
                variant="body"
                className={msg.role === "user" ? "text-white" : "text-text-primary"}
              >
                {msg.content}
              </Text>
            </View>
          </View>
        ))}

        {/* AI Thinking Indicator */}
        {messages.length > 0 &&
          messages[messages.length - 1].role === "user" && (
            <View className="items-start mb-4">
              <View className="bg-surface-elevated rounded-2xl rounded-tl-sm px-4 py-3">
                <View className="flex-row items-center gap-2">
                  <View className="w-6 h-6 rounded-full bg-ai-glow/30 items-center justify-center">
                    <Text variant="caption" className="text-ai-glow text-xs">
                      AI
                    </Text>
                  </View>
                  <Text variant="caption" className="text-ai-glow">
                    OMNI is thinking...
                  </Text>
                </View>
              </View>
            </View>
          )}
      </ScrollView>

      {/* Suggested Prompts */}
      <View className="px-6 mb-4">
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
        >
          <View className="flex-row gap-2">
            {suggestedPrompts.map((prompt, index) => (
              <Pressable
                key={index}
                className="bg-surface-elevated px-4 py-2 rounded-full border border-border"
                onPress={() => setMessage(prompt)}
              >
                <Text variant="bodySmall" className="text-text-secondary">
                  {prompt}
                </Text>
              </Pressable>
            ))}
          </View>
        </ScrollView>
      </View>

      {/* Input */}
      <View className="px-6 pb-6">
        <View className="flex-row items-center gap-3 bg-surface-elevated rounded-2xl px-4 py-3 border border-border">
          <Pressable className="w-8 h-8 items-center justify-center">
            <Text variant="body" className="text-text-tertiary">
              📎
            </Text>
          </Pressable>
          <TextInput
            className="flex-1 text-text-primary"
            placeholder="Ask Omni anything..."
            placeholderTextColor="#6B6B80"
            value={message}
            onChangeText={setMessage}
            multiline
          />
          <Pressable className="w-8 h-8 items-center justify-center">
            <Text variant="body" className="text-text-tertiary">
              🎤
            </Text>
          </Pressable>
          <Pressable
            className={`w-8 h-8 rounded-full items-center justify-center ${
              message.trim() ? "bg-primary" : "bg-surface-highlight"
            }`}
            onPress={handleSend}
          >
            <Text variant="body" className="text-white">
              ↑
            </Text>
          </Pressable>
        </View>
      </View>
    </SafeAreaView>
  );
}
