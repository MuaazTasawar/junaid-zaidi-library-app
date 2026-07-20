import 'package:flutter/material.dart';

import '../../navigation/routes.dart';
import '../../theme/theme.dart';
import '../../widgets/ui.dart';

/// First screen a signed-out student sees: brand mark + the fork between
/// "Log In" (existing patron) and "Create Account" (new registration
/// request). Pushed as the initial route inside AuthGate's nested
/// Navigator.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = useTheme(context);

    return ScreenContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.brand,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: AppText(
              'JZ',
              variant: 'h4',
              style: TextStyle(color: colors.text.onBrand, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Heading(text: 'Junaid Zaidi Library', level: 3, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          AppText(
            'COMSATS University Islamabad',
            variant: 'bodyBase',
            tone: 'secondary',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            label: 'Log In',
            variant: 'primary',
            onPressed: () => Navigator.of(context).pushNamed(AuthRoutes.login),
          ),
          const SizedBox(height: AppSpacing.ms),
          AppButton(
            label: 'Create Account',
            variant: 'secondary',
            onPressed: () => Navigator.of(context).pushNamed(AuthRoutes.signupEmail),
          ),
        ],
      ),
    );
  }
}