import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../models/student_request.dart';
import '../../navigation/routes.dart';
import '../../services/crypto_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/theme.dart';
import '../../widgets/ui.dart';

final _cnicPattern = RegExp(r'^\d{5}-\d{7}-\d$');
final _emailPattern = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
// Password policy (Updated Authentication Workflow, Phase 1 / Step 1:
// "Password meets the required policy"): at least 8 characters, with at
// least one letter and one digit. The doc names the requirement but not
// the exact rule, so this is a documented assumption, not a literal
// quote from it — tighten it here if COMSATS gives you a stricter spec.
final _passwordHasLetter = RegExp(r'[A-Za-z]');
final _passwordHasDigit = RegExp(r'\d');

/// The full registration screen (Updated Authentication Workflow, Phase
/// 1). Unlike the old three-screen flow (email -> verify -> form), there
/// is no separate email-verification step and no temporary Firebase
/// account here — the doc's Step 1 only validates field FORMAT (a real
/// COMSATS domain, a matching password/confirm pair), not email
/// ownership. Submitting writes a single Pending student_requests
/// document with an RSA-encrypted password (Step 2) and nothing else —
/// no Firebase account and no Koha patron exist until a librarian
/// approves it (see functions/index.js).
class SignupFormScreen extends StatefulWidget {
  const SignupFormScreen({super.key});

  @override
  State<SignupFormScreen> createState() => _SignupFormScreenState();
}

class _SignupFormScreenState extends State<SignupFormScreen> {
  final _fullNameController = TextEditingController();
  final _regNumberController = TextEditingController();
  final _departmentController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cnicController = TextEditingController();

  final _cryptoService = CryptoService();
  final _firestoreService = FirestoreService();

  String? _fullNameError;
  String? _regNumberError;
  String? _departmentError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _phoneError;
  String? _cnicError;
  String? _formError;

