import React, { useState, useEffect, useMemo } from "react";
import { View, ScrollView, Pressable, useWindowDimensions } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Text, Card, ProgressBar } from "@/components/ui";
import Animated, {
  FadeInDown,
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  interpolate,
  Easing,
} from "react-native-reanimated";
import Svg, { Path, Circle, Rect, Line, Defs, LinearGradient, Stop } from "react-native-svg";

const EASE_OUT = Easing.bezier(0.23, 1, 0.32, 1);

const timeFilters = ["7D", "30D", "3M", "6M", "1Y"];

const stats = [
  { label: "Calories", value: "1,850", unit: "kcal", change: "+12%", color: "text-accent", svgColor: "#FF6B35" },
  { label: "Protein", value: "145", unit: "g", change: "+8%", color: "text-primary", svgColor: "#208AEF" },
  { label: "Steps", value: "8,420", unit: "steps", change: "+15%", color: "text-success", svgColor: "#34C759" },
  { label: "Workout", value: "45", unit: "min", change: "+5%", color: "text-warning", svgColor: "#FF9500" },
];

const weightData = [78.5, 78.2, 77.8, 77.5, 77.1, 76.8, 76.5, 76.2];

const caloriesData = [
  { day: "Mon", value: 2100, target: 2200 },
  { day: "Tue", value: 1950, target: 2200 },
  { day: "Wed", value: 2250, target: 2200 },
  { day: "Thu", value: 2050, target: 2200 },
  { day: "Fri", value: 2150, target: 2200 },
  { day: "Sat", value: 2300, target: 2200 },
  { day: "Sun", value: 2100, target: 2200 },
];

function AnimatedLineChart({ width, height }: { width: number; height: number }) {
  const progress = useSharedValue(0);

  useEffect(() => {
    progress.set(withTiming(1, { duration: 1200, easing: EASE_OUT }));
  }, []);

  const animatedStyle = useAnimatedStyle(() => ({ opacity: progress.get() }));

  const padding = { top: 10, right: 10, bottom: 20, left: 10 };
  const chartWidth = width - padding.left - padding.right;
  const chartHeight = height - padding.top - padding.bottom;

  const min = Math.min(...weightData) - 0.5;
  const max = Math.max(...weightData) + 0.5;

  const points = weightData.map((val, i) => ({
    x: padding.left + (i / (weightData.length - 1)) * chartWidth,
    y: padding.top + ((max - val) / (max - min)) * chartHeight,
  }));

  const linePath = points
    .map((p, i) => `${i === 0 ? "M" : "L"} ${p.x} ${p.y}`)
    .join(" ");

  const areaPath =
    linePath +
    ` L ${points[points.length - 1].x} ${padding.top + chartHeight} L ${points[0].x} ${padding.top + chartHeight} Z`;

  return (
    <Animated.View style={animatedStyle}>
      <Svg width={width} height={height}>
        <Defs>
          <LinearGradient id="areaGrad" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor="#208AEF" stopOpacity={0.25} />
            <Stop offset="1" stopColor="#208AEF" stopOpacity={0.02} />
          </LinearGradient>
          <LinearGradient id="lineGrad" x1="0" y1="0" x2="1" y2="0">
            <Stop offset="0" stopColor="#208AEF" />
            <Stop offset="1" stopColor="#7B61FF" />
          </LinearGradient>
        </Defs>
        {[0, 0.25, 0.5, 0.75, 1].map((ratio, i) => (
          <Line
            key={i}
            x1={padding.left}
            y1={padding.top + chartHeight * ratio}
            x2={padding.left + chartWidth}
            y2={padding.top + chartHeight * ratio}
            stroke="#2A2A35"
            strokeWidth={0.5}
          />
        ))}
        <Path d={areaPath} fill="url(#areaGrad)" />
        <Path d={linePath} fill="none" stroke="url(#lineGrad)" strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" />
        {points.map((p, i) => (
          <Circle key={i} cx={p.x} cy={p.y} r={3} fill="#208AEF" />
        ))}
        <Circle cx={points[points.length - 1].x} cy={points[points.length - 1].y} r={5} fill="#7B61FF" />
        <Circle cx={points[points.length - 1].x} cy={points[points.length - 1].y} r={2.5} fill="#FFFFFF" />
      </Svg>
    </Animated.View>
  );
}

