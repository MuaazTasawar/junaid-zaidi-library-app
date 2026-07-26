import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/api_constants.dart';
import '../models/app_user.dart';
import '../models/student_request.dart';

class FirestoreService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  FirestoreService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _requestsCollection =>
      _db.collection(ApiConstants.firestoreStudentRequestsCollection);

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _db.collection(ApiConstants.firestoreUsersCollection);

  CollectionReference<Map<String, dynamic>> get _passwordChangeRequestsCollection =>
      _db.collection(ApiConstants.firestorePasswordChangeRequestsCollection);

  /// Writes a new pending registration request (Updated Authentication
  /// Workflow, Phase 1 / Step 2). [request.encryptedPassword] must
  /// already be RSA-OAEP encrypted — see CryptoService — this method
  /// never sees or handles a plaintext password.
  ///
  /// firestore.rules requires request.auth != null for this write, but
  /// the workflow deliberately creates NO real Firebase account for the
  /// student before a librarian approves them. So this signs in
  /// anonymously — a throwaway session, never tied to the student's
  /// email or password — purely to satisfy that rule, then signs back
  /// out immediately once the write succeeds. If the write throws, the
  /// anonymous session is left signed out too, so a retry doesn't pile
  /// up abandoned anonymous accounts.
  Future<void> submitStudentRequest(StudentRequest request) async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    try {
      await _requestsCollection.add(request.toMap());
    } finally {
      await _auth.signOut();
    }
  }

  Stream<List<StudentRequest>> watchRequestsForEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return _requestsCollection
        .where('email', isEqualTo: normalized)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StudentRequest.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<StudentRequest?> getLatestRequestForEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    final snapshot = await _requestsCollection
        .where('email', isEqualTo: normalized)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return StudentRequest.fromMap(doc.id, doc.data());
  }

  Future<void> saveUserProfile(AppUser user) async {
    await _usersCollection.doc(user.uid).set(user.toMap());
  }

  Future<AppUser?> getUserProfile(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.id, doc.data()!);
  }

  Future<bool> hasCompletedOnboarding(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    return doc.exists;
  }

  /// Updated Authentication Workflow, Phase 7: writes a password-change
  /// request for an already-approved student. [newEncryptedPassword]
  /// must already be RSA-OAEP encrypted, same as registration. Unlike
  /// registration, this requires the student's REAL Firebase session
  /// (they must be logged in already), so no anonymous-session dance is
  /// needed here — firestore.rules checks request.auth.uid directly.
  Future<void> submitPasswordChangeRequest({
    required String uid,
    required String email,
    required String newEncryptedPassword,
  }) async {
    await _passwordChangeRequestsCollection.add({
      'uid': uid,
      'email': email.trim().toLowerCase(),
      'newEncryptedPassword': newEncryptedPassword,
      'status': 'Pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}