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
  String get roomSectionTitle => 'Room';

  @override
  String get roomSectionDescription =>
      'You only see and write stories in the room you\'re in.';

  @override
  String get languageRoomHeading => 'Language room';

  @override
  String get languageRoomAutoDetected => 'Picked from your device language.';

  @override
  String get languageRoomAutoFallback =>
      'There\'s no room in your device language yet, so you\'re in the English one.';

  @override
  String get privateRoomRowSubtitle =>
      'Play only with friends who know its name and password.';

  @override
  String privateRoomActiveNotice(String name) {
    return 'You\'re in the private room “$name”. The language room is paused until you leave.';
  }

  @override
  String privateRoomJoinedSnackbar(String name) {
    return 'You\'re now in “$name”.';
  }

  @override
  String roomIndicatorLanguage(String language) {
    return 'Room: $language. Change it in Profile.';
  }

  @override
  String roomIndicatorPrivate(String name) {
    return 'Private room: $name. Change it in Profile.';
  }

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
  String get otherStoriesTab => 'Other stories';

  @override
  String get noOtherCompleteStories => 'No completed stories by others yet.';

  @override
  String get noYourCompleteStories =>
      'You haven\'t taken part in a completed story yet.';

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
  String chatPartProgress(int current, int total) {
    return 'Part $current of $total';
  }

  @override
  String get chatHeadlineFirst => 'Start a new story';

  @override
  String get chatHeadlineMiddle => 'Continue the story';

  @override
  String get chatHeadlineLast => 'Write the ending';

  @override
  String get chatLeadFirst =>
      'You\'re the first to write: you choose the characters, the place and what happens.';

  @override
  String get chatLeadMiddle =>
      'You only get to see the last 5 words of the story: carry on from there, your way.';

  @override
  String get chatLeadLast =>
      'You only get to see the last 5 words of the story: bring it to an end.';

  @override
  String get storyKeywordsLabel => 'What it\'s about so far';

  @override
  String chatPreviousAuthorLabel(String name, String time) {
    return '$name wrote $time:';
  }

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String chatLastWords(String words) {
    return '…$words';
  }

  @override
  String get chatInputHint => 'Write your part here…';

  @override
  String chatInputLabel(String position) {
    return 'Your part: $position';
  }

  @override
  String get chatReservingTurn => 'Reserving your turn…';

  @override
  String get chatSending => 'Sending…';

  @override
  String chatCharacterCount(int count, int max) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat maxNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String maxString = maxNumberFormat.format(max);

    return '$countString/$maxString';
  }

  @override
  String get chatSentSnackbar => 'Part sent! Now it\'s someone else\'s turn.';

  @override
  String get chatCompletedSnackbar => 'Story complete!';

  @override
  String get chatLeaveTitle => 'Leave without sending?';

  @override
  String get chatLeaveBody =>
      'What you\'ve written will be lost and the story will be free for others again.';

  @override
  String get chatLeaveCancel => 'Keep writing';

  @override
  String get chatLeaveConfirm => 'Leave';

  @override
  String get sendButton => 'Send';

  @override
  String get logoutButton => 'Logout';

  @override
  String get deleteAccountButton => 'Delete account';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountMessage =>
      'Your account and nickname will be deleted permanently. The parts you wrote stay in their stories, shown as Anonymous.';

  @override
  String get deleteAccountGoogleHint =>
      'You\'ll be asked to choose your Google account again to confirm.';

  @override
  String get deleteAccountConfirmButton => 'Delete';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get accountDeleted => 'Your account has been deleted.';

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
  String get nicknameOnceNote => 'You can choose it only once.';

  @override
  String get nicknameLockedNote => 'Your nickname can\'t be changed.';

  @override
  String get nicknameConfirmTitle => 'Confirm nickname';

  @override
  String nicknameConfirmMessage(String name) {
    return 'You\'ll appear as \"$name\" in stories. You won\'t be able to change it later.';
  }

  @override
  String get nicknameConfirmButton => 'Confirm';

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

  @override
  String get errorNicknameAlreadySet =>
      'You\'ve already chosen a nickname and it can\'t be changed.';

  @override
  String get matureStoryLockedTitle => 'Explicit content';

  @override
  String get matureStoryLockedLabel => 'locked';

  @override
  String get matureStoryUnlockHint => 'unlock';

  @override
  String get matureStoryAdultContent => 'explicit content';

  @override
  String get matureStoryUnavailable => 'This story isn\'t available.';

  @override
  String get ageCheckTitle => 'Before you continue';

  @override
  String get ageCheckQuestion => 'What year were you born?';

  @override
  String get ageCheckHint => 'Year of birth';

  @override
  String get ageCheckNote => 'You won\'t be able to change your answer.';

  @override
  String get ageCheckConfirm => 'Confirm';

  @override
  String get notificationOfferTitle =>
      'Want to know when someone continues your story?';

  @override
  String get notificationOfferMessage =>
      'We\'ll send you a notification when someone writes the next part and when the story is complete.';

  @override
  String get notificationOfferAccept => 'Yes, notify me';

  @override
  String get notificationOfferDecline => 'Not now';

  @override
  String get notificationsSectionTitle => 'Notifications';

  @override
  String get notificationsOn =>
      'On: we\'ll tell you when someone continues your stories and when they\'re complete.';

  @override
  String get notificationsOff =>
      'Turn them on to know when someone continues your stories and when they\'re complete.';

  @override
  String get notificationsDenied =>
      'They\'re turned off in your phone\'s settings: turn them on there to get them.';

  @override
  String get notificationsEnableButton => 'Turn on';

  @override
  String get notificationOpenAction => 'Open';

  @override
  String get storyNotFound => 'This story is no longer available.';

  @override
  String get storyNotReadyYet =>
      'This story will be ready to read in a moment.';
}
