import 'package:flutter/material.dart';

import '../../navigation/auth_scope.dart';
import '../../navigation/routes.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/koha_auth_service.dart';
import '../../theme/semantic/light.dart';
import '../../theme/theme.dart';
import '../../widgets/ui.dart';
import '../root_shell.dart';
import 'email_login_screen.dart';
import 'login_screen.dart';
import 'signup_email_screen.dart';
import 'signup_form_screen.dart';
import 'verify_email_screen.dart';
import 'welcome_screen.dart';

/// Decides between the auth flow and the app itself. A session is now
/// "real" via any of three independent paths, checked together on boot:
///  1. Koha (secure-storage token) — unchanged since Phase 5.
///  2. Firebase email/password, gated on the matching student_requests
///     document's status being Approved (added this change).
///  3. Firebase Microsoft OAuth (Phase 7) — valid by construction, since
///     it's domain-gated at sign-in.
/// FirebaseAuthService.hasApprovedRequestSession() handles telling (2)
/// and (3) apart and re-validating (2) against Firestore on every boot,
/// so a librarian reversing an approval takes effect next launch.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _kohaAuth = KohaAuthService();
  final _firebaseAuth = FirebaseAuthService();
  final _firestoreService = FirestoreService();

  /// null = still checking on boot, true/false = known session state.
  bool? _hasSession;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final hasKohaSession = await _kohaAuth.isLoggedIn();
    final hasFirebaseSession = await _firebaseAuth.hasApprovedRequestSession(_firestoreService);
    if (mounted) setState(() => _hasSession = hasKohaSession || hasFirebaseSession);
  }

  /// Passed down to LoginScreen and EmailLoginScreen. Flips the gate over
  /// to RootShell the moment either kind of login succeeds.
  void _handleAuthenticated() {
    setState(() => _hasSession = true);
  }

  /// Exposed to RootShell's whole subtree via AuthScope. Clears both
  /// possible session types — harmless to call the one that wasn't
  /// actually active — and flips the gate back to the signed-out flow.
  Future<void> _handleLogout() async {
    await _kohaAuth.logout();
    await _firebaseAuth.signOut();
    if (mounted) setState(() => _hasSession = false);
  }

  Route<dynamic> _onGenerateAuthRoute(RouteSettings settings) {
    late final Widget page;
    switch (settings.name) {
      case AuthRoutes.welcome:
        page = const WelcomeScreen();
      case AuthRoutes.login:
        page = LoginScreen(onLoginSuccess: _handleAuthenticated);
      case AuthRoutes.emailLogin:
        page = EmailLoginScreen(onLoginSuccess: _handleAuthenticated);
      case AuthRoutes.signupEmail:
        page = const SignupEmailScreen();
      case AuthRoutes.verifyEmail:
        final email = settings.arguments as String? ?? '';
        page = VerifyEmailScreen(email: email);
      case AuthRoutes.signupForm:
        page = const SignupFormScreen();
      default:
        page = const _ComingSoonScreen();
    }
    return MaterialPageRoute(
      builder: (_) => Scaffold(backgroundColor: lightColors.background.primary, body: page),
      settings: settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSession == null) {
      return const _AuthLoadingScreen();
    }

    if (_hasSession!) {
      return AuthScope(onLogout: _handleLogout, child: const RootShell());
    }

    return Navigator(
      initialRoute: AuthRoutes.welcome,
      onGenerateRoute: _onGenerateAuthRoute,
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final colors = useTheme(context);
    return ScreenContainer(
      child: Center(
        child: CircularProgressIndicator(color: colors.brand),
      ),
    );
  }
}

class _ComingSoonScreen extends StatelessWidget {
  const _ComingSoonScreen();

  @override
  Widget build(BuildContext context) {
    return ScreenContainer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Heading(text: 'Coming soon', level: 4, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            AppText(
              'This part of sign-up/sign-in is being built in a later phase.',
              variant: 'bodyBase',
              tone: 'secondary',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}