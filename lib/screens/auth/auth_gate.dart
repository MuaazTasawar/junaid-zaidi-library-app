import 'package:flutter/material.dart';

import '../../navigation/routes.dart';
import '../../services/koha_auth_service.dart';
import '../../theme/theme.dart';
import '../../widgets/ui.dart';
import '../root_shell.dart';
import 'welcome_screen.dart';

/// Decides between the auth flow and the app itself on boot, based on
/// whether a Koha session already exists in secure storage (SDS §9.9 —
/// Koha owns the real session, Firebase never does). Owns its own nested
/// Navigator for the signed-out flow, the same pattern root_shell.dart
/// already uses for the "More" tab stack.
///
/// The route switch below only knows about `welcome` as of Phase 2.
/// login/signup routes are added here in Phases 3 and 5 — until then,
/// pushing them lands on `_ComingSoonScreen`, which is a real, finished
/// screen (not a TODO), just an intentional placeholder for routes this
/// phase hasn't built yet.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _kohaAuth = KohaAuthService();
  late final Future<bool> _sessionCheck;

  @override
  void initState() {
    super.initState();
    _sessionCheck = _kohaAuth.isLoggedIn();
  }

  Route<dynamic> _onGenerateAuthRoute(RouteSettings settings) {
    late final Widget page;
    switch (settings.name) {
      case AuthRoutes.welcome:
        page = const WelcomeScreen();
      default:
        page = const _ComingSoonScreen();
    }
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sessionCheck,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AuthLoadingScreen();
        }

        final hasSession = snapshot.data ?? false;
        if (hasSession) {
          return const RootShell();
        }

        return Navigator(
          initialRoute: AuthRoutes.welcome,
          onGenerateRoute: _onGenerateAuthRoute,
        );
      },
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