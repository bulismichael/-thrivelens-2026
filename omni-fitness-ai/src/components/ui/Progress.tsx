import React from "react";
import { View, ViewStyle, StyleProp } from "react-native";
import Svg, { Circle } from "react-native-svg";
import { Text } from "./Text";

interface ProgressRingProps {
  progress: number; // 0-100
  size?: number;
  strokeWidth?: number;
  color?: string;
  backgroundColor?: string;
  label?: string;
  value?: string;
  style?: StyleProp<ViewStyle>;
}

export function ProgressRing({
  progress,
  size = 80,
  strokeWidth = 8,
  color = "#208AEF",
  backgroundColor = "#1C1C24",
  label,
  value,
  style,
}: ProgressRingProps) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffset = circumference - (progress / 100) * circumference;

  return (
    <View className="items-center" style={style}>
      <View
        style={{
          width: size,
          height: size,
          borderRadius: size / 2,
          borderWidth: strokeWidth,
          borderColor: backgroundColor,
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <Text variant="stat" className="text-text-primary">
          {value || `${Math.round(progress)}%`}
        </Text>
      </View>
      {label && (
        <Text variant="caption" className="text-text-secondary mt-2">
          {label}
        </Text>
      )}
    </View>
  );
}

// Progress Bar
interface ProgressBarProps {
  progress: number; // 0-100
  height?: number;
  color?: string;
  backgroundColor?: string;
  showLabel?: boolean;
  label?: string;
  style?: StyleProp<ViewStyle>;
}

export function ProgressBar({
  progress,
  height = 8,
  color = "#208AEF",
  backgroundColor = "#1C1C24",
  showLabel = false,
  label,
  style,
}: ProgressBarProps) {
  return (
    <View style={style}>
      {showLabel && label && (
        <View className="flex-row justify-between mb-2">
          <Text variant="caption" className="text-text-secondary">
            {label}
          </Text>
          <Text variant="caption" className="text-text-secondary">
            {Math.round(progress)}%
          </Text>
        </View>
      )}
      <View
        className="rounded-full overflow-hidden"
        style={{
          height,
          backgroundColor,
        }}
      >
        <View
          className="h-full rounded-full"
          style={{
            width: `${Math.min(progress, 100)}%`,
            backgroundColor: color,
          }}
        />
      </View>
    </View>
  );
}

// Circular Progress (for nutrition macros) with SVG
interface CircularProgressProps {
  value: number;
  maxValue: number;
  color: string;
  size?: number;
  strokeWidth?: number;
  label?: string;
}

export function CircularProgress({
  value,
  maxValue,
  color,
  size = 80,
  strokeWidth = 8,
  label,
}: CircularProgressProps) {
  const progress = maxValue > 0 ? Math.min((value / maxValue) * 100, 100) : 0;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffset = circumference - (progress / 100) * circumference;
  const center = size / 2;

  return (
    <View className="items-center">
      <View style={{ width: size, height: size }}>
        <Svg width={size} height={size}>
          {/* Background circle */}
          <Circle
            cx={center}
            cy={center}
            r={radius}
            stroke="#1C1C24"
            strokeWidth={strokeWidth}
            fill="none"
          />
          {/* Progress circle */}
          <Circle
            cx={center}
            cy={center}
            r={radius}
            stroke={color}
            strokeWidth={strokeWidth}
            fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={strokeDashoffset}
            strokeLinecap="round"
            transform={`rotate(-90 ${center} ${center})`}
          />
        </Svg>
        <View
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <Text variant="bodySmall" className="text-text-primary font-bold">
            {Math.round(progress)}%
          </Text>
        </View>
      </View>
      {label && (
        <Text variant="caption" className="text-text-tertiary mt-2">
          {label}
        </Text>
      )}
    </View>
  );
}
