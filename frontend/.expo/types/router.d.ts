/* eslint-disable */
import * as Router from 'expo-router';

export * from 'expo-router';

declare module 'expo-router' {
  export namespace ExpoRouter {
    export interface __routes<T extends string = string> extends Record<string, unknown> {
      StaticRoutes: `/` | `/(auth)` | `/(auth)/login` | `/(auth)/register` | `/(tabs)` | `/(tabs)/exercises` | `/(tabs)/home` | `/(tabs)/meals` | `/(tabs)/profile` | `/(tabs)/progress` | `/_sitemap` | `/exercises` | `/home` | `/login` | `/meals` | `/onboarding` | `/profile` | `/progress` | `/register`;
      DynamicRoutes: never;
      DynamicRouteTemplate: never;
    }
  }
}
