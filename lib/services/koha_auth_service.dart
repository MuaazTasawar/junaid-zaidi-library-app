import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import '../config/api_constants.dart';
import 'secure_storage_service.dart';

/// Thrown when Koha rejects credentials or the request fails. Callers
/// show [message] directly — it's already meant to be user-facing.
class KohaAuthException implements Exception {
  final String message;
  const KohaAuthException(this.message);

  @override
  String toString() => message;
}

/// Half of the real login for this app (Updated Authentication
/// Workflow, Phase 3) — the other half is FirebaseAuthService. See
/// EmailLoginScreen, which calls both with the same email + password
/// and requires both to succeed. This class only ever handles the Koha
/// side of that pair.
class KohaAuthService {
  final http.Client _client;
  final SecureStorageService _secureStorage;

  KohaAuthService({http.Client? client, SecureStorageService? secureStorage})
      : _client = client ?? http.Client(),
        _secureStorage = secureStorage ?? SecureStorageService();

  // DEV-ONLY hardcoded account so the app is reachable without a real
  // Koha server or the mock server running. Gated behind kDebugMode —
  // this branch is compiled out of release builds entirely (Dart's
  // compiler strips unreachable `if (kDebugMode)` branches in release
  // mode), so it can never work in anything you actually ship, not just
  // "shouldn't" work. Still search this file for "DEV-ONLY" before
  // shipping, to confirm.
  static const _devUsername = 'testuser';
  static const _devPassword = 'test1234';
  static const _devPatronId = '0000';

  /// Logs a student in against Koha, stores the resulting token via
  /// [SecureStorageService], and returns the patron ID on success.
  /// Throws [KohaAuthException] with a user-facing message on failure.
  Future<String> login({required String username, required String password}) async {
    if (kDebugMode && username == _devUsername && password == _devPassword) {
      await _secureStorage.saveSession(token: 'dev-hardcoded-token', patronId: _devPatronId);
      return _devPatronId;
    }

    final uri = Uri.parse(ApiConstants.kohaAuthEndpoint);

    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'userid': username, 'password': password},
          )
          .timeout(ApiConstants.requestTimeout);
    } catch (_) {
      throw const KohaAuthException(
        'Could not reach the library server. Check your connection and try again.',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const KohaAuthException('Incorrect username or password.');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw KohaAuthException(
        'Login failed (server returned ${response.statusCode}). Please try again later.',
      );
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const KohaAuthException('Unexpected response from the library server.');
    }

    // Koha's /api/v1/auth/password response shape can vary slightly by
    // version/config — adjust these keys once you see a real response body.
    final token = data['access_token'] as String? ?? data['token'] as String?;
    final patronId = (data['patron_id'] ?? data['borrowernumber'])?.toString();

    if (token == null || patronId == null) {
      throw const KohaAuthException('Unexpected response from the library server.');
    }

    await _secureStorage.saveSession(token: token, patronId: patronId);
    return patronId;
  }

  Future<void> logout() => _secureStorage.clearSession();

  Future<bool> isLoggedIn() => _secureStorage.hasSession();
}