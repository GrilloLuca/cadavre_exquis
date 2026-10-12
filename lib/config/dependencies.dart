import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository.dart';
import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository_firestore.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository_firebase.dart';
import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository_firestore.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository_firestore.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository_firestore.dart';
import 'package:cadavre_exquisite/data/services/google_sign_in_service.dart';

/// The app's repositories, provided above `MaterialApp` so every screen can
/// `context.read` them. Tests provide fakes instead.
List<SingleChildWidget> providers({
  required GoogleSignInService googleSignIn,
}) =>
    [
      ChangeNotifierProvider<AuthRepository>(
        create: (_) => AuthRepositoryFirebase(googleSignIn: googleSignIn),
      ),
      Provider<StoryRepository>(create: (_) => StoryRepositoryFirestore()),
      Provider<UserProfileRepository>(
        create: (_) => UserProfileRepositoryFirestore(),
      ),
      Provider<AgeCheckRepository>(
        create: (_) => AgeCheckRepositoryFirestore(),
      ),
      Provider<PrivateRoomRepository>(
        create: (_) => PrivateRoomRepositoryFirestore(),
      ),
    ];
