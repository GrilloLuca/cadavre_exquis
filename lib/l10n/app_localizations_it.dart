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
  String get registrationFailed => 'Registrazione non riuscita. Riprova.';

  @override
  String get googleSignInButton => 'Continua con Google';

  @override
  String get languageRoomTooltip => 'Scegli la stanza della lingua';

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
  String get storyNotStarted => 'Nessuno ha ancora iniziato questa storia.';

  @override
  String get storyBeingWritten =>
      'Qualcuno sta scrivendo il prossimo capitolo...';

  @override
  String get storyWaitingForOthers =>
      'Hai scritto l\'ultimo capitolo: aspetta un altro giocatore.';

  @override
  String get newStoryTooltip => 'Nuova storia';

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
  String get chatFirstWriterHint =>
      'Sei il primo: scrivi tu l\'introduzione della storia!';

  @override
  String get storySoFarLabel => 'Finora è stato scritto...';

  @override
  String chatMessageHint(String position) {
    return 'Scrivi qui: $position...';
  }

  @override
  String get sendButton => 'Invia';

  @override
  String get logoutButton => 'Logout';

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
}
