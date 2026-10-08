// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get loginButton => 'Log In';

  @override
  String get registerButton => 'Register';

  @override
  String get emailHint => 'Enter your email';

  @override
  String get passwordHint => 'Enter your password';

  @override
  String get loginFailed => 'Login failed. Please try again.';

  @override
  String get loginInvalidCredentials => 'Incorrect email or password.';

  @override
  String get registrationFailed => 'Registration failed. Please try again.';

  @override
  String get googleSignInButton => 'Continue with Google';

  @override
  String get passwordTooShort => 'Password must be at least 6 characters.';

  @override
  String get languageRoomTooltip => 'Choose the language room';

  @override
  String get homeTabIncomplete => 'Incomplete';

  @override
  String get homeTabComplete => 'Complete';

  @override
  String get homeTabProfile => 'Profile';

  @override
  String get titleIncompleteStories => 'Incomplete stories';

  @override
  String get titleCompleteStories => 'Complete stories';

  @override
  String get titleProfile => 'Profile';

  @override
  String get noIncompleteStories =>
      'No stories to continue right now.\nCreate a new one with the + button.';

  @override
  String get noCompleteStories => 'No completed stories yet.';

  @override
  String get yourStoriesHeading => 'Your stories';

  @override
  String get storyNotStarted => 'No one has started this story yet.';

  @override
  String get storyBeingWritten => 'Someone is writing the next chapter...';

  @override
  String get storyWaitingForOthers =>
      'You wrote the last chapter — waiting for another player.';

  @override
  String get newStoryTooltip => 'New story';

  @override
  String authorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count authors',
      one: '1 author',
    );
    return '$_temp0';
  }

  @override
  String get storyCompleteTitle => 'Complete story';

  @override
  String get positionIntroduction => 'Introduction';

  @override
  String get positionDevelopment1 => 'Development (1/2)';

  @override
  String get positionDevelopment2 => 'Development (2/2)';

  @override
  String get positionEpilogue => 'Epilogue';

  @override
  String get chatFirstWriterTitle =>
      'This is a new, empty story: you\'re the first to write!';

  @override
  String get chatFirstWriterHint =>
      'How it works:\n• Every story has 4 parts: Introduction, Development (1/2), Development (2/2) and Epilogue. You\'re writing the Introduction.\n• The next player only sees the last 5 words of your part, so end with a good hook!\n• You can\'t write two parts in a row: after your turn, someone else has to continue.\n• While you\'re writing, the story is locked for everyone else.\n• Once the Epilogue is written, the whole story appears in the Complete tab for everyone to read.';

  @override
  String get storySoFarLabel => 'So far it reads...';

  @override
  String chatMessageHint(String position) {
    return 'Write here: $position...';
  }

  @override
  String get sendButton => 'Send';

  @override
  String get logoutButton => 'Logout';

  @override
  String get adPrivacySettingsButton => 'Ad privacy settings';

  @override
  String get errorStoryAlreadyCompleted =>
      'This story has already been completed.';

  @override
  String get errorStoryPositionTaken =>
      'Someone else has already written this part.';

  @override
  String get errorStoryLockedByOther =>
      'This story is currently locked by another user.';

  @override
  String get errorConsecutiveTurnNotAllowed =>
      'You can\'t write two parts in a row — wait for someone else to write the next one.';

  @override
  String get genericError => 'Something went wrong. Please try again.';

  @override
  String get privateRoomMenuItem => 'Private room';

  @override
  String get leavePrivateRoomMenuItem => 'Leave private room';

  @override
  String get privateRoomTitle => 'Private room';

  @override
  String get privateRoomDescription =>
      'Create a private room for you and your friends, or join one with its name and password.';

  @override
  String get createRoomButton => 'Create a room';

  @override
  String get joinRoomButton => 'Join a room';

  @override
  String get createRoomTitle => 'Create private room';

  @override
  String get joinRoomTitle => 'Join private room';

  @override
  String get roomNameHint => 'Room name';

  @override
  String get roomPasswordHint => 'Room password';

  @override
  String get roomPasswordConfirmHint => 'Confirm password';

  @override
  String get roomNameRequired => 'Enter a room name.';

  @override
  String get roomNameInvalid =>
      'Room name can\'t contain \"/\" and must be 40 characters or fewer.';

  @override
  String get roomPasswordTooShort => 'Password must be at least 4 characters.';

  @override
  String get roomPasswordMismatch => 'Passwords don\'t match.';

  @override
  String get errorRoomNameTaken =>
      'A room with this name already exists. Try another name.';

  @override
  String get errorRoomJoinFailed => 'Room not found or password incorrect.';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String nicknameHelper(int min, int max) {
    return '$min–$max characters: letters, numbers, spaces, _ - .';
  }

  @override
  String get nicknameSaveButton => 'Save';

  @override
  String get nicknameSaved => 'Nickname saved.';

  @override
  String get nicknameRemoved => 'Nickname removed.';

  @override
  String get nicknameLoadFailed => 'Couldn\'t load your nickname.';

  @override
  String get retryButton => 'Retry';

  @override
  String nicknamePublicPreview(String name) {
    return 'In stories you\'ll appear as: $name';
  }

  @override
  String storyPartAuthor(String name) {
    return '— $name';
  }

  @override
  String get anonymousAuthor => 'Anonymous';

  @override
  String errorNicknameTooShort(int min) {
    return 'Nickname must be at least $min characters.';
  }

  @override
  String errorNicknameTooLong(int max) {
    return 'Nickname can be at most $max characters.';
  }

  @override
  String get errorNicknameInvalidCharacters =>
      'Use only letters, numbers, spaces and _ - .';
}
