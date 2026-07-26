/// Centralized API configuration (SDS §7.4). Every service reads from
/// here — never hardcode a URL anywhere else in the app.
class ApiConstants {
  const ApiConstants._();

  // TODO(Muaaz): replace with your actual Koha base URL, e.g.
  // "https://library.comsats.edu.pk" — no trailing slash.
  static const String kohaBaseUrl = 'https://REPLACE_WITH_YOUR_KOHA_URL';

  static const String kohaAuthEndpoint = '$kohaBaseUrl/api/v1/auth/password';

  static const String firestoreStudentRequestsCollection = 'student_requests';

  // ---- Added Phase 7: Microsoft OAuth ----

  /// COMSATS' Azure AD tenant ID. Pulled directly from a real OAuth
  /// response payload during planning — CONFIRM this is genuinely
  /// correct before shipping, this wasn't stated outright as "this is
  /// our tenant," it was inferred from a sample JSON.
  static const String azureTenantId = '75df096c-8b72-48e4-9b91-cbf79d87ee3a';

  /// Client-side domain check backing FirebaseAuthService.signInWithMicrosoft.
  /// The server-side equivalent lives in firestore.rules on the `users`
  /// collection — don't rely on this constant alone for security.
  static const String studentEmailDomain = '@isbstudent.comsats.edu.pk';

  static const String firestoreUsersCollection = 'users';

  // ---- Added: Updated Authentication Workflow (encrypted-pending +
  // automated Koha patron creation + dual login + admin-mediated
  // password change) ----

  /// Written by the student (Phase 5 UI) when requesting a password
  /// change, and read/updated by the admin dashboard + the
  /// `syncPasswordChange` Cloud Function. Note: the actual Koha
  /// patron-creation and password-sync endpoints are called from
  /// `functions/index.js` (server-side only, using privileged Koha
  /// staff API credentials) — they are deliberately NOT declared here,
  /// since this file's constants are readable inside the compiled app.
  static const String firestorePasswordChangeRequestsCollection =
      'password_change_requests';

  static const Duration requestTimeout = Duration(seconds: 15);
}