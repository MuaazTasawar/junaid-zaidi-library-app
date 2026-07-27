import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../services/crypto_service.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/theme.dart';
import '../../widgets/ui.dart';

final _passwordHasLetter = RegExp(r'[A-Za-z]');
final _passwordHasDigit = RegExp(r'\d');

/// Updated Authentication Workflow, Phase 7 (Steps: student requests a
/// password change -> administrator reviews -> administrator approves
/// -> Firebase AND Koha passwords both get updated, staying in sync).
///
/// This screen only ever WRITES a request — same encrypt-then-submit
/// pattern as registration (see signup_form_screen.dart / CryptoService)
/// so the new password is never stored in plaintext even transiently.
/// Nothing changes until an admin approves it and
/// functions/index.js's onPasswordChangeApproved trigger runs.
class RequestPasswordChangeScreen extends StatefulWidget {
  const RequestPasswordChangeScreen({super.key});

  @override
  State<RequestPasswordChangeScreen> createState() => _RequestPasswordChangeScreenState();
}

class _RequestPasswordChangeScreenState extends State<RequestPasswordChangeScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _cryptoService = CryptoService();
  final _firebaseAuth = FirebaseAuthService();
  final _firestoreService = FirestoreService();

  String? _newPasswordError;
  String? _confirmPasswordError;
  String? _formError;
  bool _isSubmitting = false;
  bool _isSubmitted = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _newPasswordError = null;
      _confirmPasswordError = null;
      _formError = null;
    });

    var isValid = true;
    final password = _newPasswordController.text;
    // Same policy as registration — see signup_form_screen.dart's note
    // on why this is a documented assumption, not a literal quote from
    // the workflow doc.
    if (password.length < 8 ||
        !_passwordHasLetter.hasMatch(password) ||
        !_passwordHasDigit.hasMatch(password)) {
      setState(() =>
          _newPasswordError = 'At least 8 characters, with a mix of letters and numbers.');
      isValid = false;
    }
    if (_confirmPasswordController.text != password) {
      setState(() => _confirmPasswordError = 'Passwords do not match.');
      isValid = false;
    }
    return isValid;
  }

  Future<void> _handleSubmit() async {
    if (!_validate()) return;

    final user = _firebaseAuth.currentUser;
    if (user == null || user.email == null) {
      setState(() =>
          _formError = 'Your session looks invalid — please log out and log back in.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final encrypted = _cryptoService.encryptPassword(_newPasswordController.text);
      await _firestoreService.submitPasswordChangeRequest(
        uid: user.uid,
        email: user.email!,
        newEncryptedPassword: encrypted,
      );

      if (!mounted) return;
      setState(() => _isSubmitted = true);
    } catch (_) {
      setState(() =>
          _formError = 'Could not submit your request. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = useTheme(context);

    if (_isSubmitted) {
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
                color: colors.intents.success.light.bg,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child:
                  Icon(LucideIcons.circle_check, size: 36, color: colors.intents.success.light.fg),
            ),
            const SizedBox(height: AppSpacing.lg),
            Heading(text: 'Request submitted', level: 3, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            AppText(
              'A librarian will review your request. Your current password keeps working '
              'until it\'s approved — you don\'t need to log in again yet.',
              variant: 'bodyBase',
              tone: 'secondary',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ScreenContainer(
        scroll: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            AppText(
              'Choose a new password. It stays the same as your current one until a '
              'librarian approves this request, and updates both your login and your '
              'library account together.',
              variant: 'bodyBase',
              tone: 'secondary',
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: 'New password',
              controller: _newPasswordController,
              placeholder: 'At least 8 characters, letters + numbers',
              obscureText: true,
              prefixIcon: LucideIcons.lock,
              errorText: _newPasswordError,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Confirm new password',
              controller: _confirmPasswordController,
              placeholder: 'Re-enter your new password',
              obscureText: true,
              prefixIcon: LucideIcons.lock,
              errorText: _confirmPasswordError,
            ),
            if (_formError != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppText(_formError!, variant: 'bodySmall', tone: 'error'),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Submit request',
              onPressed: _isSubmitting ? null : _handleSubmit,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }
}