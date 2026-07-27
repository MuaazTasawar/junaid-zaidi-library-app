# Junaid Zaidi Library App

A Flutter app for the Junaid Zaidi Library at COMSATS University Islamabad. Students can browse library resources and spaces, read guides and rules, find the library on a map, register for an account, and log in. Library staff review and approve registrations through a separate web-based admin dashboard.

This is a Flutter port of an original Expo Router (React Native) app; several comments in the codebase point back at the `.js` file each screen mirrors.

This README is intentionally long — it's meant to be the one document that explains the whole system end to end, including the mistakes made and fixed along the way, so nobody has to reconstruct that history from git blame later.

---

## Table of Contents

1. [App structure](#app-structure)
2. [Design system](#design-system)
3. [Authentication — full architecture](#authentication--full-architecture)
4. [The complete request lifecycle](#the-complete-request-lifecycle)
5. [Firestore data model](#firestore-data-model)
6. [Firestore security rules](#firestore-security-rules)
7. [The admin dashboard — full setup and usage guide](#the-admin-dashboard--full-setup-and-usage-guide)
8. [Known gotchas and lessons learned](#known-gotchas-and-lessons-learned)
9. [Project setup (fresh clone)](#project-setup-fresh-clone)
10. [Repo layout](#repo-layout)
11. [Explicit replace-before-shipping checklist](#explicit-replace-before-shipping-checklist)
12. [Known limitations and open work](#known-limitations-and-open-work)

---

## App structure

Four bottom tabs, each mirroring an `app/(tabs)/*.js` route from the original:

| Tab | Screen | Status |
|---|---|---|
| Home | `home_screen.dart` | Hero banner, search box, resource shortcut grid |
| Library Resources | `library_resources_screen.dart` | Under construction (empty state) |
| Explore Spaces | `explore_spaces_screen.dart` | Under construction (empty state) |
| More | `more/more_screen.dart` | Live profile hero card + menu → Profile, Guides, Map, About |

Navigation is `IndexedStack` + `BottomNavigationBar` in `root_shell.dart`, so switching tabs preserves each tab's state. The **More** tab owns its own nested `Navigator` for its internal stack, with `PopScope` wired so Android's back button pops that inner stack before the outer app.

Three "More" menu items — Contact Us, Event Calendar, Junaid Zaidi Gallery — are intentionally inert and show a "Coming soon" badge. By design, not a bug.

The Map screen renders OpenStreetMap through `services/osm_map_html.dart` — an HTML string fed into `webview_flutter`, not a native map SDK.

## Design system

- `theme/tokens/` — spacing (`AppSpacing`), radius (`AppRadius`), typography (`AppTypography`), color primitives (`colors.dart`, includes `AppPalette` gradient scale)
- `theme/semantic/` — light/dark semantic color maps, accessed via `useTheme(context)`
- `widgets/ui.dart` — shared component barrel (`AppText`, `AppButton`, `AppTextField`, `Heading`, `AppCard`, `ScreenContainer`, `ListRow`, `AppAvatar`, `AppBadge`, etc.)

Brand color `#1D4ED8`. Font is Inter — real `.ttf` files bundled under a custom `Inter` family; `typography.dart` sets `fontFamily: 'Inter'` directly (an earlier version called `GoogleFonts.inter(...)`, which looked for fonts via the `google_fonts` package's own manifest instead of the bundled family — fixed).

Icons are **Lucide** (`flutter_lucide` package), migrated from `ionicons` app-wide. `ionicons` (last published 2023) defines `IoniconsData extends IconData`, which stopped compiling once Flutter marked `IconData` `final` — an unmaintained package hitting a framework breaking change with no fix coming.

---
## Authentication — full architecture

This app went through a real, deliberate architecture change partway through development: from an "account first, approval second" design to an "approval first, no account exists until then" design (the "Updated Authentication Workflow"). This section describes the **current, final state**. See "Known gotchas" below, and `AUTHENTICATION.md`, for more detail on individual pieces.

### Three ways into the app

| Path | How it works | Real session? |
|---|---|---|
| **Email/password, dual-authenticated** | Student registers (one form, no account yet) → a librarian approves via the admin dashboard → a Cloud Function creates matching Firebase + Koha accounts automatically → student logs in with that email/password, authenticated against **both** systems simultaneously | Yes — requires a live Firebase session AND a stored Koha token, checked together on every boot |
| **Microsoft OAuth (Azure AD)** | *Built, not yet wired into any UI.* `FirebaseAuthService.signInWithMicrosoft()`, the `users` Firestore collection, and its security rules all exist and work; there is no button anywhere that calls it yet | Would be, once wired — domain-gated at sign-in, no approval step needed |
| **Guest** | "Continue as Guest" on the Welcome screen | No — browse-only, Profile and More tab's hero card both show a sign-in prompt instead of any data |

**Koha login is not dead code anymore.** An earlier version of this README (and of `AUTHENTICATION.md`) said Koha login had been removed in favor of Firebase-only auth. That was accurate for a period of this project's history, but the currently-implemented workflow reverses it again: Koha login is back, running *alongside* Firebase, not instead of it — both are required together for every login. `login_screen.dart` (an old, Koha-only, username-based screen from an earlier design) was deleted for real, rather than left dormant, because it directly conflicted with the current one-email-one-password-for-both-systems model.

### AuthGate — the actual session decision

`lib/screens/auth/auth_gate.dart` is a four-state machine:

- **loading** — still checking on boot
- **authenticated** — **both** a live Firebase session AND a stored Koha token are present. If only one is found, both are cleared and the student is treated as signed out — a half-authenticated state is never trusted, even across a restart.
- **guest** — no account, but the guest flag is set in secure storage (persists across restarts, same as a real session — a guest isn't re-prompted through Welcome every launch)
- **signedOut** — none of the above; shows the Welcome flow

Unlike the earlier "Approved-gated" design, there's no separate Firestore status re-check on every boot anymore — a Firebase account simply doesn't exist for a student until a Cloud Function creates it on approval, so the account's mere existence already implies approval. The dual-session check described above is what replaced that re-validation step.

### Logging in — both systems, or neither

`lib/screens/auth/email_login_screen.dart` sends the same email + password to Firebase Auth and to Koha's `/api/v1/auth/password` endpoint. Both must succeed. If Koha rejects credentials Firebase just accepted, the app signs back out of Firebase immediately, rather than leaving one system authenticated and the other not.

### Logging out (and exiting guest mode)

`AuthScope` (`navigation/auth_scope.dart`) is an `InheritedWidget` that exposes `onLogout` and `isGuest` to everything inside `RootShell`. Calling `onLogout()` clears the Koha token, signs out of Firebase, and clears the guest flag — all three, unconditionally, since clearing a state that was never set is harmless. This single callback does double duty as "log out" for a real account and "exit guest mode / go sign in" for a guest.

### Profile data — one shared loader, not two copies

`ProfileScreen` and `MoreScreen`'s hero card both need "who is signed in and what do we know about them." Early on, `MoreScreen` used a hardcoded static placeholder (`data/student_profile.dart`) while `ProfileScreen` had its own real loading logic — which is exactly why the More tab kept showing "Student Name / FA00-BCS-000" long after Profile itself was showing real data correctly. Fixed by extracting `services/profile_loader.dart` (`ProfileLoader.load()` → `models/profile_data.dart`'s `ProfileData`) as the single shared source of truth. Both screens call the same loader now; they cannot drift apart again the way they did before.

---

## The complete request lifecycle

```
1. REGISTER                      signup_form_screen.dart
   One screen: name, reg number, department, COMSATS email,
   password + confirm, phone (optional), CNIC. Format-only
   validation -- no email-ownership verification at this stage.
        |
        v
2. ENCRYPT + SUBMIT               crypto_service.dart
   Password is RSA-OAEP encrypted client-side. App signs in
   ANONYMOUSLY (a throwaway session, unrelated to the student's
   real identity) purely to satisfy Firestore's auth requirement,
   writes the Pending request, signs back out immediately.
        |
        v
3. student_requests: Pending      (encryptedPassword attached,
                                    NO Firebase account, NO Koha
                                    patron exist yet)
        |
        v
4. LIBRARIAN REVIEWS              admin-dashboard.html (web)
   A staff member logs into the admin dashboard with a dedicated
   Firebase account, sees the request under Registrations -> Pending,
   and clicks Approve or Reject.
        |
        +--- REJECTED ---------> no account is ever created;
        |                        student's future login attempts
        |                        correctly fail (no account exists)
        v
   APPROVED (status field set to exactly "Approved")
        |
        v
5. AUTOMATED ACCOUNT CREATION     functions/index.js,
                                   onStudentRequestApproved
   Cloud Function decrypts the password, creates a Firebase user,
   creates a matching Koha patron (userid = email), links the two
   via users/{uid}.kohaBorrowerNumber, deletes encryptedPassword.
   On any failure: encryptedPassword is LEFT IN PLACE (so it can be
   retried) and a processingError is written for the dashboard to
   show.
        |
        v
6. LOG IN                         email_login_screen.dart
   Student enters the SAME email/password. Sent to BOTH Firebase
   Auth and Koha's /api/v1/auth/password. Both must succeed.
        |
        v
7. APP UNLOCKED                   AuthGate flips to RootShell, live

--- Later, independently ---

8. REQUEST PASSWORD CHANGE        request_password_change_screen.dart
   Same encrypt-then-submit pattern as registration, into a
   separate password_change_requests collection. Current password
   keeps working until approved.
        |
        v
9. LIBRARIAN REVIEWS               admin-dashboard.html,
                                    Password Changes tab
        |
        v
10. AUTOMATED SYNC                 functions/index.js,
                                    onPasswordChangeApproved
    Decrypts the new password, updates Firebase AND the linked
    Koha patron together, so they can never drift apart.
```

Steps 1-2 and 6 are app code. Steps 4 and 9 happen in a **separate web page** (the admin dashboard), not inside the mobile app — this keeps librarian-level Firestore write access out of the mobile client entirely, while still giving staff a real UI instead of hand-editing documents in the Firebase Console. Steps 5 and 10 are server-side automation that no client (mobile app or dashboard) can trigger directly — they only ever run in response to a status change a librarian made.

---

## Firestore data model

### `student_requests/{requestId}`

| Field | Type | Notes |
|---|---|---|
| `fullName` | string | |
| `registrationNumber` | string | e.g. `FA23-BCS-050` |
| `department` | string | |
| `email` | string | Format-validated against `@isbstudent.comsats.edu.pk`; NOT matched against an auth token, since no real account exists at write time |
| `phone` | string | Optional |
| `cnic` | string | Format `xxxxx-xxxxxxx-x` |
| `encryptedPassword` | string | RSA-OAEP encrypted, base64. Present only while `Pending`; deleted by the Cloud Function once account creation succeeds |
| `status` | string | Exactly one of `Pending`, `Approved`, `Rejected` |
| `createdAt` | timestamp | Server-set via `FieldValue.serverTimestamp()` |
| `processedAt` | timestamp | Set by the Cloud Function on successful processing |
| `processingError` | string | Present only if automated processing failed — surfaced on the admin dashboard |

**The `status` field only recognizes those three exact values, case-sensitive**, and `firestore.rules` now enforces this on every client-side update (`in ['Approved', 'Rejected']`) — a typo like `"Verified"` is rejected by the rules themselves now, not just silently ignored by the app's status-check branches.

### `password_change_requests/{requestId}`

| Field | Type | Notes |
|---|---|---|
| `uid` | string | The requesting student's Firebase UID |
| `email` | string | |
| `newEncryptedPassword` | string | RSA-OAEP encrypted, base64. Deleted once synced. |
| `status` | string | Exactly one of `Pending`, `Approved`, `Rejected` |
| `createdAt` / `processedAt` / `processingError` | timestamp / timestamp / string | Same pattern as `student_requests` |

### `admins/{uid}`

A document existing at all, at a Firebase Auth UID as its document ID, means that account can access the admin dashboard and approve/reject requests. Document content doesn't matter — only existence matters. Nothing can write to this collection from any client; adding an admin is always a manual Firebase Console step.

### `users/{uid}`

Written automatically by the Cloud Function on approval (Admin SDK — bypasses security rules) with `fullName`, `registrationNumber`, `department`, `email`, `phone`, `cnic`, and critically `kohaBorrowerNumber` — the link between the Firebase account and its Koha patron, required for the password-sync Cloud Function to find the right Koha record later. Also still used by the (unwired) Microsoft OAuth path, which writes here client-side instead.

---

## Firestore security rules

Current `firestore.rules` (also in the repo root):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /admins/{adminId} {
      allow read: if request.auth != null && request.auth.uid == adminId;
      allow write: if false;
    }

    match /student_requests/{requestId} {
      allow create: if request.auth != null
                    && request.resource.data.email is string
                    && request.resource.data.email.matches('.*@isbstudent[.]comsats[.]edu[.]pk$')
                    && request.resource.data.status == 'Pending'
                    && request.resource.data.encryptedPassword is string
                    && request.resource.data.encryptedPassword.size() > 0;

      allow read: if request.auth != null
                  && (resource.data.email == request.auth.token.email
                      || exists(/databases/$(database)/documents/admins/$(request.auth.uid)));

      allow update: if request.auth != null
                    && exists(/databases/$(database)/documents/admins/$(request.auth.uid))
                    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status'])
                    && request.resource.data.status in ['Approved', 'Rejected'];

      allow delete: if false;
    }

    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null
                    && request.auth.uid == userId
                    && request.auth.token.email.matches('.*@isbstudent[.]comsats[.]edu[.]pk$');
      allow update: if request.auth != null && request.auth.uid == userId;
      allow delete: if false;
    }

    match /password_change_requests/{requestId} {
      allow create: if request.auth != null
                    && request.resource.data.uid == request.auth.uid
                    && request.resource.data.status == 'Pending'
                    && request.resource.data.newEncryptedPassword is string
                    && request.resource.data.newEncryptedPassword.size() > 0;

      allow read: if request.auth != null
                  && (resource.data.uid == request.auth.uid
                      || exists(/databases/$(database)/documents/admins/$(request.auth.uid)));

      allow update: if request.auth != null
                    && exists(/databases/$(database)/documents/admins/$(request.auth.uid))
                    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status'])
                    && request.resource.data.status in ['Approved', 'Rejected'];

      allow delete: if false;
    }
  }
}
```

Key design points:
- `student_requests` writes come from an **anonymous, throwaway Firebase session** (see the lifecycle diagram above) — since no real account exists yet, the create rule validates the data's **shape and format**, not an auth-token identity match the way the old rule did.
- Admins can read every request, but can update **only the `status` field, and only to `Approved` or `Rejected`** — even an admin account can't silently rewrite a student's name/CNIC, or set some other status value, through the dashboard.
- Nobody can delete a request from the client, ever. Cloud Functions use the Admin SDK, which bypasses these rules entirely for their own cleanup steps (deleting `encryptedPassword`, etc).

Two composite indexes are required for the queries this app actually runs (Firestore doesn't auto-create these — see `firestore.indexes.json`), covering `email`+`createdAt` and `status`+`createdAt` on the request collections. Deploy with:

```powershell
firebase deploy --only firestore:indexes
```

---

## The admin dashboard — full setup and usage guide

`admin-dashboard.html`, in the project root, is a **single self-contained HTML file** — no build step, no npm, no separate project. It uses the Firebase JS SDK loaded from a CDN. It exists so library staff can review and approve/reject registration and password-change requests without needing Flutter, without needing access to the Firebase Console directly, and without any librarian-level access ever being shipped inside the mobile app itself.

### What it looks like

- A login screen (brand-blue "JZ" mark, email/password fields) — this is a **separate Firebase account** from any student account, dedicated to admin access.
- Two top-level sections: **Registrations** and **Password Changes**, each with **Pending / Approved / Rejected / All** tabs.
- Each request shows every field submitted, plus **Approve**/**Reject** buttons on Pending items.
- A red **"Automated processing failed"** banner appears directly on any request whose Cloud Function step failed (e.g. Koha unreachable) — approving a request in Firestore always succeeds instantly, but that doesn't guarantee the account-creation/password-sync step behind it did too; this banner is the only signal that it didn't.
- Updates are live — approving a request removes it from Pending and it appears under Approved immediately, no manual refresh.

### One-time setup

**Step 1 — Create the admin login account.**
Firebase Console → your project → **Authentication** → **Users** tab → **Add user**. Email can be anything (doesn't need to be a real/COMSATS address) — pick a real password, since this genuinely guards access to every student's personal data. After creating it, click into the new user row and copy the **User UID**.

**Step 2 — Grant that account admin access.**
Firestore Database → **Data** tab → **Start collection** → Collection ID: `admins` (exact lowercase) → Document ID: **paste the UID from Step 1**, don't let it auto-generate one → add any single field (e.g. `role: "librarian"`, content doesn't matter) → **Save**.

**Step 3 — Fill in the dashboard's Firebase config.**
Open `lib/firebase_options.dart`, find the `web` block, and copy `apiKey`, `appId`, `messagingSenderId`, and `storageBucket` into the matching values inside `admin-dashboard.html`'s `<script>` tag. (`authDomain` and `projectId` are already correct — they follow a predictable pattern from the project ID.) This is not secret data; the same config already ships inside every copy of the mobile app.

**Step 4 — Serve it over a real HTTP origin. Do NOT open it by double-clicking the file.**

> **`file://` origins genuinely do not work correctly with Firebase's SDKs.** Firebase Auth and Firestore both rely on browser mechanisms (IndexedDB persistence, iframe coordination) that need a stable origin — `file://` pages get treated as unique, isolated origins essentially every load. **Always serve this file over `http://`, even for local testing.**

```powershell
cd path\to\project\root
python -m http.server 8000
```
Leave that terminal running, then open `http://localhost:8000/admin-dashboard.html` in your browser.

For anything beyond quick local testing, host it properly via Firebase Hosting instead of a throwaway local server:
```powershell
firebase init hosting
firebase deploy --only hosting
```

### Day-to-day usage

1. Open the dashboard's real URL (localhost during dev, or your Hosting URL once deployed).
2. Log in with the admin account from Step 1.
3. Pick a section (**Registrations** or **Password Changes**); the **Pending** tab shows new requests as they come in, in real time.
4. Review the details, click **Approve** or **Reject**.
5. If a red processing-error banner appears after approving, something failed server-side (most likely a Koha connectivity or credentials issue) — check `firebase functions:log` for the specific error, fix the underlying issue, and the same request can generally be retried by flipping its status back and forth.

### Adding more admins

There's no "invite an admin" button — creating a new admin is always Steps 1-2 above, repeated. This is intentional: granting elevated access is never something the client (or the dashboard itself) can do to itself.

---

## Known gotchas and lessons learned

Recorded here so the same debugging time doesn't get spent twice.

**PowerShell's `-Encoding UTF8` writes a byte-order mark (BOM).** Dart's compiler tolerates it silently; Firestore's rules compiler does not (`token recognition error at: '﻿'`). Fix: write files via `[System.IO.File]::WriteAllText(path, content, [System.Text.UTF8Encoding]::new($false))` instead of `Set-Content -Encoding UTF8`, which is what every file-write command in this project's history now uses.

**Special characters (em dashes, `§`, etc.) can get silently mangled when pasted into a misconfigured terminal**, producing mojibake like `â€"` baked permanently into the file — not a display bug, genuinely corrupted content. `admin-dashboard.html` had this happen to it once. The practical fix adopted here: avoid non-ASCII characters entirely in files that get written via terminal paste, using plain hyphens instead of em dashes throughout.

**Firestore composite indexes are required for any query combining an equality/range filter with an `orderBy` on a different field**, and are not auto-created. Every distinct field combination needs its own index — `email`+`createdAt` and `status`+`createdAt` are two separate indexes in this project, not one. An unhandled `FAILED_PRECONDITION` from a missing index, if not caught, can hang an app in a loading state forever.

**`file://` origins break Firebase's SDKs in confusing, hard-to-diagnose ways.** See the admin dashboard section above — always serve over real HTTP, even locally.

**PowerShell command blocks are sometimes skipped when pasting a long sequence of multiple blocks** — several rounds of "this file doesn't exist" or "this import is missing" during this build traced back to a specific `Write-NoBom` block simply never having been run, not a bug in the code or logic. Worth double-checking with a targeted `Select-String` (or `Test-Path`) after any multi-block delivery, rather than assuming every block executed.

**Client-embedded encryption keys can only ever be one-directional.** The app can hold an RSA public key safely (encrypt-only), but a shared AES key would have had to live in the app too, and anything embedded in a compiled app can be extracted from the APK. This is why registration encryption is asymmetric (RSA-OAEP), not symmetric — the private key never leaves the Cloud Function's environment.

**Cloud Functions triggers are not guaranteed exactly-once.** `onStudentRequestApproved` and `onPasswordChangeApproved` are both written to be safely re-runnable — they check for already-existing Firebase users/Koha patrons before creating new ones, and check whether the encrypted-password field is already gone before doing any work at all.

---

## Project setup (fresh clone)

```powershell
git clone https://github.com/MuaazTasawar/junaid-zaidi-library-app.git
cd junaid-zaidi-library-app
flutter pub get

cd functions
npm install
cd ..
```

You'll also need:
- `android/app/google-services.json` — committed to this repo (environment config, not a secret).
- A Firebase project with Email/Password sign-in enabled, both composite indexes deployed, and rules deployed — see the Firestore sections above.
- A generated RSA keypair — public half in `lib/config/crypto_constants.dart`, private half in `functions/.env` — see `AUTHENTICATION.md` for the exact steps.
- Koha staff API credentials in `functions/.env`, if you need real account automation — otherwise a debug-mode test login (`testuser` / `test1234`) works without any Koha server at all, for local testing only.
- `admin-dashboard.html` configured per the setup guide above, if you need approval capability.

```powershell
flutter run
```

For the full setup and run walkthrough — Firebase project setup, RSA key generation, Cloud Functions deployment, Koha configuration, and an end-to-end test — see `AUTHENTICATION.md`.

## Repo layout

```
lib/
├── main.dart                        App entry, Firebase init, theme setup
├── firebase_options.dart            Generated by flutterfire CLI (android + web)
├── config/
│   ├── api_constants.dart           Koha URL, Azure tenant ID, Firestore collection names
│   └── crypto_constants.dart        Embedded RSA public key
├── models/
│   ├── student_request.dart         student_requests document shape
│   ├── password_change_request.dart password_change_requests document shape
│   ├── app_user.dart                users document shape
│   └── profile_data.dart            Shared "who's signed in" shape
├── services/
│   ├── crypto_service.dart          RSA-OAEP client-side encryption (encrypt-only)
│   ├── firebase_auth_service.dart   Firebase sign-in/out, Microsoft OAuth (unwired), sign-in failure descriptions
│   ├── firestore_service.dart       student_requests + password_change_requests + users CRUD
│   ├── koha_auth_service.dart       Koha login (dual-auth, real path), debug-only test account
│   ├── koha_api_client.dart         Reusable Bearer-token HTTP client for future catalog features
│   ├── secure_storage_service.dart  Koha session token + guest-mode flag
│   └── profile_loader.dart          Shared profile-loading logic (ProfileScreen + MoreScreen)
├── navigation/
│   ├── routes.dart                  AuthRoutes + MoreRoutes
│   └── auth_scope.dart              InheritedWidget: onLogout + isGuest
├── theme/ , widgets/                 Design tokens + shared UI primitives
└── screens/
    ├── root_shell.dart
    ├── home_screen.dart / library_resources_screen.dart / explore_spaces_screen.dart
    ├── more/                        Profile, request_password_change_screen.dart, Guides, Map, About
    └── auth/                        AuthGate, Welcome, SignupForm (single screen), EmailLogin (dual-auth)

functions/                           Cloud Functions (Node.js) — account creation + password sync automation
admin-dashboard.html                 Standalone web admin tool — see dedicated section above
AUTHENTICATION.md                    Full authentication architecture + setup/run walkthrough
firestore.rules / firestore.indexes.json
mock-koha-server.js                  Dev-only, delete before shipping if still present
```

## Explicit replace-before-shipping checklist

| Item | Location | Action |
|---|---|---|
| Hardcoded dev login (`testuser`/`test1234`) | `lib/services/koha_auth_service.dart` | Already gated behind `kDebugMode` and compiled out of release builds — verify with `grep -n "DEV-ONLY"` before shipping, but no code change should be required |
| RSA keypair | `lib/config/crypto_constants.dart`, `functions/.env` | The pair currently in the repo was generated for development and shared in chat/docs — generate a fresh pair before any real student data flows through this |
| Mock Koha server | `mock-koha-server.js` (project root, if still present) | Delete |
| Azure tenant ID | `lib/config/api_constants.dart` → `azureTenantId` | Confirm this is genuinely COMSATS' tenant — it was taken from a sample payload, never explicitly stated as authoritative |
| Admin dashboard hosting | `admin-dashboard.html` | Move off a local `python -m http.server` onto real Firebase Hosting before any real staff member relies on it day to day |
| Koha staff API credentials | `functions/.env` | Confirm `KOHA_STAFF_BASE_URL`, `KOHA_OAUTH_CLIENT_ID/SECRET`, `KOHA_PATRON_CATEGORY_CODE`, `KOHA_LIBRARY_BRANCHCODE` against a real Koha instance — none of this was tested against a live Koha server |
| Secrets in `.env` | `functions/.env` | Deploy-time env config, not Secret Manager — migrate to `firebase functions:secrets:set` before handling real student data at scale |
| Microsoft OAuth | Welcome screen, onboarding flow | Not wired to any UI — either finish wiring it in, or remove the unused service/model/rules if it's genuinely not needed |

## Known limitations and open work

- **Microsoft OAuth has no UI path** — see above.
- **No catalog/checkouts/holds/renewals/fines features exist yet** — `koha_api_client.dart` is ready-made infrastructure for whichever gets built first, but nothing calls it yet.
- **iOS not targeted** — only `android/` and `web/` platform folders exist in the repo.
- **Library Resources / Explore Spaces tabs** — still placeholder empty states, unrelated to auth.
- **Koha patron-password-update endpoint is unverified** — `functions/index.js` uses an educated-guess path (`PUT /api/v1/patrons/{id}/password`); confirm against your Koha version's actual API docs.
- **Department/CNIC have no first-class Koha field** — `createKohaPatron` in `functions/index.js` has a commented-out `extended_attributes` mapping, ready to enable once matching Patron Attribute Types are defined in Koha.
- **Admin dashboard has no audit trail** — approving/rejecting doesn't record which admin did it or when (beyond Firestore's own document history if you dig for it). Would need a small schema addition (`reviewedBy`, `reviewedAt` fields) if that matters going forward.