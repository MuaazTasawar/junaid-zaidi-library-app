import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../navigation/routes.dart';
import '../../services/koha_auth_service.dart';
import '../../theme/theme.dart';
import '../../widgets/ui.dart';

/// The real login (SDS §9.9) — goes straight to Koha's
/// POST /api/v1/auth/password, never through Firebase. Firebase's only
/// role in this app ends at email verification during sign-up.
class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _kohaAuth = KohaAuthService();

  String? _formError;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() => _formError = null);

    if (username.isEmpty || password.isEmpty) {
      setState(() => _formError = 'Enter your username and password.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _kohaAuth.login(username: username, password: password);
      if (!mounted) return;
      widget.onLoginSuccess();
    } on KohaAuthException catch (e) {
      setState(() => _formError = e.message);
    } catch (_) {
      setState(() => _formError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ScreenContainer(
        scroll: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(Ionicons.arrow_back, size: 20, color: useTheme(context).icon),
                  const SizedBox(width: AppSpacing.xs),
                  AppText('Back', variant: 'bodyBase', tone: 'secondary'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Heading(text: 'Log in', level: 3),
            const SizedBox(height: AppSpacing.xs),
            AppText(
              'Use the library username and password given to you after approval.',
              variant: 'bodyBase',
              tone: 'secondary',
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: 'Username',
              controller: _usernameController,
              placeholder: 'Your library username',
              prefixIcon: Ionicons.person_outline,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Password',
              controller: _passwordController,
              placeholder: 'Your library password',
              obscureText: true,
              prefixIcon: Ionicons.lock_closed_outline,
            ),
            if (_formError != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppText(_formError!, variant: 'bodySmall', tone: 'error'),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Log in',
              onPressed: _isSubmitting ? null : _handleLogin,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: AppSpacing.ms),
            AppButton(
              label: "Don't have an account? Create one",
              variant: 'text',
              onPressed: _isSubmitting
                  ? null
                  : () => Navigator.of(context).pushNamed(AuthRoutes.signupEmail),
            ),
          ],
        ),
      ),
    );
  }
}
