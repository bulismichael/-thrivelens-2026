/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./App.tsx", "./src/**/*.{js,jsx,ts,tsx}"],
  presets: [require("nativewind/preset")],
  theme: {
    extend: {
      colors: {
        // Brand
        primary: {
          DEFAULT: "#208AEF",
          dark: "#1A6FC0",
          light: "#4DA6FF",
        },
        accent: {
          DEFAULT: "#FF6B35",
          dark: "#FF8555",
        },

        // Semantic
        success: "#34C759",
        warning: "#FF9500",
        error: "#FF3B30",
        info: "#5AC8FA",

        // Backgrounds
        background: "#0A0A0F",
        surface: {
          DEFAULT: "#141419",
          elevated: "#1C1C24",
          highlight: "#24242E",
        },

        // Text
        text: {
          primary: "#FFFFFF",
          secondary: "#A0A0B0",
          tertiary: "#6B6B80",
          inverse: "#0A0A0F",
        },

        // Borders
        border: {
          DEFAULT: "#2A2A35",
          light: "#1E1E28",
        },

        // AI
        ai: {
          glow: "#7B61FF",
          surface: "rgba(123, 97, 255, 0.1)",
        },
      },
      spacing: {
        xs: "4px",
        sm: "8px",
        md: "12px",
        lg: "16px",
        xl: "20px",
        xxl: "24px",
        xxxl: "32px",
        xxxxl: "40px",
        xxxxxl: "48px",
        section: "64px",
      },
      borderRadius: {
        xs: "4px",
        sm: "8px",
        md: "12px",
        lg: "16px",
        xl: "20px",
        xxl: "24px",
      },
      fontSize: {
        display: ["40px", { fontWeight: "800", letterSpacing: "-1px" }],
        h1: ["32px", { fontWeight: "700", letterSpacing: "-0.5px" }],
        h2: ["24px", { fontWeight: "700", letterSpacing: "-0.25px" }],
        h3: ["20px", { fontWeight: "600" }],
        "body-lg": ["18px", { fontWeight: "400", lineHeight: "26px" }],
        body: ["16px", { fontWeight: "400", lineHeight: "24px" }],
        "body-sm": ["14px", { fontWeight: "400", lineHeight: "20px" }],
        caption: ["12px", { fontWeight: "500", lineHeight: "16px" }],
        stat: ["28px", { fontWeight: "700", letterSpacing: "-0.5px" }],
        "stat-sm": ["20px", { fontWeight: "600" }],
        "stat-lg": ["48px", { fontWeight: "800", letterSpacing: "-1px" }],
      },
      boxShadow: {
        sm: "0 1px 2px rgba(0, 0, 0, 0.1)",
        md: "0 4px 8px rgba(0, 0, 0, 0.15)",
        lg: "0 8px 16px rgba(0, 0, 0, 0.2)",
        xl: "0 12px 24px rgba(0, 0, 0, 0.25)",
        "ai-glow": "0 4px 12px rgba(123, 97, 255, 0.3)",
        "primary-glow": "0 4px 12px rgba(32, 138, 239, 0.3)",
      },
    },
  },
  plugins: [],
};
