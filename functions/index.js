const crypto = require('crypto');
const admin = require('firebase-admin');
const fetch = require('node-fetch');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');

admin.initializeApp();

// NOTE on secrets: this reads Koha credentials and the RSA private key
// from process.env, populated from functions/.env at deploy time
// (2nd-gen Cloud Functions bundle .env automatically). That's fine for
// a student build, but .env values aren't encrypted at rest the way
// Secret Manager values are — if this ever handles real student data
// in production, migrate RSA_PRIVATE_KEY / KOHA_OAUTH_CLIENT_SECRET to
// `firebase functions:secrets:set` + `defineSecret()` instead.

/**
 * Decrypts a password that the Flutter app encrypted with
 * CryptoService.encryptPassword (RSA-OAEP, SHA-256) — see
 * lib/services/crypto_service.dart and lib/config/crypto_constants.dart
 * for the client-side half of this pair. Padding and hash MUST match
 * exactly or this throws.
 */
function decryptPassword(encryptedBase64) {
  const privateKeyPem = (process.env.RSA_PRIVATE_KEY || '').replace(/\\n/g, '\n');
  if (!privateKeyPem.includes('BEGIN PRIVATE KEY')) {
    throw new Error('RSA_PRIVATE_KEY is missing or malformed in functions/.env');
  }
  const decrypted = crypto.privateDecrypt(
    {
      key: privateKeyPem,
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: 'sha256',
    },
    Buffer.from(encryptedBase64, 'base64'),
  );
  return decrypted.toString('utf8');
}

/**
 * Idempotent: if a Firebase user already exists for this email (e.g.
 * this function is retrying after a partial failure), reuse it instead
 * of throwing on auth/email-already-exists.
 */
async function ensureFirebaseUser(email, password, displayName) {
  try {
    return await admin.auth().getUserByEmail(email);
  } catch (err) {
    if (err.code !== 'auth/user-not-found') throw err;
  }
  return admin.auth().createUser({
    email,
    password,
    displayName,
    emailVerified: false,
  });
}

/**
 * Koha's staff-side OAuth2 client-credentials grant — a DIFFERENT
 * credential from the student login endpoint the app calls directly
 * (api_constants.dart's kohaAuthEndpoint). Generated in Koha's staff
 * interface with borrowers add/edit permission — see
 * functions/.env.example for where the values come from.
 */
