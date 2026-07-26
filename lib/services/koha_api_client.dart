import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_constants.dart';
import 'secure_storage_service.dart';

/// Thrown when a Koha API call gets a 401/403 — the stored token is
/// missing, expired, or was rejected. Callers should treat this as "the
/// session is no longer valid" and trigger a full logout (see
/// AuthScope.of(context).onLogout in auth_scope.dart, which clears both
/// the Koha token and the Firebase session together), not just retry
/// the same call with the same dead token.
class KohaSessionExpiredException implements Exception {
  const KohaSessionExpiredException();
  @override
  String toString() => 'Koha session expired or was rejected.';
}

/// Updated Authentication Workflow, Step 16: "Koha Access Token gets
/// attached to all API calls." This is that attachment mechanism — a
/// thin wrapper around http.Client that reads the token saved by
/// KohaAuthService.login() (via SecureStorageService) and adds it as a
/// Bearer Authorization header to every request automatically, so
/// individual feature code never has to remember to do it by hand.
///
/// SCOPE NOTE: as of this phase, this app has no catalog / checkouts /
/// holds / renewals / fines screens or services yet — grepping lib/ for
/// any Koha HTTP call turns up nothing beyond koha_auth_service.dart's
/// own login request. Building those features out is a separate, much
/// larger effort outside the authentication workflow this class exists
/// to support. What's here is the INFRASTRUCTURE Step 16 specifies,
/// ready for whichever of those features gets built first, e.g.:
///
///   final client = KohaApiClient();
///   final response = await client.get('/api/v1/checkouts');
///   if (response.statusCode == 200) { ... }
///
/// A future feature should catch [KohaSessionExpiredException] and call
/// `AuthScope.of(context).onLogout()` rather than showing a raw error —
/// that's the one existing hook that already clears both sessions
/// together (see auth_gate.dart's _handleLogout).
class KohaApiClient {
  final http.Client _client;
  final SecureStorageService _secureStorage;

  KohaApiClient({http.Client? client, SecureStorageService? secureStorage})
      : _client = client ?? http.Client(),
        _secureStorage = secureStorage ?? SecureStorageService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _secureStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const KohaSessionExpiredException();
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Uri _resolve(String path) => Uri.parse('${ApiConstants.kohaBaseUrl}$path');

  Future<http.Response> get(String path) async {
    final response = await _client
        .get(_resolve(path), headers: await _authHeaders())
        .timeout(ApiConstants.requestTimeout);
    _throwIfSessionExpired(response);
    return response;
  }

  Future<http.Response> post(String path, {Object? body}) async {
    final response = await _client
        .post(
          _resolve(path),
          headers: await _authHeaders(),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(ApiConstants.requestTimeout);
    _throwIfSessionExpired(response);
    return response;
  }

  Future<http.Response> put(String path, {Object? body}) async {
    final response = await _client
        .put(
          _resolve(path),
          headers: await _authHeaders(),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(ApiConstants.requestTimeout);
    _throwIfSessionExpired(response);
    return response;
  }

  Future<http.Response> delete(String path) async {
    final response = await _client
        .delete(_resolve(path), headers: await _authHeaders())
        .timeout(ApiConstants.requestTimeout);
    _throwIfSessionExpired(response);
    return response;
  }

  void _throwIfSessionExpired(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const KohaSessionExpiredException();
    }
  }
}