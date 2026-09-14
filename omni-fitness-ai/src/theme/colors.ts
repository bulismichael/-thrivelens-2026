import { Platform } from "react-native";

const brandPalette = {
  light: {
    primary: "#208AEF",
    primaryDark: "#1A6FC0",
    accent: "#FF6B35",
    accentDark: "#FF8555",
    success: "#34C759",
    warning: "#FF9500",
    error: "#FF3B30",
    info: "#5AC8FA",
  },
  dark: {
    primary: "#4DA6FF",
    primaryDark: "#208AEF",
    accent: "#FF8555",
    accentDark: "#FF6B35",
    success: "#30D158",
    warning: "#FFB340",
    error: "#FF453A",
    info: "#64D2FF",
  },
} as const;

function useBrandColors() {
  const scheme =
    Platform.OS === "ios"
      ? "light"
      : "light"; // Will be replaced with useColorScheme in components
  return brandPalette[scheme];
}

export const colors = {
  // Brand
  primary: "#208AEF",
  primaryDark: "#1A6FC0",
  accent: "#FF6B35",

  // Semantic
  success: "#34C759",
  warning: "#FF9500",
  error: "#FF3B30",
  info: "#5AC8FA",

  // Backgrounds
  background: "#0A0A0F",
  surface: "#141419",
  surfaceElevated: "#1C1C24",
  surfaceHighlight: "#24242E",

  // Text
  textPrimary: "#FFFFFF",
  textSecondary: "#A0A0B0",
  textTertiary: "#6B6B80",
  textInverse: "#0A0A0F",

  // Borders
  border: "#2A2A35",
  borderLight: "#1E1E28",

  // Overlays
  overlay: "rgba(0, 0, 0, 0.6)",
  overlayLight: "rgba(0, 0, 0, 0.3)",

  // Gradient stops
  gradientStart: "#208AEF",
  gradientEnd: "#7B61FF",

  // AI specific
  aiGlow: "#7B61FF",
  aiSurface: "rgba(123, 97, 255, 0.1)",
} as const;

export type Colors = typeof colors;