function AnimatedBarChart({ width, height }: { width: number; height: number }) {
  const [animated, setAnimated] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => setAnimated(true), 100);
    return () => clearTimeout(t);
  }, []);

  const padding = { top: 10, right: 10, bottom: 24, left: 10 };
  const chartWidth = width - padding.left - padding.right;
  const chartHeight = height - padding.top - padding.bottom;

  const maxVal = Math.max(...caloriesData.map((d) => Math.max(d.value, d.target)));
  const barWidth = (chartWidth / caloriesData.length) * 0.6;
  const gap = (chartWidth / caloriesData.length) * 0.4;

  return (
    <Svg width={width} height={height}>
      <Defs>
        <LinearGradient id="barGrad" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#FF6B35" />
          <Stop offset="1" stopColor="#FF8555" />
        </LinearGradient>
      </Defs>
      {[0, 0.25, 0.5, 0.75, 1].map((ratio, i) => (
        <Line
          key={i}
          x1={padding.left}
          y1={padding.top + chartHeight * ratio}
          x2={padding.left + chartWidth}
          y2={padding.top + chartHeight * ratio}
          stroke="#2A2A35"
          strokeWidth={0.5}
        />
      ))}
      {caloriesData.map((d, i) => {
        const barH = animated ? (d.value / maxVal) * chartHeight : 0;
        const x = padding.left + i * (barWidth + gap) + gap / 2;
        return (
          <React.Fragment key={i}>
            <Rect
              x={x}
              y={padding.top + chartHeight - barH}
              width={barWidth}
              height={barH}
              rx={4}
              fill="url(#barGrad)"
            />
            <Rect
              x={x}
              y={padding.top}
              width={barWidth}
              height={chartHeight}
              rx={4}
              fill="transparent"
              stroke="#FF6B35"
              strokeWidth={0.5}
              strokeOpacity={0.2}
            />
          </React.Fragment>
        );
      })}
    </Svg>
  );
}

function AnimatedProgress({ progress: target, color }: { progress: number; color: string }) {
  const width = useSharedValue(0);

  useEffect(() => {
    width.set(withTiming(target, { duration: 800, easing: EASE_OUT }));
  }, []);

  const style = useAnimatedStyle(() => ({
    width: `${width.get()}%`,
  }));

  return (
    <View className="h-2 rounded-full bg-surface-highlight overflow-hidden">
      <Animated.View style={[{ height: "100%", borderRadius: 999, backgroundColor: color }, style]} />
    </View>
  );
}

