import { View, Text, TouchableOpacity, Dimensions, ScrollView, StyleSheet } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import { Zap, Brain, Utensils, Dumbbell, ArrowRight } from 'lucide-react-native';

const { width } = Dimensions.get('window');

export default function Welcome() {
  const router = useRouter();

  return (
    <LinearGradient
      colors={['#0a0a1a', '#0f172a', '#0a0a1a']}
      style={styles.container}
    >
      {/* Background Decorative Elements */}
      <View style={styles.bgContainer} pointerEvents="none">
        <View style={[styles.glow, { width: 320, height: 320, top: -120, right: -120, backgroundColor: 'rgba(59,130,246,0.12)' }]} />
        <View style={[styles.glow, { width: 200, height: 200, top: -60, right: -60, backgroundColor: 'rgba(139,92,246,0.08)' }]} />
        <View style={[styles.glow, { width: 380, height: 380, bottom: -180, left: -180, backgroundColor: 'rgba(59,130,246,0.08)' }]} />
        <View style={[styles.glow, { width: 220, height: 220, bottom: -80, left: -80, backgroundColor: 'rgba(139,92,246,0.06)' }]} />
      </View>

      <ScrollView style={styles.scrollView} contentContainerStyle={styles.scrollContent}>
        {/* Hero Visual */}
        <View style={styles.heroSection}>
          <View style={styles.ringsContainer}>
            <View style={[styles.ring, { width: 220, height: 220, borderColor: 'rgba(59,130,246,0.2)' }]} />
            <View style={[styles.ring, { width: 170, height: 170, borderColor: 'rgba(139,92,246,0.25)' }]} />
            <View style={[styles.ring, { width: 120, height: 120, borderColor: 'rgba(59,130,246,0.35)' }]} />
            <View style={[styles.centerGlow, { width: 90, height: 90 }]} />
            <View style={styles.centerIcon}>
              <Dumbbell size={34} color="#FFFFFF" strokeWidth={2.5} />
            </View>
            <View style={[styles.dot, styles.dotBlue, { top: 0, left: 106 }]} />
            <View style={[styles.dot, styles.dotPurple, { bottom: 25, right: 15 }]} />
            <View style={[styles.dot, styles.dotLightBlue, { top: 30, left: 10 }]} />
          </View>

          <Text style={styles.brandName}>OMNI</Text>
          <Text style={styles.brandSub}>FITNESS AI</Text>
          <Text style={styles.tagline}>
            Your AI-powered fitness companion.{'\n'}Train smarter. Eat better. Achieve more.
          </Text>
        </View>

        {/* Feature Cards */}
        <View style={styles.featuresSection}>
          <FeatureCard icon={<Zap size={20} color="#60A5FA" />} text="AI-Powered Workouts & Nutrition" subtitle="Personalized plans that adapt to you" />
          <FeatureCard icon={<Brain size={20} color="#A78BFA" />} text="Smart Progress Tracking" subtitle="Analytics that drive real results" containerStyle={{ marginTop: 12 }} />
          <FeatureCard icon={<Utensils size={20} color="#60A5FA" />} text="Food Scanner & Meal Planning" subtitle="Scan, track, and optimize nutrition" containerStyle={{ marginTop: 12 }} />
        </View>

        {/* CTAs */}
        <View style={styles.ctaSection}>
          <TouchableOpacity 
            onPress={() => router.push('/signup')} 
            style={styles.primaryButton}
            activeOpacity={0.8}
          >
            <View style={styles.buttonContent}>
              <Text style={styles.primaryButtonText}>Get Started</Text>
              <ArrowRight size={18} color="#FFFFFF" style={{ marginLeft: 8 }} />
            </View>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => router.push('/signin')} 
            style={styles.secondaryButton}
            activeOpacity={0.8}
          >
            <Text style={styles.secondaryButtonText}>Sign In</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </LinearGradient>
  );
}

function FeatureCard({ icon, text, subtitle, containerStyle = {} }: {
  icon: React.ReactNode; text: string; subtitle: string; containerStyle?: object;
}) {
  return (
    <View style={[styles.featureCard, containerStyle]}>
      <View style={styles.featureIcon}>
        {icon}
      </View>
      <View style={styles.featureText}>
        <Text style={styles.featureTitle}>{text}</Text>
        <Text style={styles.featureSubtitle}>{subtitle}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  bgContainer: {
    ...StyleSheet.absoluteFill,
    overflow: 'hidden',
  },
  glow: {
    position: 'absolute',
    borderRadius: 999,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: 24,
    paddingTop: 64,
    paddingBottom: 32,
  },
  heroSection: {
    alignItems: 'center',
    marginTop: 16,
  },
  ringsContainer: {
    width: 220,
    height: 220,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ring: {
    position: 'absolute',
    borderRadius: 999,
    borderWidth: 1.5,
  },
  centerGlow: {
    position: 'absolute',
    borderRadius: 999,
    backgroundColor: 'rgba(59,130,246,0.15)',
  },
  centerIcon: {
    width: 76,
    height: 76,
    borderRadius: 38,
    backgroundColor: '#3B82F6',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#3B82F6',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.5,
    shadowRadius: 16,
    elevation: 8,
  },
  dot: {
    position: 'absolute',
    borderRadius: 999,
  },
  dotBlue: {
    width: 8,
    height: 8,
    backgroundColor: '#60A5FA',
  },
  dotPurple: {
    width: 6,
    height: 6,
    backgroundColor: '#A78BFA',
  },
  dotLightBlue: {
    width: 5,
    height: 5,
    backgroundColor: '#93C5FD',
  },
  brandName: {
    color: '#FFFFFF',
    fontSize: 40,
    fontWeight: 'bold',
    marginTop: 40,
    letterSpacing: -1,
  },
  brandSub: {
    color: '#60A5FA',
    fontSize: 18,
    fontWeight: '600',
    letterSpacing: 5,
    marginTop: 8,
  },
  tagline: {
    color: '#9CA3AF',
    fontSize: 16,
    textAlign: 'center',
    marginTop: 16,
    lineHeight: 24,
    paddingHorizontal: 16,
  },
  featuresSection: {
    marginTop: 48,
  },
  featureCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  featureIcon: {
    width: 44,
    height: 44,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 16,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  featureText: {
    flex: 1,
  },
  featureTitle: {
    color: '#E5E7EB',
    fontSize: 16,
    fontWeight: '500',
  },
  featureSubtitle: {
    color: '#6B7280',
    fontSize: 14,
    marginTop: 2,
  },
  ctaSection: {
    marginTop: 48,
  },
  primaryButton: {
    borderRadius: 16,
    paddingVertical: 16,
    alignItems: 'center',
    backgroundColor: '#3B82F6',
    shadowColor: '#3B82F6',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 12,
    elevation: 6,
  },
  buttonContent: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  primaryButtonText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '600',
  },
  secondaryButton: {
    borderRadius: 16,
    paddingVertical: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
    marginTop: 16,
  },
  secondaryButtonText: {
    color: '#D1D5DB',
    fontSize: 18,
    fontWeight: '600',
  },
});
