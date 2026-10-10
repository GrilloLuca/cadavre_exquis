# 📝 Cadavre Exquisite – Collaborative Story Writing App

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=flat&logo=Dart&logoColor=white)](https://dart.dev)
[![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=flat&logo=firebase&logoColor=black)](https://firebase.google.com/)

A cross-platform (Android, iOS, Web) Flutter application for **collaborative creative writing**, inspired by the surrealist game *Cadavre Exquis* (Exquisite Corpse).

Each story is written turn-by-turn by different, anonymous authors who only ever see the last few words of what came before, then it is revealed in full once complete.

---

## 🚀 Getting Started

### Prerequisites

* [Flutter SDK](https://docs.flutter.dev/get-started/install) (>=3.0.0) with the Android/iOS toolchains set up.
* A [Firebase](https://firebase.google.com/) account.

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/cadavre-exquisite-flutter.git
cd cadavre-exquisite-flutter
flutter pub get
```

### 2. Set up a Firebase project

1. Go to the [Firebase Console](https://console.firebase.google.com/) and create a new project (or use an existing one).
2. Enable **Authentication** → sign-in method **Email/Password**.
3. Enable **Cloud Firestore** (start in test mode, then apply your own security rules).
4. Register an **Android app** with the package name `com.lucagrillo.cadavreexquis`.
5. Register an **iOS app** with the bundle ID `com.lucagrillo.cadavreexquis`.

### 3. Add the Firebase config files

The app reads its Firebase configuration from the native platform files rather than a generated `firebase_options.dart`, so after registering each app in the Firebase console, download and place its config file exactly here (both are already git-ignored since they contain project-specific keys):

* **Android:** download `google-services.json` → `android/app/google-services.json`
* **iOS:** download `GoogleService-Info.plist` → `ios/Runner/GoogleService-Info.plist`

For iOS, make sure `GoogleService-Info.plist` is added to the `Runner` target in Xcode (open `ios/Runner.xcworkspace`, drag the file into the `Runner` folder, and check "Copy items if needed" + the `Runner` target membership).

### 4. Run the app

```bash
flutter run
```

### 5. (Optional) Deploy the backend

Story titles and content moderation run in Cloud Functions (`functions/`), which need the **Blaze** plan and the **Vertex AI API** enabled on the project. Gemini is called with the functions' service account, so there is no API key to configure.

```bash
firebase deploy --only firestore,functions   # rules, indexes and functions
```

The complete stories lists only show reviewed stories, so after the first deploy review the stories completed before it:

```bash
cd functions
gcloud auth application-default login
node scripts/review-complete-stories.js           # dry run
node scripts/review-complete-stories.js --write
```

---

## 🎲 The Concept

In the original paper game, each player draws a section of a creature (head, torso, legs), folding the paper to hide their contribution before passing it to the next person.

This app translates that mechanic into text: every story is split into **4 phases**, each written by a different user, who is only shown the **last 5 words** of the previous phase as a continuity hint.

### The Gameplay Loop

1. **Introduction** – the first author opens the story from a blank page.
2. **Development (1/2)** – the second author continues it, seeing only the tail end of the introduction.
3. **Development (2/2)** – the third author continues it, seeing only the tail end of the previous part.
4. **Epilogue** – the fourth author brings the story to a close.
5. **The Reveal** – once all 4 phases are written, the story is marked complete and can be read in full by anyone, with each part attributed to its author.

A story can only be written by one author at a time: while someone has it open, it's locked and shown to other users as "being written" so nobody can write the same phase twice or race a submission.

---

## 🛠️ Tech Stack & Architecture

* **Framework:** [Flutter](https://flutter.dev) — single codebase targeting Android, iOS, and Web.
* **Language:** [Dart](https://dart.dev).
* **Backend:** [Firebase Authentication](https://firebase.google.com/docs/auth) (email/password) and [Cloud Firestore](https://firebase.google.com/docs/firestore) as the real-time database. Story locking and part submission are implemented as Firestore transactions (`StoryService`) to keep concurrent writers consistent.
* **Cloud Functions:** TypeScript functions in `functions/`. `reviewCompletedStory` sends each completed story to Gemini (`gemini-3.1-flash-lite` on Vertex AI) for a title and a `mature` verdict; `normalizeStory` fills in fields that older app versions don't write.
* **State management:** plain Flutter — `StatefulWidget` + `StreamBuilder` listening directly to Firestore streams. No external state-management package.
* **Localization:** `flutter_localizations` + `intl`, driven by `.arb` files under `lib/l10n/` (English and Italian are currently supported).

### Project structure

```
lib/
├── main.dart                 # App entry point, Firebase init, auth-based routing
├── models/story.dart         # Story / StoryPart models and phase helpers
├── models/story_language.dart   # Languages available as story rooms
├── services/story_service.dart  # Firestore streams, locking & submission transactions
├── services/age_check_service.dart  # Write-once birth year for the mature stories gate
├── screens/
│   ├── welcome_screen.dart
│   ├── login_screen.dart
│   ├── registration_screen.dart
│   ├── home_screen.dart          # Bottom-nav shell (Incomplete / Complete / Profile)
│   ├── incomplete_stories_screen.dart
│   ├── complete_stories_screen.dart  # Also the age-gated mature stories list
│   ├── age_check_screen.dart     # Neutral birth-year screen
│   ├── chat_screen.dart          # Writing UI for the current phase of a story
│   ├── story_read_screen.dart    # Full read view of a completed story
│   └── account_screen.dart       # Profile & logout
└── l10n/                     # Localization templates and generated files
functions/
├── src/index.ts              # Cloud Functions: story review (title + moderation)
└── scripts/                  # One-off maintenance scripts (backfills)
```

---

## ✅ Implemented Features

- **Email/password authentication** (registration, login, logout) via Firebase Auth.
- **Create and browse incomplete stories**, joining any story you haven't already contributed to.
- **Turn-based writing** across the 4 phases described above, with only the last 5 words of the previous phase shown as a hint.
- **Exclusive locking** so a story can only be written by one author at a time, with a live "being written" indicator for everyone else.
- **Completed story archive** — read any finished story in full, part by part, with author attribution.
- **Language-based rooms** — every story belongs to a language room (🇮🇹 🇬🇧 🇪🇸 🇫🇷 🇩🇪); pick a room from the home screen and you only see, continue, and read stories in that language, so each story is written entirely by authors sharing it. New stories are created in the room you're in, and the app starts you in the room matching your device language.
- **AI story titles** — when a story is completed, a Cloud Function asks Gemini for a short title in the story's language, shown in the list and above the story.
- **Moderation of completed stories** — the same review flags stories unsuitable for children (sexual content, graphic violence, strong profanity, drugs, self-harm, hate). Flagged stories leave the normal list and move to a **Stories for adults** section, opened after a neutral age screen that asks for the birth year once and never again. Players under 18 don't see the section at all. Stories in progress are not moderated yet.
- **English and Italian localization.**

## 🚀 Roadmap

- [x] **Language-based Rooms:** join rooms filtered by language, so a story is written entirely by authors sharing the same language.
- [ ] **Public & Private Lobbies:** dedicated rooms via invite code instead of a single shared pool of stories.
- [ ] **Story Showcase Feed:** rating and sharing for completed stories.
- [ ] **Pass-and-Play (Local Offline Mode):** play locally with friends on a single device.
- [ ] **Writing timer:** optional time limit per phase to encourage stream-of-consciousness writing.

---

## 🤝 Contributing

This project is open source and welcomes contributions of any kind: feature development, refactoring, UI/UX improvements, bug fixes, or documentation.

To get started:
1. **Fork** the repository.
2. Create a feature branch (`git checkout -b feature/AmazingFeature`).
3. **Commit** your changes (`git commit -m 'Add some AmazingFeature'`).
4. **Push** to the branch (`git push origin feature/AmazingFeature`).
5. Open a **Pull Request**.