export default function TrackingScreen() {
  const [selectedTime, setSelectedTime] = useState("30D");
  const { width: screenWidth } = useWindowDimensions();
  const chartWidth = screenWidth - 48;

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 100 }}
        showsVerticalScrollIndicator={false}
      >
        <View className="px-6 py-4">
          <Text variant="h1">Tracking</Text>
          <Text variant="body" className="text-text-secondary mt-1">
            Your fitness analytics dashboard
          </Text>
        </View>

        <View className="px-6 mb-6">
          <View className="flex-row bg-surface-elevated rounded-xl p-1">
            {timeFilters.map((time) => (
              <Pressable
                key={time}
                className={`flex-1 py-2 rounded-lg ${
                  selectedTime === time ? "bg-primary" : ""
                }`}
                onPress={() => setSelectedTime(time)}
              >
                <Text
                  variant="bodySmall"
                  className={`text-center font-semibold ${
                    selectedTime === time ? "text-white" : "text-text-secondary"
                  }`}
                >
                  {time}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>

        <View className="px-6 mb-6">
          <Text variant="h3" className="mb-4">
            Today's Statistics
          </Text>
          <View className="flex-row flex-wrap gap-3">
            {stats.map((stat, index) => (
              <Animated.View
                key={index}
                entering={FadeInDown.duration(500).delay(index * 100).easing(EASE_OUT)}
                className="w-[48%]"
              >
                <Card variant="elevated">
                  <Text variant="caption" className="text-text-tertiary mb-1">
                    {stat.label}
                  </Text>
                  <View className="flex-row items-baseline gap-1">
                    <Text variant="stat" className={stat.color}>
                      {stat.value}
                    </Text>
                    <Text variant="bodySmall" className="text-text-tertiary">
                      {stat.unit}
                    </Text>
                  </View>
                  <Text variant="caption" className="text-success mt-1">
                    {stat.change}
                  </Text>
                </Card>
              </Animated.View>
            ))}
          </View>
        </View>

        <Animated.View
          entering={FadeInDown.duration(500).delay(320).easing(EASE_OUT)}
          className="px-6 mb-6"
        >
          <Text variant="h3" className="mb-4">
            Weight Progress
          </Text>
          <Card variant="elevated">
            <AnimatedLineChart width={chartWidth - 32} height={160} />
            <Text variant="caption" className="text-text-tertiary mt-2">
              Weight: 78.5 kg → 76.2 kg (-2.3 kg)
            </Text>
            <View className="flex-row justify-between mt-4">
              <View>
                <Text variant="caption" className="text-text-tertiary">
                  Start
                </Text>
                <Text variant="body" className="text-text-primary">
                  78.5 kg
                </Text>
              </View>
              <View className="items-center">
                <Text variant="caption" className="text-text-tertiary">
                  Current
                </Text>
                <Text variant="body" className="text-primary">
                  76.2 kg
                </Text>
              </View>
              <View className="items-end">
                <Text variant="caption" className="text-text-tertiary">
                  Goal
                </Text>
                <Text variant="body" className="text-success">
                  75.0 kg
                </Text>
              </View>
            </View>
          </Card>
        </Animated.View>

        <Animated.View
          entering={FadeInDown.duration(500).delay(400).easing(EASE_OUT)}
          className="px-6 mb-6"
        >
          <Text variant="h3" className="mb-4">
            Calories Intake
          </Text>
          <Card variant="elevated">
            <AnimatedBarChart width={chartWidth - 32} height={160} />
            <View className="flex-row justify-between mt-4">
              <View className="items-center">
                <Text variant="statSmall" className="text-accent">
                  2,100
                </Text>
                <Text variant="caption" className="text-text-tertiary">
                  Average
                </Text>
              </View>
              <View className="items-center">
                <Text variant="statSmall" className="text-primary">
                  2,200
                </Text>
                <Text variant="caption" className="text-text-tertiary">
                  Target
                </Text>
              </View>
              <View className="items-center">
                <Text variant="statSmall" className="text-success">
                  95%
                </Text>
                <Text variant="caption" className="text-text-tertiary">
                  Adherence
                </Text>
              </View>
            </View>
          </Card>
        </Animated.View>

        <Animated.View
          entering={FadeInDown.duration(500).delay(480).easing(EASE_OUT)}
          className="px-6 mb-6"
        >
          <Text variant="h3" className="mb-4">
            Strength Progression
          </Text>
          <Card variant="elevated">
            <View className="gap-3">
              <View className="flex-row justify-between items-center">
                <Text variant="body">Bench Press</Text>
                <Text variant="body" className="text-primary font-semibold">
                  80 kg → 85 kg
                </Text>
              </View>
              <AnimatedProgress progress={85} color="#208AEF" />
              <View className="flex-row justify-between items-center">
                <Text variant="body">Squat</Text>
                <Text variant="body" className="text-primary font-semibold">
                  100 kg → 110 kg
                </Text>
              </View>
              <AnimatedProgress progress={90} color="#34C759" />
              <View className="flex-row justify-between items-center">
                <Text variant="body">Deadlift</Text>
                <Text variant="body" className="text-primary font-semibold">
                  120 kg → 125 kg
                </Text>
              </View>
              <AnimatedProgress progress={75} color="#FF9500" />
            </View>
          </Card>
        </Animated.View>
      </ScrollView>
    </SafeAreaView>
  );
}
