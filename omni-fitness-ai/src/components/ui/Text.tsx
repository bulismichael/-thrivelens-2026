import React from "react";
import { Text as RNText, TextProps as RNTextProps, StyleSheet } from "react-native";

type TextVariant =
  | "display"
  | "h1"
  | "h2"
  | "h3"
  | "bodyLarge"
  | "body"
  | "bodySmall"
  | "caption"
  | "button"
  | "stat"
  | "statSmall"
  | "statLarge";

interface TextProps extends RNTextProps {
  variant?: TextVariant;
  className?: string;
}

const variantStyles = StyleSheet.create({
  display: {
    fontSize: 40,
    fontWeight: "800",
    letterSpacing: -1,
  },
  h1: {
    fontSize: 32,
    fontWeight: "700",
    letterSpacing: -0.5,
  },
  h2: {
    fontSize: 24,
    fontWeight: "700",
    letterSpacing: -0.25,
  },
  h3: {
    fontSize: 20,
    fontWeight: "600",
  },
  bodyLarge: {
    fontSize: 18,
    fontWeight: "400",
    lineHeight: 26,
  },
  body: {
    fontSize: 16,
    fontWeight: "400",
    lineHeight: 24,
  },
  bodySmall: {
    fontSize: 14,
    fontWeight: "400",
    lineHeight: 20,
  },
  caption: {
    fontSize: 12,
    fontWeight: "500",
    lineHeight: 16,
  },
  button: {
    fontSize: 16,
    fontWeight: "600",
    letterSpacing: 0.25,
  },
  stat: {
    fontSize: 28,
    fontWeight: "700",
    letterSpacing: -0.5,
  },
  statSmall: {
    fontSize: 20,
    fontWeight: "600",
  },
  statLarge: {
    fontSize: 48,
    fontWeight: "800",
    letterSpacing: -1,
  },
});

export function Text({ variant = "body", style, ...props }: TextProps) {
  return (
    <RNText
      style={[variantStyles[variant], { color: "#FFFFFF" }, style]}
      {...props}
    />
  );
}
