import React, { useState } from "react";
import { View, ScrollView, Pressable } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Text, Card, SearchInput } from "@/components/ui";

const filters = ["All", "Gym", "Hospital", "Fitness"];

const locations = [
  {
    id: "1",
    name: "FitZone Gym",
    type: "Gym",
    distance: "0.8 km",
    rating: 4.8,
    isOpen: true,
    address: "123 Fitness Street",
  },
  {
    id: "2",
    name: "PowerHouse Fitness",
    type: "Gym",
    distance: "1.2 km",
    rating: 4.6,
    isOpen: true,
    address: "456 Workout Avenue",
  },
  {
    id: "3",
    name: "City Hospital",
    type: "Hospital",
    distance: "2.5 km",
    rating: 4.9,
    isOpen: true,
    address: "789 Health Road",
  },
  {
    id: "4",
    name: "Yoga Studio",
    type: "Fitness",
    distance: "0.5 km",
    rating: 4.7,
    isOpen: false,
    address: "321 Zen Lane",
  },
];

export default function MapsScreen() {
  const [selectedFilter, setSelectedFilter] = useState("All");

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 100 }}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View className="px-6 py-4">
          <Text variant="h1">Maps</Text>
          <Text variant="body" className="text-text-secondary mt-1">
            Find nearby gyms and fitness centers
          </Text>
        </View>

        {/* Search */}
        <View className="px-6 mb-4">
          <SearchInput placeholder="Search locations..." />
        </View>

        {/* Filters */}
        <View className="px-6 mb-6">
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
          >
            <View className="flex-row gap-2">
              {filters.map((filter) => (
                <Pressable
                  key={filter}
                  className={`px-4 py-2 rounded-full ${
                    selectedFilter === filter
                      ? "bg-primary"
                      : "bg-surface-elevated"
                  }`}
                  onPress={() => setSelectedFilter(filter)}
                >
                  <Text
                    variant="bodySmall"
                    className={
                      selectedFilter === filter
                        ? "text-white"
                        : "text-text-secondary"
                    }
                  >
                    {filter}
                  </Text>
                </Pressable>
              ))}
            </View>
          </ScrollView>
        </View>

        {/* Map Placeholder */}
        <View className="px-6 mb-6">
          <Card variant="elevated">
            <View className="h-64 items-center justify-center bg-surface-highlight rounded-xl">
              <Text variant="h1" className="mb-2">
                🗺️
              </Text>
              <Text variant="body" className="text-text-tertiary">
                Map will be displayed here
              </Text>
              <Text variant="caption" className="text-text-tertiary mt-1">
                Integrate with maps SDK
              </Text>
            </View>
          </Card>
        </View>

        {/* Nearby Locations */}
        <View className="px-6">
          <Text variant="h3" className="mb-4">
            Nearby Locations
          </Text>
          <View className="gap-3">
            {locations.map((location) => (
              <Card key={location.id} variant="elevated">
                <View className="flex-row justify-between items-start">
                  <View className="flex-1">
                    <View className="flex-row items-center gap-2 mb-1">
                      <Text variant="body" className="font-semibold">
                        {location.name}
                      </Text>
                      <View
                        className={`px-2 py-0.5 rounded-full ${
                          location.isOpen ? "bg-success/20" : "bg-error/20"
                        }`}
                      >
                        <Text
                          variant="caption"
                          className={
                            location.isOpen ? "text-success" : "text-error"
                          }
                        >
                          {location.isOpen ? "Open" : "Closed"}
                        </Text>
                      </View>
                    </View>
                    <Text variant="bodySmall" className="text-text-secondary mb-1">
                      {location.address}
                    </Text>
                    <View className="flex-row items-center gap-3">
                      <Text variant="caption" className="text-text-tertiary">
                        📍 {location.distance}
                      </Text>
                      <Text variant="caption" className="text-text-tertiary">
                        ⭐ {location.rating}
                      </Text>
                      <Text variant="caption" className="text-text-tertiary">
                        {location.type}
                      </Text>
                    </View>
                  </View>
                  <Pressable className="bg-primary/20 px-4 py-2 rounded-full">
                    <Text variant="bodySmall" className="text-primary">
                      Directions
                    </Text>
                  </Pressable>
                </View>
              </Card>
            ))}
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}