  bool _isSubmitting = false;
  bool _isSubmitted = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _regNumberController.dispose();
    _departmentController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _cnicController.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _fullNameError = null;
      _regNumberError = null;
      _departmentError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
      _phoneError = null;
      _cnicError = null;
      _formError = null;
    });

    var isValid = true;

    if (_fullNameController.text.trim().isEmpty) {
      setState(() => _fullNameError = 'Enter your full name.');
      isValid = false;
    }
    if (_regNumberController.text.trim().isEmpty) {
      setState(() => _regNumberError = 'Enter your registration number.');
      isValid = false;
    }
    if (_departmentController.text.trim().isEmpty) {
      setState(() => _departmentError = 'Enter your department.');
      isValid = false;
    }

    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !_emailPattern.hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email address.');
      isValid = false;
    } else if (!email.endsWith('@isbstudent.comsats.edu.pk')) {
      setState(() =>
          _emailError = 'Use your COMSATS Outlook email (must end with @isbstudent.comsats.edu.pk).');
      isValid = false;
    }

    final password = _passwordController.text;
    if (password.length < 8 ||
        !_passwordHasLetter.hasMatch(password) ||
        !_passwordHasDigit.hasMatch(password)) {
      setState(() =>
          _passwordError = 'At least 8 characters, with a mix of letters and numbers.');
      isValid = false;
    }
    if (_confirmPasswordController.text != password) {
      setState(() => _confirmPasswordError = 'Passwords do not match.');
      isValid = false;
    }

    // Phone is optional per the workflow doc — only validate its shape
    // if the student actually entered something.
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty && phone.length < 7) {
      setState(() => _phoneError = 'Enter a valid phone number.');
      isValid = false;
    }

    if (!_cnicPattern.hasMatch(_cnicController.text.trim())) {
      setState(() => _cnicError = 'Enter your CNIC as xxxxx-xxxxxxx-x.');
      isValid = false;
    }

    return isValid;
  }

  Future<void> _handleSubmit() async {
    if (!_validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final encryptedPassword = _cryptoService.encryptPassword(_passwordController.text);

      final request = StudentRequest(
        fullName: _fullNameController.text.trim(),
        registrationNumber: _regNumberController.text.trim(),
        department: _departmentController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        phone: _phoneController.text.trim(),
        cnic: _cnicController.text.trim(),
        encryptedPassword: encryptedPassword,
      );
      await _firestoreService.submitStudentRequest(request);

      if (!mounted) return;
      setState(() => _isSubmitted = true);
    } catch (_) {
      setState(() =>
          _formError = 'Could not submit your request. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _handleBackToWelcome() {
    Navigator.of(context).popUntil((route) => route.settings.name == AuthRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    if (_isSubmitted) {
      return _SubmittedView(onDone: _handleBackToWelcome);
    }

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
                  Icon(LucideIcons.arrow_left, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  AppText('Back', variant: 'bodyBase', tone: 'secondary'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Heading(text: 'Create your account', level: 3),
            const SizedBox(height: AppSpacing.xs),
            AppText(
              'Fill this in and a librarian will review your request before you can log in.',
              variant: 'bodyBase',
              tone: 'secondary',
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: 'Full name',
              controller: _fullNameController,
              placeholder: 'e.g. Muaaz Tasawar',
              prefixIcon: LucideIcons.user,
              errorText: _fullNameError,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Registration number',
              controller: _regNumberController,
              placeholder: 'e.g. FA23-BCS-123',
              prefixIcon: LucideIcons.id_card,
              errorText: _regNumberError,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Department',
              controller: _departmentController,
              placeholder: 'e.g. Department of Computer Science',
              prefixIcon: LucideIcons.graduation_cap,
              errorText: _departmentError,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'COMSATS Outlook email',
              controller: _emailController,
              placeholder: 'you@isbstudent.comsats.edu.pk',
              keyboardType: TextInputType.emailAddress,
              prefixIcon: LucideIcons.mail,
              errorText: _emailError,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Password',
              controller: _passwordController,
              placeholder: 'At least 8 characters, letters + numbers',
              obscureText: true,
              prefixIcon: LucideIcons.lock,
              errorText: _passwordError,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Confirm password',
              controller: _confirmPasswordController,
              placeholder: 'Re-enter your password',
              obscureText: true,
              prefixIcon: LucideIcons.lock,
              errorText: _confirmPasswordError,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Phone number (optional)',
              controller: _phoneController,
              placeholder: 'e.g. 03001234567',
              keyboardType: TextInputType.phone,
              prefixIcon: LucideIcons.phone,
              errorText: _phoneError,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'CNIC',
              controller: _cnicController,
              placeholder: 'xxxxx-xxxxxxx-x',
              keyboardType: TextInputType.number,
              prefixIcon: LucideIcons.file_text,
              errorText: _cnicError,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(13),
                _CnicDashFormatter(),
              ],
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

/// Auto-inserts the two CNIC dashes as the student types, so the field
/// always displays as xxxxx-xxxxxxx-x. Combined with
/// FilteringTextInputFormatter.digitsOnly (upstream in the formatter
/// chain), this only ever sees raw digits as input.
class _CnicDashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 4 || i == 11) buffer.write('-');
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Shown in place of the form once the request has been written to
/// Firestore. Kept inside this file rather than a separate screen since
/// it's a state of the same step, not a new route.
class _SubmittedView extends StatelessWidget {
  final VoidCallback onDone;

  const _SubmittedView({required this.onDone});

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
              color: colors.intents.success.light.bg,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(LucideIcons.circle_check, size: 36, color: colors.intents.success.light.fg),
          ),
          const SizedBox(height: AppSpacing.lg),
          Heading(text: 'Request submitted', level: 3, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          AppText(
            'Your registration request has been submitted successfully. Please wait for administrator approval.',
            variant: 'bodyBase',
            tone: 'secondary',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: 'Back to start', onPressed: onDone),
        ],
      ),
    );
  }
}