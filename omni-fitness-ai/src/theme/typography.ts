import { TextStyle } from "react-native";
import { colors } from "./colors";

export const typography = {
  // Display / Hero
  display: {
    fontSize: 40,
    fontWeight: "800",
    letterSpacing: -1,
    color: colors.textPrimary,
  } as TextStyle,

  // H1
  h1: {
    fontSize: 32,
    fontWeight: "700",
    letterSpacing: -0.5,
    color: colors.textPrimary,
  } as TextStyle,

  // H2
  h2: {
    fontSize: 24,
    fontWeight: "700",
    letterSpacing: -0.25,
    color: colors.textPrimary,
  } as TextStyle,

  // H3
  h3: {
    fontSize: 20,
    fontWeight: "600",
    color: colors.textPrimary,
  } as TextStyle,

  // Body Large
  bodyLarge: {
    fontSize: 18,
    fontWeight: "400",
    lineHeight: 26,
    color: colors.textPrimary,
  } as TextStyle,

  // Body
  body: {
    fontSize: 16,
    fontWeight: "400",
    lineHeight: 24,
    color: colors.textPrimary,
  } as TextStyle,

  // Body Small
  bodySmall: {
    fontSize: 14,
    fontWeight: "400",
    lineHeight: 20,
    color: colors.textSecondary,
  } as TextStyle,

  // Caption
  caption: {
    fontSize: 12,
    fontWeight: "500",
    lineHeight: 16,
    color: colors.textTertiary,
  } as TextStyle,

  // Button text
  button: {
    fontSize: 16,
    fontWeight: "600",
    letterSpacing: 0.25,
    color: colors.textPrimary,
  } as TextStyle,

  // Numeric/Stat
  stat: {
    fontSize: 28,
    fontWeight: "700",
    letterSpacing: -0.5,
    color: colors.textPrimary,
  } as TextStyle,

  statSmall: {
    fontSize: 20,
    fontWeight: "600",
    color: colors.textPrimary,
  } as TextStyle,

  statLarge: {
    fontSize: 48,
    fontWeight: "800",
    letterSpacing: -1,
    color: colors.textPrimary,
  } as TextStyle,
} as const;

export type Typography = typeof typography;
