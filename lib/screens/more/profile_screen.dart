import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../models/app_user.dart';
import '../../models/student_request.dart';
import '../../navigation/auth_scope.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/koha_auth_service.dart';
import '../../services/secure_storage_service.dart';
import '../../theme/theme.dart';
import '../../widgets/ui.dart';

/// Grouped list container - a card-like surface holding several [ListRow]s
/// stacked with dividers.
Widget _groupedList(SemanticColors colors, List<Widget> rows) {
  final shadow = cardShadowDecoration(colors);
  return Container(
    decoration: BoxDecoration(
      color: colors.background.secondary,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: shadow.border,
      boxShadow: shadow.boxShadow,
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: rows),
  );
}

/// Unified view of "whoever is currently signed in," regardless of which
/// of the three session types (Koha / Microsoft / email-approved) got
/// them there. [isLimited] is true for Koha-only accounts, which have no
/// rich profile data available (koha_auth_service.dart only ever talks
/// to the login endpoint, never a patron-details one) — the UI shows an
/// honest "not available" state for those rather than blank/fake fields.
class _ProfileData {
  final String fullName;
  final String registrationNumber;
  final String? department;
  final String? email;
  final String? phone;
  final String? cnic;
  final bool isLimited;

  const _ProfileData({
    required this.fullName,
    required this.registrationNumber,
    this.department,
    this.email,
    this.phone,
    this.cnic,
    this.isLimited = false,
  });
}

/// Profile screen: student hero (avatar/name/reg number) + every detail
/// collected at signup. Loads from whichever backend actually holds the
/// signed-in account's data. Shows a Sign Up/Sign In prompt instead of
/// any of that when the current session is guest (Phase 8).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firebaseAuth = FirebaseAuthService();
  final _firestoreService = FirestoreService();
  final _kohaAuth = KohaAuthService();
  final _secureStorage = SecureStorageService();

  _ProfileData? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final firebaseUser = _firebaseAuth.currentUser;

    if (firebaseUser != null) {
      final isMicrosoft = firebaseUser.providerData.any((p) => p.providerId == 'microsoft.com');

      if (isMicrosoft) {
        final appUser = await _firestoreService.getUserProfile(firebaseUser.uid);
        if (mounted) setState(() => _profile = _fromAppUser(appUser, firebaseUser.email));
        return;
      }

      final email = firebaseUser.email;
      if (email != null) {
        final request = await _firestoreService.getLatestRequestForEmail(email);
        if (mounted) setState(() => _profile = _fromStudentRequest(request, email));
        return;
      }
    }

    final hasKohaSession = await _kohaAuth.isLoggedIn();
    if (hasKohaSession) {
      final patronId = await _secureStorage.readPatronId();
      if (mounted) {
        setState(() => _profile = _ProfileData(
              fullName: 'Library Account',
              registrationNumber: 'Patron ID: ${patronId ?? 'unknown'}',
              isLimited: true,
            ));
      }
      return;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  _ProfileData _fromAppUser(AppUser? user, String? fallbackEmail) {
    if (user == null) {
      return _ProfileData(
        fullName: 'Profile unavailable',
        registrationNumber: '',
        email: fallbackEmail,
        isLimited: true,
      );
    }
    return _ProfileData(
      fullName: user.fullName,
      registrationNumber: user.registrationNumber,
      department: user.department,
      email: user.email,
      phone: user.phone,
      cnic: user.cnic,
    );
  }

  _ProfileData _fromStudentRequest(StudentRequest? request, String fallbackEmail) {
    if (request == null) {
      return _ProfileData(
        fullName: 'Profile unavailable',
        registrationNumber: '',
        email: fallbackEmail,
        isLimited: true,
      );
    }
    return _ProfileData(
      fullName: request.fullName,
      registrationNumber: request.registrationNumber,
      department: request.department,
      email: request.email,
      phone: request.phone,
      cnic: request.cnic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = useTheme(context);
    final isGuest = AuthScope.of(context).isGuest;

    if (isGuest) {
      return ScreenContainer(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.intents.info.light.bg,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(LucideIcons.user, size: 32, color: colors.brand),
              ),
              const SizedBox(height: AppSpacing.lg),
              Heading(level: 4, text: "You're browsing as a guest", textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              AppText(
                'Sign up or log in to see your profile and borrow history.',
                variant: 'bodyBase',
                tone: 'secondary',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Sign Up / Sign In',
                onPressed: () => AuthScope.of(context).onLogout(),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading && _profile == null) {
      return ScreenContainer(
        child: Center(child: CircularProgressIndicator(color: colors.brand)),
      );
    }

    final profile = _profile ??
        const _ProfileData(fullName: 'Profile unavailable', registrationNumber: '', isLimited: true);

    return ScreenContainer(
      scroll: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppAvatar(name: profile.fullName, size: 'large'),
                const SizedBox(height: AppSpacing.sm),
                Heading(level: 4, text: profile.fullName, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.xs),
                AppText(
                  profile.registrationNumber,
                  variant: 'bodyBase',
                  tone: 'secondary',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (profile.isLimited)
            _groupedList(colors, [
              ListRow(
                icon: LucideIcons.info,
                label: 'Full profile not available',
                secondaryLabel: 'Only shown for accounts created via Sign Up',
                showChevron: false,
                showDivider: false,
              ),
            ])
          else
            _groupedList(colors, [
              ListRow(
                icon: LucideIcons.graduation_cap,
                label: 'Department',
                secondaryLabel: profile.department ?? '—',
                showChevron: false,
              ),
              ListRow(
                icon: LucideIcons.mail,
                label: 'Email',
                secondaryLabel: profile.email ?? '—',
                showChevron: false,
              ),
              ListRow(
                icon: LucideIcons.phone,
                label: 'Phone',
                secondaryLabel: profile.phone ?? '—',
                showChevron: false,
              ),
              ListRow(
                icon: LucideIcons.file_text,
                label: 'CNIC',
                secondaryLabel: profile.cnic ?? '—',
                showChevron: false,
                showDivider: false,
              ),
            ]),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Log Out',
            variant: 'secondary',
            onPressed: () => AuthScope.of(context).onLogout(),
          ),
        ],
      ),
    );
  }
}