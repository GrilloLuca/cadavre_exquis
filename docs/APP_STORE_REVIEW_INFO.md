# App Store Connect: App Review information

Answers for the App Review questionnaire, based on `master` at 1.1.3. Fill in the bracketed parts before submitting.

## 2. Purpose and target audience

Cadavre Exquisite is a collaborative writing game based on the surrealist "exquisite corpse" parlour game. Four players each write one part of a short story. Each writer sees only the last five words of the part before theirs. When all four parts are written, the whole story is revealed to everyone, and the result is usually surprising and funny.

The game is for adults and teens who like creative writing, word games and light social play. It answers the question "what can I write today?" with a short prompt and almost no commitment: one part takes a minute or two. Players get a small creative habit, a sense of writing something together with strangers or friends, and a growing library of finished stories to read.

Players join a public room for their language (Italian, English, Spanish, French or German), or they can create a password-protected private room to play only with friends.

## 3. Setup and access instructions

- Sign in with email and password (you can register in the app) or with Google. Review account: **[email] / [password]**
- **Write:** on the home screen, open a story that's waiting for its next part, or start a new one. You'll see the last five words of the previous part. Write at least five words and submit.
- **Read:** finished stories are under completed stories, and you can search them by keyword. Stories still being written are listed with their keywords.
- **Private room:** Profile/menu → Private room → create one with a name and password, or join an existing one.
- **Safety:** use the menu next to any part to report it or block its author. Blocked authors can be managed in Profile.
- **Mature stories:** completed stories that AI moderation marks as mature are age-gated. The app asks for the iOS Declared Age Range first, and if that isn't available it asks for the birth year. Minors see these stories as locked tiles.
- **Notifications:** after you write a part, the app offers to notify you when the story continues or is completed.
- **Account deletion:** Profile → Delete account. Parts you wrote stay in their stories, shown as "Anonymous".
- No sample files are needed.

## 4. External services

- **Firebase Authentication:** email/password and Google Sign-In accounts.
- **Cloud Firestore:** stores stories, rooms and user profiles.
- **Cloud Functions for Firebase:** server-side logic such as moderation, report handling, notifications and account anonymization.
- **Google Gemini API (gemini-3.1-flash-lite):** moderates each part as it's submitted, flags mature stories, rejects nonsense parts, and generates story titles and keywords.
- **Firebase Cloud Messaging / APNs:** push notifications.
- **Google AdMob**, with Google's User Messaging Platform for consent: banner ads.
- **Apple Declared Age Range** (iOS 26+): the age check for mature stories. The age result stays on the device.

## 5. Regional differences

The app works the same way in every region. The only differences are:

- **Ad consent:** in regions that require it (EEA, UK, Switzerland), Google's consent form appears and an "Ad privacy settings" option is available.
- **Default room:** the starting language room comes from the device language, falling back to English. Users can change it at any time.
- **Interface language:** the interface is in Italian or English.

## 6. Regulated industry / third-party material

Not applicable. The app isn't in a regulated industry and doesn't include protected third-party content. All stories are written by users and moderated under the in-app terms of use, which include reporting, blocking, and review of reports within 24 hours.

## Before submitting

- **Review account:** create a demo account. For the reviewer to see the full game quickly, it helps if that account already has a waiting story and at least one completed story. If one account can't write two parts of the same story in a row, give them two accounts.
- **Sign in with Apple:** the app offers Google sign-in but not Sign in with Apple. Under guideline 4.8, Apple usually accepts your own email/password registration as the equivalent option, but reviewers sometimes question it.
- **App Tracking Transparency:** `Info.plist` has no `NSUserTrackingUsageDescription`, so AdMob serves non-personalized ads on iOS. Your App Privacy answers should match that.
- **Age rating:** the ad content rating is capped at Teen, and the AdMob target-audience setting is still a TODO in `ads_repository_admob.dart`. Keep the age rating consistent with mature stories being age-gated.
