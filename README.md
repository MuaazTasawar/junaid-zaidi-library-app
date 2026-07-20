# Junaid Zaidi Library App

A Flutter app for the Junaid Zaidi Library at COMSATS University Islamabad. Students can browse library resources and spaces, read guides and rules, find the library on a map, and — as of this feature — register for and log into an account.

This is a Flutter port of an original Expo Router (React Native) app; several comments in the codebase point back at the `.js` file each screen mirrors, which is intentional and worth keeping when you touch those files.

## App structure

Four bottom tabs, each mirroring an `app/(tabs)/*.js` route from the original:

| Tab | Screen | Status |
|---|---|---|
| Home | `home_screen.dart` | Hero banner, search box, resource shortcut grid |
| Library Resources | `library_resources_screen.dart` | Under construction (empty state) |
| Explore Spaces | `explore_spaces_screen.dart` | Under construction (empty state) |
| More | `more/more_screen.dart` | Menu → Profile, Guides, Map, About (+ Facts/Rules/Staff/Floor Plan sub-pages) |

Navigation is `IndexedStack` + `BottomNavigationBar` in `root_shell.dart`, so switching tabs preserves each tab's state — no rebuild, no lost scroll position. The **More** tab owns its own nested `Navigator` (`app_tab_scope.dart` + `MoreRoutes`) for its internal stack (Profile → Guides → Map → About → About/Facts, etc.), with `PopScope` wired so the Android back button pops that inner stack before it pops the outer app.

Three "More" menu items — Contact Us, Event Calendar, Junaid Zaidi Gallery — are intentionally inert (`routeName: null` in `more_menu.dart`) and show a "Coming soon" badge instead of navigating anywhere. That's by design, not a bug, per the original project brief.

The map screen renders an OpenStreetMap view through `services/osm_map_html.dart` — an HTML string fed into `webview_flutter`, not a native map SDK.

## Auth (this feature)

Registration and login run on two entirely separate services — mixing them up is the easiest way to break this feature, so it's worth being explicit about the split:

| Service | Job | Never does |
|---|---|---|
| `FirebaseAuthService` | Proves a student controls their email, during sign-up only | Issue the real app session |
| `KohaAuthService` | The actual login (`POST /api/v1/auth/password`), the real session | Get touched during sign-up |

Firebase Dynamic Links is dead (shut down August 25, 2025), which is why sign-up uses plain `sendEmailVerification()` instead of the old passwordless-link pattern — no Hosting domain or deep links required.

**Flow:**
1. Student signs up (`signup_email_screen.dart`) → temp Firebase account created → verification email sent.
2. Student clicks the link, taps "I've verified" (`verify_email_screen.dart`) → app re-checks `emailVerified`.
3. Student fills in registration details (`signup_form_screen.dart`) → written to Firestore `student_requests` (status `Pending`) → temp Firebase account signed out. Firebase's job ends here.
4. A librarian manually reviews the request in the Firebase Console (Firestore → `student_requests`) and, outside this app, creates the real Koha patron record and changes `status` to `Approved`. There is no in-app admin tool for this by design — approval credentials never ship inside the mobile client.
5. Once approved, the student logs in (`login_screen.dart`) with their Koha username/password. This goes straight to Koha, never through Firebase.

`AuthGate` (`screens/auth/auth_gate.dart`) sits in front of `RootShell` in `main.dart`: on boot it checks `KohaAuthService.isLoggedIn()` (a Koha token in secure storage) and shows either the signed-out auth flow (its own nested `Navigator`, same pattern as the More tab) or `RootShell` directly. A successful login flips this over live, no restart needed.

Firestore access is locked down by `firestore.rules`: a student can create exactly one request for their own verified email, can read only their own request, and can never update or delete one from the client — status changes are a librarian-only, Console-side action.

## Design system

Everything — old screens and the new auth screens alike — pulls from the same token set, so nothing looks bolted on:

