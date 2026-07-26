import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';

import '../config/crypto_constants.dart';

/// Client-side RSA-OAEP encryption for the student's password before it
/// is ever written to Firestore (Updated Authentication Workflow, Phase
/// 1 / Step 2: "The password is encrypted before saving").
///
/// This class can only ENCRYPT. There is deliberately no decrypt()
/// method anywhere in the Flutter app — decryption only happens inside
/// the Cloud Function, using the private key held in its environment.
/// See crypto_constants.dart for the full security rationale.
class CryptoService {
  RSAPublicKey? _cachedPublicKey;

  RSAPublicKey _publicKey() {
    return _cachedPublicKey ??= CryptoUtils.rsaPublicKeyFromPem(
      CryptoConstants.passwordEncryptionPublicKeyPem,
    );
  }

  /// Encrypts [plaintext] with RSA-OAEP (SHA-256), returning a base64
  /// string ready to store directly in a Firestore document field.
  ///
  /// The matching Cloud Function decrypt call MUST use the same padding
  /// scheme (RSA_PKCS1_OAEP_PADDING) and the same hash (SHA-256) — see
  /// functions/index.js's decryptPassword() — or decryption will fail
  /// even with the correct private key.
  ///
  /// Throws [ArgumentError] if [plaintext] is too long for a single
  /// RSA-2048 OAEP-SHA256 block (~190 bytes of UTF-8). Real passwords
  /// never come close to that limit.
  String encryptPassword(String plaintext) {
    final publicKey = _publicKey();
    final maxInputBytes = (publicKey.modulus!.bitLength ~/ 8) - 2 * 32 - 2;

    final input = Uint8List.fromList(utf8.encode(plaintext));
    if (input.length > maxInputBytes) {
      throw ArgumentError(
        'Password is too long to encrypt (max $maxInputBytes bytes, got ${input.length}).',
      );
    }

    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    final output = cipher.process(input);
    return base64Encode(output);
  }
}