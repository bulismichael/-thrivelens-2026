export const colors = {
  primary: '#6C63FF',
  primaryDark: '#5A52D5',
  primaryLight: '#8B85FF',
  secondary: '#FF6584',
  secondaryDark: '#E55A75',
  secondaryLight: '#FF85A0',

  background: '#0F0F23',
  surface: '#1A1A2E',
  surfaceLight: '#252542',
  surfaceBorder: '#2D2D4A',

  text: '#FFFFFF',
  textSecondary: '#A0A0B8',
  textMuted: '#6B6B80',

  success: '#4CAF50',
  warning: '#FFC107',
  error: '#FF5252',
  info: '#2196F3',

  white: '#FFFFFF',
  black: '#000000',
  transparent: 'transparent',

  chartBlue: '#6C63FF',
  chartGreen: '#4CAF50',
  chartOrange: '#FF9800',
  chartRed: '#FF5252',
  chartPurple: '#9C27B0',

  skeleton: '#252542',
  skeletonHighlight: '#2D2D4A',

  // Body part colors
  chest: '#FF6B6B',
  back: '#4ECDC4',
  shoulders: '#45B7D1',
  arms: '#96CEB4',
  legs: '#FFEAA7',
  core: '#DDA0DD',
  cardio: '#FF8A80',
  fullBody: '#B39DDB',

  // Meal type colors
  breakfast: '#FFD93D',
  lunch: '#6BCB77',
  dinner: '#4D96FF',
  snack: '#FF6B6B',
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 32,
  xxl: 48,
};

export const borderRadius = {
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  full: 9999,
};

export const typography: any = {
  h1: {
    fontSize: 28,
    fontWeight: '700' as const,
    color: colors.text,
  },
  h2: {
    fontSize: 24,
    fontWeight: '700' as const,
    color: colors.text,
  },
  h3: {
    fontSize: 20,
    fontWeight: '600' as const,
    color: colors.text,
  },
  h4: {
    fontSize: 18,
    fontWeight: '600' as const,
    color: colors.text,
  },
  body: {
    fontSize: 16,
    fontWeight: '400' as const,
    color: colors.text,
  },
  bodySmall: {
    fontSize: 14,
    fontWeight: '400' as const,
    color: colors.textSecondary,
  },
  caption: {
    fontSize: 12,
    fontWeight: '400' as const,
    color: colors.textMuted,
  },
  button: {
    fontSize: 16,
    fontWeight: '600' as const,
    color: colors.white,
  },
};