- `theme/tokens/` — spacing (`AppSpacing`), radius (`AppRadius`), typography (`AppTypography`), color primitives (`colors.dart`)
- `theme/semantic/` — light/dark semantic color maps (`semantic_colors.dart`, `light.dart`, `dark.dart`), accessed via `useTheme(context)`
- `theme/theme_provider.dart` — `AppThemeProvider`, wraps the whole app in `main.dart`
- `widgets/ui.dart` — the shared component barrel file (`AppText`, `AppButton`, `AppTextField`, `Heading`, `AppCard`, `ScreenContainer`, `EmptyState`, `ListRow`, `SearchInput`, `Badge`, `Avatar`, etc.)

Brand color is `#1D4ED8`. Font is Inter, loaded locally via `pubspec.yaml`'s `fonts:` block (`GoogleFonts.config.allowRuntimeFetching = false` in `main.dart` — it's bundled, not fetched at runtime).

If you're adding a new screen, start from `widgets/ui.dart` and `theme/theme.dart` before reaching for a raw `Container`/`Text` — almost everything you need already exists as a token or primitive.

## Project setup (fresh clone)

```powershell
git clone https://github.com/MuaazTasawar/junaid-zaidi-library-app.git
cd junaid-zaidi-library-app
flutter pub get
```

You'll also need:
- `android/app/google-services.json` — already committed to this repo (it's environment config, not a secret; the real access control is `firestore.rules`).
- A Firebase project with Email/Password sign-in enabled and Firestore rules deployed (`firebase deploy --only firestore:rules`) — both already done for `comsats-library-app`; only relevant if you're pointing this at a different Firebase project.
- Your Koha instance's base URL set in `lib/config/api_constants.dart` (`ApiConstants.kohaBaseUrl`).

```powershell
flutter run
```

## Repo layout

```
lib/
├── main.dart                        App entry, Firebase init, theme setup
├── firebase_options.dart            Generated by flutterfire CLI — android + web only
├── config/
│   └── api_constants.dart           Koha base URL, Firestore collection name
├── models/
│   └── student_request.dart         student_requests document shape
├── services/
│   ├── firebase_auth_service.dart   Email verification only
│   ├── firestore_service.dart       student_requests CRUD
│   ├── koha_auth_service.dart       Real login, token exchange
│   ├── secure_storage_service.dart  Koha token storage
│   └── osm_map_html.dart            HTML fed into the Map tab's webview
├── data/                            Static content (home resources, more-menu items,
│                                     about-page facts, library images/location)
├── navigation/
│   ├── routes.dart                  MoreRoutes + AuthRoutes route-name constants
│   └── app_tab_scope.dart           InheritedWidget for switching bottom tabs from anywhere
├── theme/                           Design tokens + semantic color maps (see above)
├── widgets/                         Shared UI primitives (see above)
└── screens/
    ├── root_shell.dart              Bottom tab bar + IndexedStack + More-tab nested Navigator
    ├── home_screen.dart
    ├── library_resources_screen.dart
    ├── explore_spaces_screen.dart
    ├── more/                        Profile, Guides, Map, About (+ sub-pages)
    └── auth/                        AuthGate, Welcome, Login, Signup (email → verify → form)
```

## Known follow-ups

- **Koha response field names**: `koha_auth_service.dart` assumes `access_token`/`token` and `patron_id`/`borrowernumber` as response keys. Confirm against a real login response and adjust if your Koha version's `/api/v1/auth/password` returns different field names.
- **No admin approval UI**: approving/rejecting a `student_requests` document is a manual Firebase Console action for now. A proper librarian-side tool is future scope.
- **iOS**: not currently targeted — only `android/` and `web/` platform folders exist in this repo. If iOS support is added later, run `flutter create --platforms=ios .` first, then `flutterfire configure`, and use a proper reverse-DNS bundle ID (not a plain domain).
- **Library Resources / Explore Spaces tabs**: still placeholder empty states, unrelated to auth — separate future work.

## Learn more

- [Flutter docs](https://docs.flutter.dev/)
- [FlutterFire docs](https://firebase.google.com/docs/flutter/setup)
- [Koha REST API docs](https://api.koha-community.org/)