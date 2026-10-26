// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get loginButton => 'Accedi';

  @override
  String get registerButton => 'Registrati';

  @override
  String get emailHint => 'Inserisci la tua email';

  @override
  String get passwordHint => 'Inserisci la tua password';

  @override
  String get loginFailed => 'Accesso non riuscito. Riprova.';

  @override
  String get loginInvalidCredentials => 'Email o password errati.';

  @override
  String get registrationFailed => 'Registrazione non riuscita. Riprova.';

  @override
  String get googleSignInButton => 'Continua con Google';

  @override
  String get passwordTooShort => 'La password deve avere almeno 6 caratteri.';

  @override
  String get roomSectionTitle => 'Stanza';

  @override
  String get roomSectionDescription =>
      'Vedi e scrivi solo le storie della stanza in cui ti trovi.';

  @override
  String get languageRoomHeading => 'Stanza della lingua';

  @override
  String get languageRoomAutoDetected =>
      'Scelta in base alla lingua del dispositivo.';

  @override
  String get languageRoomAutoFallback =>
      'Non c\'è ancora una stanza nella lingua del dispositivo, quindi sei in quella inglese.';

  @override
  String get privateRoomRowSubtitle =>
      'Gioca solo con gli amici che ne conoscono nome e password.';

  @override
  String privateRoomActiveNotice(String name) {
    return 'Sei nella stanza privata “$name”. La stanza della lingua è in pausa finché non esci.';
  }

  @override
  String privateRoomJoinedSnackbar(String name) {
    return 'Ora sei in “$name”.';
  }

  @override
  String roomIndicatorLanguage(String language) {
    return 'Stanza: $language. Cambiala nel Profilo.';
  }

  @override
  String roomIndicatorPrivate(String name) {
    return 'Stanza privata: $name. Cambiala nel Profilo.';
  }

  @override
  String get homeTabIncomplete => 'Incomplete';

  @override
  String get homeTabComplete => 'Complete';

  @override
  String get homeTabProfile => 'Profilo';

  @override
  String get titleIncompleteStories => 'Storie incomplete';

  @override
  String get titleCompleteStories => 'Storie complete';

  @override
  String get titleProfile => 'Profilo';

  @override
  String get noIncompleteStories =>
      'Nessuna storia da continuare al momento.\nCreane una nuova con il pulsante +.';

  @override
  String get noCompleteStories => 'Nessuna storia completata, per ora.';

  @override
  String get yourStoriesHeading => 'Le tue storie';

  @override
  String get otherStoriesTab => 'Altre storie';

  @override
  String get noOtherCompleteStories =>
      'Nessuna storia completata da altri, per ora.';

  @override
  String get noYourCompleteStories =>
      'Non hai ancora partecipato a una storia completata.';

  @override
  String get storyNotStarted => 'Nessuno ha ancora iniziato questa storia.';

  @override
  String get storyBeingWritten =>
      'Qualcuno sta scrivendo il prossimo capitolo...';

  @override
  String get storyWaitingForOthers =>
      'Hai scritto l\'ultimo capitolo: aspetta un altro giocatore.';

  @override
  String get storyUnderReview => 'In revisione...';

  @override
  String get storyUnderReviewError =>
      'Questa storia è in revisione: riprova tra poco.';

  @override
  String get newStoryTooltip => 'Nuova storia';

  @override
  String get newStoryBlocked =>
      'Hai già iniziato una storia: aspetta che qualcuno scriva il capitolo successivo.';

  @override
  String authorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count autori',
      one: '1 autore',
    );
    return '$_temp0';
  }

  @override
  String get storyCompleteTitle => 'Storia completa';

  @override
  String get positionIntroduction => 'Introduzione';

  @override
  String get positionDevelopment1 => 'Sviluppo (1/2)';

  @override
  String get positionDevelopment2 => 'Sviluppo (2/2)';

  @override
  String get positionEpilogue => 'Epilogo';

  @override
  String chatPartProgress(int current, int total) {
    return 'Parte $current di $total';
  }

  @override
  String get chatHeadlineFirst => 'Inizia una storia nuova';

  @override
  String get chatHeadlineMiddle => 'Continua la storia';

  @override
  String get chatHeadlineLast => 'Scrivi il finale';

  @override
  String get chatLeadFirst =>
      'Tocca a te iniziare: scegli tu personaggi, luogo e cosa succede.';

  @override
  String get chatLeadMiddle =>
      'Della storia vedi solo le ultime 5 parole: riparti da lì, con la tua fantasia.';

  @override
  String get chatLeadLast =>
      'Della storia vedi solo le ultime 5 parole: portala a una conclusione.';

  @override
  String get storyKeywordsLabel => 'Di cosa parla finora';

  @override
  String chatPreviousAuthorLabel(String name, String time) {
    return '$name ha scritto $time:';
  }

  @override
  String get timeJustNow => 'poco fa';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minuti fa',
      one: '1 minuto fa',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ore fa',
      one: '1 ora fa',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni fa',
      one: '1 giorno fa',
    );
    return '$_temp0';
  }

  @override
  String chatLastWords(String words) {
    return '…$words';
  }

  @override
  String get chatInputHint => 'Scrivi qui la tua parte…';

  @override
  String chatInputLabel(String position) {
    return 'La tua parte: $position';
  }

  @override
  String get chatReservingTurn => 'Sto riservando il tuo turno…';

  @override
  String get chatSending => 'Invio…';

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
  String chatWordsMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mancano ancora $count parole',
      one: 'Manca ancora 1 parola',
    );
    return '$_temp0';
  }

  @override
  String get chatSentSnackbar => 'Parte inviata! Ora tocca a qualcun altro.';

  @override
  String get chatCompletedSnackbar => 'Storia completata!';

  @override
  String get chatLeaveTitle => 'Uscire senza inviare?';

  @override
  String get chatLeaveBody =>
      'Quello che hai scritto andrà perso e la storia tornerà libera per gli altri.';

  @override
  String get chatLeaveCancel => 'Continua a scrivere';

  @override
  String get chatLeaveConfirm => 'Esci';

  @override
  String get sendButton => 'Invia';

  @override
  String get logoutButton => 'Logout';

  @override
  String get adPrivacySettingsButton => 'Privacy e annunci';

  @override
  String get deleteAccountButton => 'Elimina account';

  @override
  String get deleteAccountTitle => 'Eliminare il tuo account?';

  @override
  String get deleteAccountMessage =>
      'Il tuo account e il tuo nickname verranno eliminati definitivamente. Le parti che hai scritto restano nelle loro storie, come Anonimo.';

  @override
  String get deleteAccountGoogleHint =>
      'Per confermare ti verrà chiesto di scegliere di nuovo il tuo account Google.';

  @override
  String get deleteAccountConfirmButton => 'Elimina';

  @override
  String get cancelButton => 'Annulla';

  @override
  String get accountDeleted => 'Il tuo account è stato eliminato.';

  @override
  String get errorStoryAlreadyCompleted =>
      'Questa storia è già stata completata.';

  @override
  String get errorStoryPositionTaken =>
      'Qualcun altro ha già scritto questo pezzo.';

  @override
  String get errorStoryLockedByOther =>
      'Questa storia è bloccata da un altro utente.';

  @override
  String get errorConsecutiveTurnNotAllowed =>
      'Non puoi scrivere due capitoli di fila: aspetta che qualcun altro scriva il prossimo.';

  @override
  String get genericError => 'Si è verificato un errore. Riprova.';

  @override
  String get privateRoomMenuItem => 'Stanza privata';

  @override
  String get leavePrivateRoomMenuItem => 'Esci dalla stanza privata';

  @override
  String get privateRoomTitle => 'Stanza privata';

  @override
  String get privateRoomDescription =>
      'Crea una stanza privata per te e i tuoi amici, oppure unisciti a una stanza esistente con nome e password.';

  @override
  String get createRoomButton => 'Crea una stanza';

  @override
  String get joinRoomButton => 'Unisciti a una stanza';

  @override
  String get createRoomTitle => 'Crea stanza privata';

  @override
  String get joinRoomTitle => 'Unisciti a una stanza privata';

  @override
  String get roomNameHint => 'Nome della stanza';

  @override
  String get roomPasswordHint => 'Password della stanza';

  @override
  String get roomPasswordConfirmHint => 'Conferma password';

  @override
  String get roomNameRequired => 'Inserisci il nome della stanza.';

  @override
  String get roomNameInvalid =>
      'Il nome della stanza non può contenere \"/\" e deve avere al massimo 40 caratteri.';

  @override
  String get roomPasswordTooShort =>
      'La password deve avere almeno 4 caratteri.';

  @override
  String get roomPasswordMismatch => 'Le password non coincidono.';

  @override
  String get errorRoomNameTaken =>
      'Esiste già una stanza con questo nome. Prova un altro nome.';

  @override
  String get errorRoomJoinFailed => 'Stanza non trovata o password errata.';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String nicknameHelper(int min, int max) {
    return '$min–$max caratteri: lettere, numeri, spazi, _ - .';
  }

  @override
  String get nicknameSaveButton => 'Salva';

  @override
  String get nicknameSaved => 'Nickname salvato.';

  @override
  String get nicknameOnceNote => 'Puoi sceglierlo una sola volta.';

  @override
  String get nicknameLockedNote => 'Il nickname non può essere modificato.';

  @override
  String get nicknameConfirmTitle => 'Conferma nickname';

  @override
  String nicknameConfirmMessage(String name) {
    return 'Nelle storie apparirai come «$name». Non potrai più cambiarlo.';
  }

  @override
  String get nicknameConfirmButton => 'Conferma';

  @override
  String get nicknameLoadFailed => 'Impossibile caricare il nickname.';

  @override
  String get retryButton => 'Riprova';

  @override
  String nicknamePublicPreview(String name) {
    return 'Nelle storie apparirai come: $name';
  }

  @override
  String storyPartAuthor(String name) {
    return '— $name';
  }

  @override
  String get anonymousAuthor => 'Anonimo';

  @override
  String errorNicknameTooShort(int min) {
    return 'Il nickname deve avere almeno $min caratteri.';
  }

  @override
  String errorNicknameTooLong(int max) {
    return 'Il nickname può avere al massimo $max caratteri.';
  }

  @override
  String get errorNicknameInvalidCharacters =>
      'Usa solo lettere, numeri, spazi e _ - .';

  @override
  String get errorNicknameAlreadySet =>
      'Hai già scelto un nickname e non può essere cambiato.';

  @override
  String get matureStoryLockedTitle => 'Contenuto esplicito';

  @override
  String get matureStoryLockedLabel => 'bloccata';

  @override
  String get matureStoryUnlockHint => 'sbloccare';

  @override
  String get matureStoryAdultContent => 'contenuto esplicito';

  @override
  String get matureStoryUnavailable => 'Questa storia non è disponibile.';

  @override
  String get matureStoryUnavailableLabel => 'Non disponibile';

  @override
  String get ageCheckTitle => 'Prima di continuare';

  @override
  String get ageCheckQuestion => 'Qual è il tuo anno di nascita?';

  @override
  String get ageCheckHint => 'Anno di nascita';

  @override
  String get ageCheckNote => 'Non potrai modificare la risposta.';

  @override
  String get ageCheckConfirm => 'Conferma';

  @override
  String get notificationOfferTitle =>
      'Vuoi sapere quando qualcuno continua la tua storia?';

  @override
  String get notificationOfferMessage =>
      'Ti mandiamo una notifica quando qualcuno scrive il pezzo successivo e quando la storia è completa.';

  @override
  String get notificationOfferAccept => 'Sì, avvisami';

  @override
  String get notificationOfferDecline => 'Non ora';

  @override
  String get notificationsSectionTitle => 'Notifiche';

  @override
  String get notificationsOn =>
      'Attive: ti avvisiamo quando qualcuno continua le tue storie e quando sono complete.';

  @override
  String get notificationsOff =>
      'Attivale per sapere quando qualcuno continua le tue storie e quando sono complete.';

  @override
  String get notificationsDenied =>
      'Sono disattivate nelle impostazioni del telefono: attivale lì per riceverle.';

  @override
  String get notificationsEnableButton => 'Attiva';

  @override
  String get notificationOpenAction => 'Apri';

  @override
  String get storyNotFound => 'Questa storia non è più disponibile.';

  @override
  String get storyNotReadyYet =>
      'La storia sarà pronta da leggere tra un momento.';

  @override
  String get searchStoriesHint => 'Cerca per titolo o argomento';

  @override
  String get searchStoriesLabel => 'Cerca storie';

  @override
  String get clearSearch => 'Cancella ricerca';

  @override
  String storiesTabCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String noMatchingStories(String query) {
    return 'Nessuna storia trovata per «$query».';
  }

  @override
  String noMatchingStoriesHere(String query) {
    return 'Nessuna storia trovata qui per «$query».';
  }

  @override
  String get noMatchingStoriesHint =>
      'Prova con un\'altra parola, oppure scrivila al singolare.';

  @override
  String showMatchesInTab(int count, String tab) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vedi $count storie in «$tab»',
      one: 'Vedi 1 storia in «$tab»',
    );
    return '$_temp0';
  }

  @override
  String storyKeywordsSemantics(String keywords) {
    return 'Argomenti: $keywords';
  }

  @override
  String get partSafetyMenuTooltip => 'Segnala o blocca';

  @override
  String get reportPartMenuItem => 'Segnala questa parte';

  @override
  String blockAuthorMenuItem(Object name) {
    return 'Blocca $name';
  }

  @override
  String get reportReasonTitle => 'Perché la segnali?';

  @override
  String get reportReasonOffensive => 'Offensiva o di odio';

  @override
  String get reportReasonSexual => 'Contenuti sessuali';

  @override
  String get reportReasonHarassment => 'Molestie o bullismo';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonOther => 'Altro';

  @override
  String get reportSentSnackbar =>
      'Grazie della segnalazione. La esamineremo entro 24 ore.';

  @override
  String blockAuthorTitle(Object name) {
    return 'Bloccare $name?';
  }

  @override
  String blockAuthorMessage(Object name) {
    return 'Non vedrai più le storie con parti scritte da $name. Puoi annullare il blocco nel Profilo.';
  }

  @override
  String get blockAuthorConfirmButton => 'Blocca';

  @override
  String authorBlockedSnackbar(Object name) {
    return 'Hai bloccato $name.';
  }

  @override
  String get blockedAuthorsTitle => 'Giocatori bloccati';

  @override
  String get blockedAuthorsEmpty => 'Non hai bloccato nessuno.';

  @override
  String get unblockButton => 'Sblocca';

  @override
  String supportContact(Object email) {
    return 'Serve aiuto o vuoi segnalare un giocatore o una storia? Scrivi a $email';
  }

  @override
  String get termsNotice =>
      'Continuando accetti le condizioni d\'uso. Non sono tollerati contenuti offensivi, d\'odio, sessuali o abusivi.';

  @override
  String get termsButton => 'Condizioni d\'uso';

  @override
  String get termsTitle => 'Condizioni d\'uso';

  @override
  String termsBody(Object email) {
    return 'Cadavre Exquisite è un gioco in cui si scrivono storie insieme. Usandolo accetti queste condizioni.\n\n• Non scrivere contenuti offensivi, d\'odio, sessuali, violenti o abusivi, non molestare gli altri giocatori e non condividere dati personali. Non c\'è tolleranza per i contenuti inappropriati né per chi si comporta in modo abusivo.\n• Ogni parte viene controllata automaticamente, e puoi segnalare qualsiasi parte o bloccarne l\'autore dal menu accanto. Esaminiamo le segnalazioni entro 24 ore: rimuoviamo i contenuti che violano queste condizioni e chiudiamo gli account di chi li ha scritti.\n• Sei responsabile di ciò che scrivi. Le parti che scrivi restano nelle loro storie, come Anonimo se elimini l\'account.\n\nDomande o segnalazioni: $email';
  }

  @override
  String get closeButton => 'Chiudi';

  @override
  String get partRemovedByModeration =>
      'Questa parte è stata rimossa dalla moderazione.';
}
