/// Route names for the nested Navigator that lives inside the "More"
/// bottom tab (mirrors the original app's `app/(tabs)/more/*` expo-router
/// stack).
class MoreRoutes {
  const MoreRoutes._();

  static const String root = '/more';
  static const String profile = '/more/profile';
  static const String guides = '/more/guides';
  static const String map = '/more/map';
  static const String about = '/more/about';
  static const String aboutFacts = '/more/about/facts';
  static const String aboutRules = '/more/about/rules';
  static const String aboutStaff = '/more/about/staff';
  static const String aboutFloorPlan = '/more/about/floor-plan';
}

/// Route names for the nested Navigator that AuthGate owns. Screens push
/// these by name rather than by direct widget reference, so each screen
/// file stays independently compilable regardless of build order.
class AuthRoutes {
  const AuthRoutes._();

  static const String welcome = '/auth/welcome';
  static const String login = '/auth/login';
  static const String emailLogin = '/auth/login/email';
  static const String signupEmail = '/auth/signup/email';
  static const String verifyEmail = '/auth/signup/verify-email';
  static const String signupForm = '/auth/signup/form';
}