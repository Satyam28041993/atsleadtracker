# atsleadtracker (ATS CRM)

A Flutter lead-tracking CRM ("ATS CRM" / Applied Technology Systems) backed by Firebase.
Targets **Web** and **Android** only (see `firebase.json` and `lib/firebase_options.dart`).

## Cursor Cloud specific instructions

### Environment / toolchain
- The Flutter SDK (stable, includes Dart) is installed at `~/flutter` and is on `PATH` via `~/.bashrc`.
  If `flutter` is not found in a non-login shell, prefix commands with `~/flutter/bin/` (e.g. `~/flutter/bin/flutter ...`).
- The startup update script runs `flutter pub get` (root) and `npm install` in `functions/`. You normally
  do not need to install anything else.

### Services
- **Flutter app** (primary): the whole product. Standard commands (run from repo root):
  - Lint: `flutter analyze` — currently reports ~34 pre-existing `info`/`warning` lints (deprecations, `avoid_print`, etc.) and **no errors**. Treat those as baseline, not regressions.
  - Test: `flutter test` (a single smoke test in `test/widget_test.dart`).
  - Run (web dev): `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080` (or `-d chrome`). The first compile takes ~20–30s before it prints "serving at ...". Chrome is installed on the VM.
- **Cloud Functions** (`functions/`, Node.js): OPTIONAL. Only needed for the server-side duplicate-lead check, push follow-up reminders, and scheduled Firestore backups. `DuplicateLeadService` has a client-side Firestore fallback, so the app runs fine without deployed functions. Deploying requires the Firebase CLI + a Blaze-plan project (not available here).
- `presentaion/` is a standalone static marketing deck, unrelated to the app.

### Firebase / authentication (important gotcha)
- The app talks to the **live Firebase project `atsleadtracker`** (config hardcoded in `lib/firebase_options.dart`). There is **no emulator wiring** in `lib/`. The VM has network access to Firebase, so `Firebase.initializeApp` and Auth/Firestore calls work against the real backend.
- Login is **email/password only** via Firebase Auth. There is **no self sign-up** (the "Forgot Password"/sign-up buttons are stubs). After login, `auth_gate.dart` reads `users/{uid}.role` from Firestore and routes to the admin or employee dashboard; a user with no role doc sees an error screen.
- Therefore, to test anything **past the login screen you need real credentials** for a user that already exists in the `atsleadtracker` Firebase Auth tenant **and** has a matching `users/{uid}` role document. Without credentials you can still verify the app builds, renders the login screen, and that the auth flow reaches Firebase (submitting bad credentials returns "Incorrect email or password.").