async function getKohaAccessToken() {
  const res = await fetch(`${process.env.KOHA_STAFF_BASE_URL}/api/v1/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: process.env.KOHA_OAUTH_CLIENT_ID,
      client_secret: process.env.KOHA_OAUTH_CLIENT_SECRET,
    }),
  });
  if (!res.ok) {
    throw new Error(`Koha OAuth token request failed: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  return data.access_token;
}

/** Idempotency check — see createOrFindKohaPatron. */
async function findKohaPatronByEmail(accessToken, email) {
  const url = `${process.env.KOHA_STAFF_BASE_URL}/api/v1/patrons?email=${encodeURIComponent(email)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (res.status === 404) return null;
  if (!res.ok) {
    throw new Error(`Koha patron lookup failed: ${res.status} ${await res.text()}`);
  }
  const patrons = await res.json();
  return Array.isArray(patrons) && patrons.length > 0 ? patrons[0] : null;
}

async function createKohaPatron(accessToken, details) {
  const { fullName, email, registrationNumber, phone, password } = details;
  const parts = fullName.trim().split(/\s+/);
  const firstName = parts[0] || fullName.trim();
  const surname = parts.length > 1 ? parts.slice(1).join(' ') : firstName;

  const res = await fetch(`${process.env.KOHA_STAFF_BASE_URL}/api/v1/patrons`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      category_id: process.env.KOHA_PATRON_CATEGORY_CODE,
      library_id: process.env.KOHA_LIBRARY_BRANCHCODE,
      firstname: firstName,
      surname,
      email,
      userid: email,
      password,
      cardnumber: registrationNumber,
      phone: phone || undefined,
      // Koha has no first-class "department" or "cnic" field out of the
      // box. If your Koha instance has Patron Attribute Types defined
      // for these (Administration -> Patron attribute types), send them
      // as extended_attributes here, e.g.:
      // extended_attributes: [
      //   { type: 'DEPT', value: details.department },
      //   { type: 'CNIC', value: details.cnic },
      // ],
      // Left commented rather than guessed, since the attribute type
      // codes are specific to your Koha instance's configuration.
    }),
  });
  if (!res.ok) {
    throw new Error(`Koha patron creation failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

/** Reuses an existing patron by email if one exists (retry-safety), else creates one. */
async function createOrFindKohaPatron(accessToken, details) {
  const existing = await findKohaPatronByEmail(accessToken, details.email);
  if (existing) return existing;
  return createKohaPatron(accessToken, details);
}

/**
 * Updated Authentication Workflow, Phase 3 (Steps 8-11): fires when an
 * admin flips a student_requests document to Approved. Creates the real
 * Firebase account AND the Koha patron, links them via
 * users/{firebaseUid}.kohaBorrowerNumber, then deletes the now-unneeded
 * encryptedPassword field.
 *
 * This is the ONLY place in the entire system that ever decrypts a
 * student's password — see crypto_constants.dart for why that's a
 * deliberate design choice, not an oversight.
 */
exports.onStudentRequestApproved = onDocumentUpdated(
  'student_requests/{requestId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const requestId = event.params.requestId;
    const docRef = event.data.after.ref;

    const justApproved = before.status !== 'Approved' && after.status === 'Approved';
    if (!justApproved) return;

    // Already processed (e.g. this trigger firing twice for the same
    // write, which Cloud Functions does not guarantee against) —
    // encryptedPassword is deleted at the end of a successful run, so
    // its absence means there's nothing left to do.
    if (!after.encryptedPassword) {
      logger.info(`student_requests/${requestId} already processed — skipping.`);
      return;
    }

    const email = after.email;

    try {
      const password = decryptPassword(after.encryptedPassword);

      const firebaseUser = await ensureFirebaseUser(email, password, after.fullName);

      const accessToken = await getKohaAccessToken();
      const kohaPatron = await createOrFindKohaPatron(accessToken, {
        fullName: after.fullName,
        email,
        registrationNumber: after.registrationNumber,
        department: after.department,
        phone: after.phone,
        cnic: after.cnic,
        password,
      });
      const kohaBorrowerNumber = kohaPatron.patron_id ?? kohaPatron.borrowernumber ?? null;

      // Links Firebase UID <-> Koha borrower number (Step 10). Written
      // to the existing `users` collection so Phase 4's session/API
      // code has one place to look up either ID from the other.
      await admin.firestore().collection('users').doc(firebaseUser.uid).set(
        {
          fullName: after.fullName,
          registrationNumber: after.registrationNumber,
          email,
          department: after.department,
          phone: after.phone,
          cnic: after.cnic,
          kohaBorrowerNumber,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      // Step 11: the temporary encrypted password has done its job —
      // remove it. The student_requests document itself stays (status
      // Approved) since FirestoreService.getLatestRequestForEmail still
      // reads it during login.
      await docRef.update({
        encryptedPassword: admin.firestore.FieldValue.delete(),
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processingError: admin.firestore.FieldValue.delete(),
      });

      logger.info(
        `Approved ${email}: firebaseUid=${firebaseUser.uid}, kohaBorrowerNumber=${kohaBorrowerNumber}`,
      );
    } catch (err) {
      logger.error(`Failed to process approval for ${email} (student_requests/${requestId}):`, err);

      // Deliberately do NOT delete encryptedPassword on failure — that
      // would strand the student with an Approved status but no way to
      // log in anywhere, and no way to retry short of rejecting and
      // re-approving them from scratch. Surface the error on the
      // document instead so the admin dashboard (Phase 5) can show it.
      await docRef
        .update({
          processingError: err.message || String(err),
          processingErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch(() => {});

      throw err;
    }
  },
);

/**
 * Updated Authentication Workflow, Phase 7: fires when an admin flips a
 * password_change_requests document to Approved. Updates BOTH the
 * Firebase password and the Koha patron's password to the same new
 * value, so they never drift apart — the whole reason this workflow
 * routes password changes through an admin instead of letting students
 * self-serve one side (e.g. Firebase's own reset-email flow) and leave
 * the other stale.
 */
exports.onPasswordChangeApproved = onDocumentUpdated(
  'password_change_requests/{requestId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const requestId = event.params.requestId;
    const docRef = event.data.after.ref;

    const justApproved = before.status !== 'Approved' && after.status === 'Approved';
    if (!justApproved) return;

    if (!after.newEncryptedPassword) {
      logger.info(`password_change_requests/${requestId} already processed — skipping.`);
      return;
    }

    const { uid, email } = after;

    try {
      const newPassword = decryptPassword(after.newEncryptedPassword);

      // Firebase half.
      await admin.auth().updateUser(uid, { password: newPassword });

      // Koha half — needs the borrower number onStudentRequestApproved
      // linked onto users/{uid} back at registration time.
      const userDoc = await admin.firestore().collection('users').doc(uid).get();
      const kohaBorrowerNumber = userDoc.exists ? userDoc.data().kohaBorrowerNumber : null;
      if (!kohaBorrowerNumber) {
        throw new Error(
          `No kohaBorrowerNumber on users/${uid} — cannot sync the Koha password. ` +
            'This student may predate the automated linking (Phase 3), or that step failed silently.',
        );
      }

      const accessToken = await getKohaAccessToken();
      // NOTE: verify this exact path against your Koha version's API
      // docs before relying on it — Koha's REST API has grown a
      // dedicated patron-password endpoint on newer releases, but on
      // older ones a plain PATCH/PUT to /api/v1/patrons/{id} with a
      // password field may be what's actually needed instead.
      const res = await fetch(
        `${process.env.KOHA_STAFF_BASE_URL}/api/v1/patrons/${kohaBorrowerNumber}/password`,
        {
          method: 'PUT',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ password: newPassword }),
        },
      );
      if (!res.ok) {
        throw new Error(`Koha password update failed: ${res.status} ${await res.text()}`);
      }

      await docRef.update({
        newEncryptedPassword: admin.firestore.FieldValue.delete(),
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processingError: admin.firestore.FieldValue.delete(),
      });

      logger.info(`Synced password change for uid=${uid} (${email}).`);
    } catch (err) {
      logger.error(`Failed to sync password change for uid=${uid} (${email}):`, err);

      // Same reasoning as onStudentRequestApproved: don't delete
      // newEncryptedPassword on failure, so this can be retried, and
      // surface the error for the admin dashboard.
      await docRef
        .update({
          processingError: err.message || String(err),
          processingErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch(() => {});

      throw err;
    }
  },
);