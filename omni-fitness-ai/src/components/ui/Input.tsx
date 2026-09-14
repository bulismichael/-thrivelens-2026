import React from "react";
import { TextInput as RNTextInput, View, Pressable, TextInputProps as RNTextInputProps, ViewStyle, StyleProp } from "react-native";
import { Text } from "./Text";

interface TextInputProps extends RNTextInputProps {
  label?: string;
  error?: string;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
  containerStyle?: StyleProp<ViewStyle>;
}

export function TextInput({
  label,
  error,
  leftIcon,
  rightIcon,
  containerStyle,
  style,
  ...props
}: TextInputProps) {
  return (
    <View style={containerStyle}>
      {label && (
        <Text variant="bodySmall" className="text-text-secondary mb-2">
          {label}
        </Text>
      )}
      <View
        className={`
          flex-row items-center
          bg-surface-elevated
          border ${error ? "border-error" : "border-border"}
          rounded-xl
          px-4 py-3
        `}
      >
        {leftIcon && <View className="mr-3">{leftIcon}</View>}
        <RNTextInput
          className="flex-1 text-text-primary text-base"
          placeholderTextColor="#6B6B80"
          {...props}
        />
        {rightIcon && <View className="ml-3">{rightIcon}</View>}
      </View>
      {error && (
        <Text variant="caption" className="text-error mt-1">
          {error}
        </Text>
      )}
    </View>
  );
}

// Search Input
interface SearchInputProps extends Omit<TextInputProps, "leftIcon"> {
  onSearch?: () => void;
}

export function SearchInput({ onSearch, ...props }: SearchInputProps) {
  return (
    <TextInput
      leftIcon={
        <Text variant="body" className="text-text-tertiary">
          🔍
        </Text>
      }
      placeholder="Search..."
      {...props}
    />
  );
}

// Password Input
interface PasswordInputProps extends Omit<TextInputProps, "rightIcon"> {
  showToggle?: boolean;
}

export function PasswordInput({ showToggle = true, ...props }: PasswordInputProps) {
  const [secure, setSecure] = React.useState(true);

  return (
    <TextInput
      secureTextEntry={secure}
      rightIcon={
        showToggle ? (
          <Pressable onPress={() => setSecure(!secure)}>
            <Text variant="body" className="text-text-tertiary">
              {secure ? "👁️" : "👁️‍🗨️"}
            </Text>
          </Pressable>
        ) : undefined
      }
      {...props}
    />
  );
}
