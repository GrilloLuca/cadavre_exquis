import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

// The mobile implementation pulls in google_mobile_ads, which has no web
// support, so web builds get a factory that never imports it.
import 'package:cadavre_exquisite/config/ads_repository_factory.dart'
    if (dart.library.js_interop) 'package:cadavre_exquisite/config/ads_repository_factory_web.dart';

import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository.dart';
import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository_firestore.dart';
import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository_firebase.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository_firebase.dart';
import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository_firestore.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository_local.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository_firestore.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository_firestore.dart';
import 'package:cadavre_exquisite/data/services/google_sign_in_service.dart';
import 'package:cadavre_exquisite/data/services/language_room_preference.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';

/// The app's repositories, provided above `MaterialApp` so every screen can
/// `context.read` them. Tests provide fakes instead.
List<SingleChildWidget> providers({
  required GoogleSignInService googleSignIn,
}) =>
    [
      ChangeNotifierProvider<AuthRepository>(
        create: (_) => AuthRepositoryFirebase(googleSignIn: googleSignIn),
      ),
      // Below AuthRepository, which it reads to leave the private room on
      // sign-out.
      ChangeNotifierProvider<RoomRepository>(
        create: (context) => RoomRepositoryLocal(
          preference: LanguageRoomPreference(),
          authRepository: context.read<AuthRepository>(),
        ),
      ),
      Provider<StoryRepository>(create: (_) => StoryRepositoryFirestore()),
      Provider<UserProfileRepository>(
        create: (_) => UserProfileRepositoryFirestore(),
      ),
      Provider<AgeCheckRepository>(
        create: (_) => AgeCheckRepositoryFirestore(),
      ),
      // The app-wide age check: remembers verdicts for the session and
      // forgets them on sign-out.
      Provider<AgeGate>(
        create: (context) => AgeGate(
          storage: context.read<AgeCheckRepository>(),
          authRepository: context.read<AuthRepository>(),
        ),
        dispose: (_, gate) => gate.dispose(),
      ),
      Provider<PrivateRoomRepository>(
        create: (_) => PrivateRoomRepositoryFirestore(),
      ),
      // Below AuthRepository, which it follows to register the device for
      // the signed-in user. Created on first use (the signed-in home), so a
      // launch notification is still waiting for it.
      ChangeNotifierProvider<NotificationRepository>(
        create: (context) => NotificationRepositoryFirebase(
          authRepository: context.read<AuthRepository>(),
        ),
      ),
      // Started by the signed-in home after its first frame: the consent
      // form needs a screen to show on.
      ChangeNotifierProvider<AdsRepository>(
        create: (_) => createAdsRepository(),
      ),
    ];
