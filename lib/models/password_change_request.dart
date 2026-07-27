import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors a document in Firestore's `password_change_requests`
/// collection (Updated Authentication Workflow, Phase 7). Field names
/// here must stay in sync with firestore.rules — the rules check
/// `request.resource.data.uid`, `.status`, and `.newEncryptedPassword`
/// by name.
///
/// This is intentionally a much thinner model than StudentRequest: the
/// student is already an approved user with a profile in `users/{uid}`
/// by the time they can submit one of these, so there's no need to
/// duplicate fullName/department/etc — just enough to identify who's
/// asking and carry the encrypted new password.
class PasswordChangeRequestStatus {
  PasswordChangeRequestStatus._();
  static const String pending = 'Pending';
  static const String approved = 'Approved';
  static const String rejected = 'Rejected';
}

class PasswordChangeRequest {
  final String? id;
  final String uid;
  final String email;
  final String newEncryptedPassword;
  final String status;
  final DateTime? createdAt;

  const PasswordChangeRequest({
    this.id,
    required this.uid,
    required this.email,
    required this.newEncryptedPassword,
    this.status = PasswordChangeRequestStatus.pending,
    this.createdAt,
  });

  factory PasswordChangeRequest.fromMap(String id, Map<String, dynamic> map) {
    final ts = map['createdAt'];
    return PasswordChangeRequest(
      id: id,
      uid: map['uid'] as String? ?? '',
      email: map['email'] as String? ?? '',
      // Absent once syncPasswordChange (functions/index.js) has
      // processed an Approved request and deleted it.
      newEncryptedPassword: map['newEncryptedPassword'] as String? ?? '',
      status: map['status'] as String? ?? PasswordChangeRequestStatus.pending,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}