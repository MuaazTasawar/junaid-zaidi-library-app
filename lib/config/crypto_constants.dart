/// RSA-OAEP public key used to encrypt a student's password client-side
/// before it is ever written to Firestore (Updated Authentication
/// Workflow, Phase 1 / Step 2).
///
/// Security model:
/// - This is a PUBLIC key. It is safe for it to live in the compiled app
///   — anyone can encrypt with it, nobody can decrypt with it.
/// - The matching PRIVATE key lives ONLY in the Cloud Function's
///   environment (`functions/.env`, never committed) — see
///   `functions/index.js`. Nothing client-side, including the admin
///   dashboard, can ever decrypt a password. Only the Cloud Function can.
/// - Never replace this with a symmetric (AES) key shared between the
///   app and the backend — a key embedded in the compiled app can be
///   extracted from the APK, which would defeat the encryption entirely.
///
/// TODO(Muaaz): This is a real, working dev/testing keypair generated for
/// this build — NOT a placeholder. It is fine for local testing, but
/// generate a fresh keypair before shipping to production:
///   openssl genrsa -out private_key.pem 2048
///   openssl rsa -in private_key.pem -pubout -out public_key.pem
/// Put the new public key below, and the new private key in
/// functions/.env (RSA_PRIVATE_KEY) — never in this file, never in git.
class CryptoConstants {
  const CryptoConstants._();

  static const String passwordEncryptionPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+AGprvhFpgfeYY2CxSTu
4YGxpylaB7ZQKgd45+d+cXfLTPhr2q5xfKiW6f1c2c0E2PuX7WrQ3p4uGDSf/Nb0
QBWE+RXCytEARP+78r4RLZoIIi+TD+MKD5nn7vPCYvACpj8lv+r4duKRqtIthpra
GWyr5GImrg+VWDtvZ29MLMcy1BhlBn4yxDVueTyaBZeBHyFuNxtqkFzf38nVsZ/C
APaN0ZnivxypCfvReRmxUTj5RRiMY8cZw+ft/XgsNtLUXon0Bn6Doy8VlLPCRHhq
ryYtL1BkLnOHBRmuAMbYmmOGuT2OR0vRzbupTyoIrdeBrR6DUj0aDW2wXUISKea5
mQIDAQAB
-----END PUBLIC KEY-----
''';
}