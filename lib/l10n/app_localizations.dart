import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it')
  ];

  /// No description provided for @loginButton.
  ///
  /// In it, this message translates to:
  /// **'Accedi'**
  String get loginButton;

  /// No description provided for @registerButton.
  ///
  /// In it, this message translates to:
  /// **'Registrati'**
  String get registerButton;

  /// No description provided for @emailHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la tua email'**
  String get emailHint;

  /// No description provided for @passwordHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la tua password'**
  String get passwordHint;

  /// No description provided for @loginFailed.
  ///
  /// In it, this message translates to:
  /// **'Accesso non riuscito. Riprova.'**
  String get loginFailed;

  /// No description provided for @loginInvalidCredentials.
  ///
  /// In it, this message translates to:
  /// **'Email o password errati.'**
  String get loginInvalidCredentials;

  /// No description provided for @registrationFailed.
  ///
  /// In it, this message translates to:
  /// **'Registrazione non riuscita. Riprova.'**
  String get registrationFailed;

  /// No description provided for @googleSignInButton.
  ///
  /// In it, this message translates to:
  /// **'Continua con Google'**
  String get googleSignInButton;

  /// No description provided for @passwordTooShort.
  ///
  /// In it, this message translates to:
  /// **'La password deve avere almeno 6 caratteri.'**
  String get passwordTooShort;

  /// Title of the Room card on the Profile tab.
  ///
  /// In it, this message translates to:
  /// **'Stanza'**
  String get roomSectionTitle;

  /// Explains what the room is, under the Room card title.
  ///
  /// In it, this message translates to:
  /// **'Vedi e scrivi solo le storie della stanza in cui ti trovi.'**
  String get roomSectionDescription;

  /// Subheading above the list of language rooms.
  ///
  /// In it, this message translates to:
  /// **'Stanza della lingua'**
  String get languageRoomHeading;

  /// Caption under the language rooms while the room was picked automatically from a matching device language.
  ///
  /// In it, this message translates to:
  /// **'Scelta in base alla lingua del dispositivo.'**
  String get languageRoomAutoDetected;

  /// Caption under the language rooms when no room matches the device language and the English one is used.
  ///
  /// In it, this message translates to:
  /// **'Non c\'è ancora una stanza nella lingua del dispositivo, quindi sei in quella inglese.'**
  String get languageRoomAutoFallback;

  /// Subtitle of the private-room row while not in a private room.
  ///
  /// In it, this message translates to:
  /// **'Gioca solo con gli amici che ne conoscono nome e password.'**
  String get privateRoomRowSubtitle;

  /// Notice on the Room card while a private room is active.
  ///
  /// In it, this message translates to:
  /// **'Sei nella stanza privata “{name}”. La stanza della lingua è in pausa finché non esci.'**
  String privateRoomActiveNotice(String name);

  /// Snackbar after joining or creating a private room.
  ///
  /// In it, this message translates to:
  /// **'Ora sei in “{name}”.'**
  String privateRoomJoinedSnackbar(String name);

  /// Snackbar after leaving a private room; offers Undo.
  ///
  /// In it, this message translates to:
  /// **'Hai lasciato “{name}”.'**
  String privateRoomLeftSnackbar(String name);

  /// Snackbar action that undoes leaving a private room.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get undoButton;

  /// Tooltip and screen-reader label of the app bar room indicator in a language room; language is the room's native name.
  ///
  /// In it, this message translates to:
  /// **'Stanza: {language}. Cambiala nel Profilo.'**
  String roomIndicatorLanguage(String language);

  /// Tooltip and screen-reader label of the app bar room indicator in a private room.
  ///
  /// In it, this message translates to:
  /// **'Stanza privata: {name}. Cambiala nel Profilo.'**
  String roomIndicatorPrivate(String name);

  /// No description provided for @homeTabIncomplete.
  ///
  /// In it, this message translates to:
  /// **'Incomplete'**
  String get homeTabIncomplete;

  /// No description provided for @homeTabComplete.
  ///
  /// In it, this message translates to:
  /// **'Complete'**
  String get homeTabComplete;

  /// No description provided for @homeTabProfile.
  ///
  /// In it, this message translates to:
  /// **'Profilo'**
  String get homeTabProfile;

  /// No description provided for @titleIncompleteStories.
  ///
  /// In it, this message translates to:
  /// **'Storie incomplete'**
  String get titleIncompleteStories;

  /// No description provided for @titleCompleteStories.
  ///
  /// In it, this message translates to:
  /// **'Storie complete'**
  String get titleCompleteStories;

  /// No description provided for @titleProfile.
  ///
  /// In it, this message translates to:
  /// **'Profilo'**
  String get titleProfile;

  /// No description provided for @noIncompleteStories.
  ///
  /// In it, this message translates to:
  /// **'Nessuna storia da continuare al momento.\nCreane una nuova con il pulsante +.'**
  String get noIncompleteStories;

  /// No description provided for @noCompleteStories.
  ///
  /// In it, this message translates to:
  /// **'Nessuna storia completata, per ora.'**
  String get noCompleteStories;

  /// No description provided for @yourStoriesHeading.
  ///
  /// In it, this message translates to:
  /// **'Le tue storie'**
  String get yourStoriesHeading;

  /// No description provided for @storyNotStarted.
  ///
  /// In it, this message translates to:
  /// **'Nessuno ha ancora iniziato questa storia.'**
  String get storyNotStarted;

  /// No description provided for @storyBeingWritten.
  ///
  /// In it, this message translates to:
  /// **'Qualcuno sta scrivendo il prossimo capitolo...'**
  String get storyBeingWritten;

  /// No description provided for @storyWaitingForOthers.
  ///
  /// In it, this message translates to:
  /// **'Hai scritto l\'ultimo capitolo: aspetta un altro giocatore.'**
  String get storyWaitingForOthers;

  /// No description provided for @newStoryTooltip.
  ///
  /// In it, this message translates to:
  /// **'Nuova storia'**
  String get newStoryTooltip;

  /// No description provided for @authorsCount.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{1 autore} other{{count} autori}}'**
  String authorsCount(int count);

  /// No description provided for @storyCompleteTitle.
  ///
  /// In it, this message translates to:
  /// **'Storia completa'**
  String get storyCompleteTitle;

  /// No description provided for @positionIntroduction.
  ///
  /// In it, this message translates to:
  /// **'Introduzione'**
  String get positionIntroduction;

  /// No description provided for @positionDevelopment1.
  ///
  /// In it, this message translates to:
  /// **'Sviluppo (1/2)'**
  String get positionDevelopment1;

  /// No description provided for @positionDevelopment2.
  ///
  /// In it, this message translates to:
  /// **'Sviluppo (2/2)'**
  String get positionDevelopment2;

  /// No description provided for @positionEpilogue.
  ///
  /// In it, this message translates to:
  /// **'Epilogo'**
  String get positionEpilogue;

  /// No description provided for @chatFirstWriterTitle.
  ///
  /// In it, this message translates to:
  /// **'Questa è una storia nuova e ancora vuota: sei il primo a scrivere!'**
  String get chatFirstWriterTitle;

  /// No description provided for @chatFirstWriterHint.
  ///
  /// In it, this message translates to:
  /// **'Come funziona:\n• Ogni storia ha 4 parti: Introduzione, Sviluppo (1/2), Sviluppo (2/2) ed Epilogo. Tu scrivi l\'Introduzione.\n• Il prossimo giocatore vedrà solo le ultime 5 parole della tua parte: chiudi con un buon aggancio!\n• Non puoi scrivere due parti di fila: dopo il tuo turno deve continuare qualcun altro.\n• Mentre scrivi, la storia è bloccata per tutti gli altri.\n• Quando viene scritto l\'Epilogo, la storia intera appare nella scheda Complete e tutti possono leggerla.'**
  String get chatFirstWriterHint;

  /// No description provided for @storySoFarLabel.
  ///
  /// In it, this message translates to:
  /// **'Finora è stato scritto...'**
  String get storySoFarLabel;

  /// No description provided for @chatMessageHint.
  ///
  /// In it, this message translates to:
  /// **'Scrivi qui: {position}...'**
  String chatMessageHint(String position);

  /// No description provided for @sendButton.
  ///
  /// In it, this message translates to:
  /// **'Invia'**
  String get sendButton;

  /// No description provided for @logoutButton.
  ///
  /// In it, this message translates to:
  /// **'Logout'**
  String get logoutButton;

  /// No description provided for @deleteAccountButton.
  ///
  /// In it, this message translates to:
  /// **'Elimina account'**
  String get deleteAccountButton;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare il tuo account?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountMessage.
  ///
  /// In it, this message translates to:
  /// **'Il tuo account e il tuo nickname verranno eliminati definitivamente. Le parti che hai scritto restano nelle loro storie, come Anonimo.'**
  String get deleteAccountMessage;

  /// No description provided for @deleteAccountGoogleHint.
  ///
  /// In it, this message translates to:
  /// **'Per confermare ti verrà chiesto di scegliere di nuovo il tuo account Google.'**
  String get deleteAccountGoogleHint;

  /// No description provided for @deleteAccountConfirmButton.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get deleteAccountConfirmButton;

  /// No description provided for @cancelButton.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get cancelButton;

  /// No description provided for @accountDeleted.
  ///
  /// In it, this message translates to:
  /// **'Il tuo account è stato eliminato.'**
  String get accountDeleted;

  /// No description provided for @errorStoryAlreadyCompleted.
  ///
  /// In it, this message translates to:
  /// **'Questa storia è già stata completata.'**
  String get errorStoryAlreadyCompleted;

  /// No description provided for @errorStoryPositionTaken.
  ///
  /// In it, this message translates to:
  /// **'Qualcun altro ha già scritto questo pezzo.'**
  String get errorStoryPositionTaken;

  /// No description provided for @errorStoryLockedByOther.
  ///
  /// In it, this message translates to:
  /// **'Questa storia è bloccata da un altro utente.'**
  String get errorStoryLockedByOther;

  /// No description provided for @errorConsecutiveTurnNotAllowed.
  ///
  /// In it, this message translates to:
  /// **'Non puoi scrivere due capitoli di fila: aspetta che qualcun altro scriva il prossimo.'**
  String get errorConsecutiveTurnNotAllowed;

  /// No description provided for @genericError.
  ///
  /// In it, this message translates to:
  /// **'Si è verificato un errore. Riprova.'**
  String get genericError;

  /// No description provided for @privateRoomMenuItem.
  ///
  /// In it, this message translates to:
  /// **'Stanza privata'**
  String get privateRoomMenuItem;

  /// No description provided for @leavePrivateRoomMenuItem.
  ///
  /// In it, this message translates to:
  /// **'Esci dalla stanza privata'**
  String get leavePrivateRoomMenuItem;

  /// No description provided for @privateRoomTitle.
  ///
  /// In it, this message translates to:
  /// **'Stanza privata'**
  String get privateRoomTitle;

  /// No description provided for @privateRoomDescription.
  ///
  /// In it, this message translates to:
  /// **'Crea una stanza privata per te e i tuoi amici, oppure unisciti a una stanza esistente con nome e password.'**
  String get privateRoomDescription;

  /// No description provided for @createRoomButton.
  ///
  /// In it, this message translates to:
  /// **'Crea una stanza'**
  String get createRoomButton;

  /// No description provided for @joinRoomButton.
  ///
  /// In it, this message translates to:
  /// **'Unisciti a una stanza'**
  String get joinRoomButton;

  /// No description provided for @createRoomTitle.
  ///
  /// In it, this message translates to:
  /// **'Crea stanza privata'**
  String get createRoomTitle;

  /// No description provided for @joinRoomTitle.
  ///
  /// In it, this message translates to:
  /// **'Unisciti a una stanza privata'**
  String get joinRoomTitle;

  /// No description provided for @roomNameHint.
  ///
  /// In it, this message translates to:
  /// **'Nome della stanza'**
  String get roomNameHint;

  /// No description provided for @roomPasswordHint.
  ///
  /// In it, this message translates to:
  /// **'Password della stanza'**
  String get roomPasswordHint;

  /// No description provided for @roomPasswordConfirmHint.
  ///
  /// In it, this message translates to:
  /// **'Conferma password'**
  String get roomPasswordConfirmHint;

  /// No description provided for @roomNameRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci il nome della stanza.'**
  String get roomNameRequired;

  /// No description provided for @roomNameInvalid.
  ///
  /// In it, this message translates to:
  /// **'Il nome della stanza non può contenere \"/\" e deve avere al massimo 40 caratteri.'**
  String get roomNameInvalid;

  /// No description provided for @roomPasswordTooShort.
  ///
  /// In it, this message translates to:
  /// **'La password deve avere almeno 4 caratteri.'**
  String get roomPasswordTooShort;

  /// No description provided for @roomPasswordMismatch.
  ///
  /// In it, this message translates to:
  /// **'Le password non coincidono.'**
  String get roomPasswordMismatch;

  /// No description provided for @errorRoomNameTaken.
  ///
  /// In it, this message translates to:
  /// **'Esiste già una stanza con questo nome. Prova un altro nome.'**
  String get errorRoomNameTaken;

  /// No description provided for @errorRoomJoinFailed.
  ///
  /// In it, this message translates to:
  /// **'Stanza non trovata o password errata.'**
  String get errorRoomJoinFailed;

  /// No description provided for @nicknameLabel.
  ///
  /// In it, this message translates to:
  /// **'Nickname'**
  String get nicknameLabel;

  /// No description provided for @nicknameHelper.
  ///
  /// In it, this message translates to:
  /// **'{min}–{max} caratteri: lettere, numeri, spazi, _ - .'**
  String nicknameHelper(int min, int max);

  /// No description provided for @nicknameSaveButton.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get nicknameSaveButton;

  /// No description provided for @nicknameSaved.
  ///
  /// In it, this message translates to:
  /// **'Nickname salvato.'**
  String get nicknameSaved;

  /// Helper line under the nickname field while no nickname is set.
  ///
  /// In it, this message translates to:
  /// **'Puoi sceglierlo una sola volta.'**
  String get nicknameOnceNote;

  /// Helper text under the read-only nickname field once a nickname is set.
  ///
  /// In it, this message translates to:
  /// **'Il nickname non può essere modificato.'**
  String get nicknameLockedNote;

  /// No description provided for @nicknameConfirmTitle.
  ///
  /// In it, this message translates to:
  /// **'Conferma nickname'**
  String get nicknameConfirmTitle;

  /// Body of the dialog confirming the one-time nickname choice.
  ///
  /// In it, this message translates to:
  /// **'Nelle storie apparirai come «{name}». Non potrai più cambiarlo.'**
  String nicknameConfirmMessage(String name);

  /// No description provided for @nicknameConfirmButton.
  ///
  /// In it, this message translates to:
  /// **'Conferma'**
  String get nicknameConfirmButton;

  /// No description provided for @nicknameLoadFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile caricare il nickname.'**
  String get nicknameLoadFailed;

  /// No description provided for @retryButton.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get retryButton;

  /// No description provided for @nicknamePublicPreview.
  ///
  /// In it, this message translates to:
  /// **'Nelle storie apparirai come: {name}'**
  String nicknamePublicPreview(String name);

  /// No description provided for @storyPartAuthor.
  ///
  /// In it, this message translates to:
  /// **'— {name}'**
  String storyPartAuthor(String name);

  /// No description provided for @anonymousAuthor.
  ///
  /// In it, this message translates to:
  /// **'Anonimo'**
  String get anonymousAuthor;

  /// No description provided for @errorNicknameTooShort.
  ///
  /// In it, this message translates to:
  /// **'Il nickname deve avere almeno {min} caratteri.'**
  String errorNicknameTooShort(int min);

  /// No description provided for @errorNicknameTooLong.
  ///
  /// In it, this message translates to:
  /// **'Il nickname può avere al massimo {max} caratteri.'**
  String errorNicknameTooLong(int max);

  /// No description provided for @errorNicknameInvalidCharacters.
  ///
  /// In it, this message translates to:
  /// **'Usa solo lettere, numeri, spazi e _ - .'**
  String get errorNicknameInvalidCharacters;

  /// Shown when saving a nickname while one is already stored (e.g. set from another device).
  ///
  /// In it, this message translates to:
  /// **'Hai già scelto un nickname e non può essere cambiato.'**
  String get errorNicknameAlreadySet;

  /// Label of a locked mature story in the completed stories list: shown next to the authors count, and as the title when the story has no AI title.
  ///
  /// In it, this message translates to:
  /// **'Contenuto esplicito'**
  String get matureStoryLockedTitle;

  /// Screen-reader label of the padlock on a locked mature story.
  ///
  /// In it, this message translates to:
  /// **'bloccata'**
  String get matureStoryLockedLabel;

  /// Screen-reader tap hint on a locked mature story; the platform adds the 'Double tap to' prefix, so this is just the verb.
  ///
  /// In it, this message translates to:
  /// **'sbloccare'**
  String get matureStoryUnlockHint;

  /// Screen-reader label of the open padlock on an unlocked mature story.
  ///
  /// In it, this message translates to:
  /// **'contenuto esplicito'**
  String get matureStoryAdultContent;

  /// Snackbar when an age check denies a mature story.
  ///
  /// In it, this message translates to:
  /// **'Questa storia non è disponibile.'**
  String get matureStoryUnavailable;

  /// No description provided for @ageCheckTitle.
  ///
  /// In it, this message translates to:
  /// **'Prima di continuare'**
  String get ageCheckTitle;

  /// No description provided for @ageCheckQuestion.
  ///
  /// In it, this message translates to:
  /// **'Qual è il tuo anno di nascita?'**
  String get ageCheckQuestion;

  /// No description provided for @ageCheckHint.
  ///
  /// In it, this message translates to:
  /// **'Anno di nascita'**
  String get ageCheckHint;

  /// No description provided for @ageCheckNote.
  ///
  /// In it, this message translates to:
  /// **'Non potrai modificare la risposta.'**
  String get ageCheckNote;

  /// No description provided for @ageCheckConfirm.
  ///
  /// In it, this message translates to:
  /// **'Conferma'**
  String get ageCheckConfirm;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
