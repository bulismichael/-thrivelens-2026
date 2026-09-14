import { useState } from "react";
import { Alert, StyleSheet, Text, TextInput, TouchableOpacity, View } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import { useRouter } from "expo-router";
import { ArrowLeft, Mail } from "lucide-react-native";
import { authRedirectUrl } from "@/lib/auth";
import { supabase } from "@/lib/supabase";

export default function ForgotPassword() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = async () => {
    if (!email.trim()) {
      Alert.alert("Missing email", "Enter the email address for your account.");
      return;
    }

    setIsLoading(true);
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: authRedirectUrl,
    });
    setIsLoading(false);

    if (error) {
      Alert.alert("Unable to send reset email", error.message);
      return;
    }

    Alert.alert("Check your email", "Use the link to choose a new password.", [
      { text: "Back to sign in", onPress: () => router.replace("/signin") },
    ]);
  };

  return (
    <LinearGradient colors={["#0a0a1a", "#0f172a", "#0a0a1a"]} style={styles.container}>
      <View style={styles.content}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <ArrowLeft size={20} color="#FFFFFF" />
        </TouchableOpacity>
        <Text style={styles.title}>Reset password</Text>
        <Text style={styles.subtitle}>We will send a secure reset link to your account email.</Text>
        <View style={styles.inputContainer}>
          <Mail size={18} color="#6B7280" />
          <TextInput
            style={styles.input}
            placeholder="Email Address"
            placeholderTextColor="#6B7280"
            value={email}
            onChangeText={setEmail}
            keyboardType="email-address"
            autoCapitalize="none"
            autoComplete="email"
          />
        </View>
        <TouchableOpacity onPress={handleSubmit} disabled={isLoading} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>{isLoading ? "Sending..." : "Send reset link"}</Text>
        </TouchableOpacity>
      </View>
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { flex: 1, padding: 24, paddingTop: 64 },
  backButton: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: "rgba(255,255,255,0.05)",
    alignItems: "center", justifyContent: "center", marginBottom: 32,
  },
  title: { color: "#FFFFFF", fontSize: 28, fontWeight: "700" },
  subtitle: { color: "#9CA3AF", fontSize: 15, lineHeight: 22, marginTop: 8, marginBottom: 28 },
  inputContainer: {
    flexDirection: "row", alignItems: "center", gap: 12, borderRadius: 16, borderWidth: 1,
    borderColor: "rgba(255,255,255,0.1)", backgroundColor: "rgba(255,255,255,0.04)", paddingHorizontal: 16,
  },
  input: { flex: 1, paddingVertical: 16, color: "#FFFFFF", fontSize: 16 },
  primaryButton: { marginTop: 24, borderRadius: 16, paddingVertical: 16, alignItems: "center", backgroundColor: "#3B82F6" },
  primaryButtonText: { color: "#FFFFFF", fontSize: 17, fontWeight: "600" },
});
