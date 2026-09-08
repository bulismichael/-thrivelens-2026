import React, { useState } from "react";
import { Pressable, PressableProps, ViewStyle, StyleProp } from "react-native";
import Animated from "react-native-reanimated";

interface PressableScaleProps extends PressableProps {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
  hitSlop?: number;
  pressRetentionOffset?: number;
}

const animatedStyle = {
  transform: [{ scale: 1 }],
  transitionProperty: "transform",
  transitionDuration: "200ms",
  transitionTimingFunction: "ease-out",
};

const pressedStyle = {
  transform: [{ scale: 0.97 }],
};

export function PressableScale({
  children,
  style,
  hitSlop = 12,
  pressRetentionOffset = 16,
  ...rest
}: PressableScaleProps) {
  const [pressed, setPressed] = useState(false);

  return (
    <Pressable
      onPressIn={() => setPressed(true)}
      onPressOut={() => setPressed(false)}
      hitSlop={hitSlop}
      pressRetentionOffset={pressRetentionOffset}
      {...rest}
    >
      <Animated.View style={[animatedStyle, pressed && pressedStyle, style]}>
        {children}
      </Animated.View>
    </Pressable>
  );
}
