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
  String get registrationFailed => 'Registration failed. Please try again.';

  @override
  String get googleSignInButton => 'Continue with Google';

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
  String get chatFirstWriterHint =>
      'You\'re first: write the introduction of the story!';

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
}
