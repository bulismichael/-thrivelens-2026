import React from "react";
import {
  Pressable,
  ActivityIndicator,
  ViewStyle,
  StyleProp,
  PressableProps,
} from "react-native";
import { Text } from "./Text";

type ButtonVariant = "primary" | "secondary" | "ghost" | "destructive" | "accent";
type ButtonSize = "sm" | "md" | "lg";

interface ButtonProps extends PressableProps {
  variant?: ButtonVariant;
  size?: ButtonSize;
  title: string;
  loading?: boolean;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
  icon?: React.ReactNode;
}

const variantStyles: Record<ButtonVariant, { bg: string; text: string; pressed: string }> = {
  primary: {
    bg: "bg-primary",
    text: "text-white",
    pressed: "bg-primary-dark",
  },
  secondary: {
    bg: "bg-surface-elevated",
    text: "text-text-primary",
    pressed: "bg-surface-highlight",
  },
  ghost: {
    bg: "bg-transparent",
    text: "text-primary",
    pressed: "bg-surface",
  },
  destructive: {
    bg: "bg-error",
    text: "text-white",
    pressed: "bg-red-600",
  },
  accent: {
    bg: "bg-accent",
    text: "text-white",
    pressed: "bg-accent-dark",
  },
};

const sizeStyles: Record<ButtonSize, { container: string; text: string }> = {
  sm: {
    container: "py-2 px-4 rounded-lg",
    text: "text-sm",
  },
  md: {
    container: "py-3 px-6 rounded-xl",
    text: "text-base",
  },
  lg: {
    container: "py-4 px-8 rounded-xl",
    text: "text-lg",
  },
};

export function Button({
  variant = "primary",
  size = "md",
  title,
  loading = false,
  disabled = false,
  style,
  icon,
  ...props
}: ButtonProps) {
  const variantStyle = variantStyles[variant];
  const sizeStyle = sizeStyles[size];

  return (
    <Pressable
      className={`
        ${variantStyle.bg}
        ${sizeStyle.container}
        items-center justify-center flex-row gap-2
        ${disabled ? "opacity-50" : ""}
        active:opacity-80
      `}
      disabled={disabled || loading}
      style={style}
      {...props}
    >
      {loading ? (
        <ActivityIndicator color="#FFFFFF" size="small" />
      ) : (
        <>
          {icon}
          <Text
            variant="button"
            className={`${variantStyle.text} ${sizeStyle.text}`}
          >
            {title}
          </Text>
        </>
      )}
    </Pressable>
  );
}
