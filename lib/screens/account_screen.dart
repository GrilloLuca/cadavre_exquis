import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/author_name.dart';
import 'package:cadavre_exquisite/models/private_room.dart';
import 'package:cadavre_exquisite/models/story_language.dart';
import 'package:cadavre_exquisite/screens/complete_stories_screen.dart';
import 'package:cadavre_exquisite/screens/private_room_screen.dart';
import 'package:cadavre_exquisite/screens/welcome_screen.dart';
import 'package:cadavre_exquisite/services/age_gate.dart';
import 'package:cadavre_exquisite/services/auth_service.dart';
import 'package:cadavre_exquisite/services/language_room_preference.dart';
import 'package:cadavre_exquisite/services/user_profile_service.dart';

/// Localized message for a nickname validation/service error [code].
String _nicknameErrorMessage(
  AppLocalizations l10n,
  UserProfileServiceErrorCode code,
) {
  switch (code) {
    case UserProfileServiceErrorCode.nicknameTooShort:
      return l10n.errorNicknameTooShort(UserProfileService.minNicknameLength);
    case UserProfileServiceErrorCode.nicknameTooLong:
      return l10n.errorNicknameTooLong(UserProfileService.maxNicknameLength);
    case UserProfileServiceErrorCode.nicknameInvalidCharacters:
      return l10n.errorNicknameInvalidCharacters;
    case UserProfileServiceErrorCode.nicknameAlreadySet:
      return l10n.errorNicknameAlreadySet;
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    this.profileService,
    this.email,
    this.currentEmail,
    this.languageCode = kFallbackRoomLanguage,
    this.languageSource = RoomLanguageSource.explicit,
    this.privateRoom,
    this.onLanguageChanged,
    this.onPrivateRoomChanged,
  });

  /// Service used to read/write the nickname. Defaults to a
  /// [UserProfileService] backed by the default Firestore instance.
  final UserProfileService? profileService;

  /// Email of the signed-in user. Defaults to [currentEmail]; when provided,
  /// [FirebaseAuth] is never accessed while building.
  final String? email;

  /// Looks up the signed-in user's email when [email] is null. Defaults to
  /// the current Firebase user's email; tests use it to have no email
  /// without touching [FirebaseAuth].
  final String? Function()? currentEmail;

  /// The language room the user is in, or returns to when they leave
  /// [privateRoom]. The state lives in the home screen, which owns it for
  /// the story tabs too.
  final String languageCode;

  /// How [languageCode] was picked; anything but an explicit choice is
  /// explained with a caption.
  final RoomLanguageSource languageSource;

  /// The private room the user is in, which takes precedence over
  /// [languageCode], or null.
  final PrivateRoom? privateRoom;

  /// Called when the user picks a language room. The home screen also
  /// leaves [privateRoom], if any.
  final ValueChanged<String>? onLanguageChanged;

  /// Called with the room the user joins, or null when they leave it.
  final ValueChanged<PrivateRoom?>? onPrivateRoomChanged;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  late final UserProfileService _profileService;

  String? _email;
  bool _isLoadingNickname = false;

  /// True once a nickname is stored: it can be chosen only once, so the
  /// field becomes read-only.
  bool _hasNickname = false;
  bool _isSaving = false;
  bool _isDeleting = false;

  /// True when the last prefill attempt failed. While set, editing and
  /// saving are disabled, since the user may already have a nickname.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? UserProfileService();
    _email = widget.email ??
        (widget.currentEmail ??
            () => FirebaseAuth.instance.currentUser?.email)();
    _isLoadingNickname = _email != null;
    _loadNickname();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  /// Prefills the nickname field. On failure the form stays disabled (see
  /// [_loadFailed]) until a retry succeeds.
  Future<void> _loadNickname() async {
    final email = _email;
    if (email == null) return;
    if (!_isLoadingNickname) {
      setState(() {
        _isLoadingNickname = true;
        _loadFailed = false;
      });
    }
    var failed = false;
    try {
      final nickname = await _profileService.getNickname(email);
      if (!mounted) return;
      _nicknameController.text = nickname ?? '';
      _hasNickname = nickname != null;
    } catch (_) {
      failed = true;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingNickname = false;
          _loadFailed = failed;
        });
      }
    }
  }

  Future<void> _saveNickname() async {
    final email = _email;
    if (email == null ||
        _hasNickname ||
        _isSaving ||
        _isLoadingNickname ||
        _loadFailed) {
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final normalized =
        UserProfileService.normalizeNickname(_nicknameController.text);
    if (normalized.isEmpty) return;

    // The choice is final, so it is confirmed first.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.nicknameConfirmTitle),
        content: Text(l10n.nicknameConfirmMessage(normalized)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.nicknameConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _profileService.setNickname(email: email, nickname: normalized);
      if (!mounted) return;
      _nicknameController.text = normalized;
      setState(() => _hasNickname = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.nicknameSaved)),
      );
    } on UserProfileServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_nicknameErrorMessage(l10n, e.code)),
          backgroundColor: Colors.red,
        ),
      );
      // Set meanwhile (e.g. on another device): show the stored one.
      if (e.code == UserProfileServiceErrorCode.nicknameAlreadySet) {
        _loadNickname();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.genericError), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Asks for confirmation (and the password, for email/password users),
  /// then deletes the account and returns to the welcome screen.
  Future<void> _deleteAccount() async {
    final email = _email;
    if (email == null || _isDeleting) return;
    final l10n = AppLocalizations.of(context)!;
    final usesPassword = AuthService.usesPassword;

    final confirmation = await showDialog<_DeleteConfirmation>(
      context: context,
      builder: (_) => _DeleteAccountDialog(usesPassword: usesPassword),
    );
    if (confirmation == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isDeleting = true);
    try {
      final confirmed =
          await AuthService.reauthenticate(password: confirmation.password);
      if (!confirmed) return;
      // The anonymizeDeletedUser Cloud Function deletes the profile: the
      // rules don't let the user delete it, as that would free the
      // nickname to be chosen again.
      await AuthService.deleteAccount();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
      Navigator.pushNamedAndRemoveUntil(
        context,
        WelcomeScreen.id,
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'wrong-password' || e.code == 'invalid-credential'
                ? l10n.loginInvalidCredentials
                : l10n.genericError,
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.genericError), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Widget _buildNicknameCard(AppLocalizations l10n) {
    final isBusy = _isLoadingNickname || _isSaving || _loadFailed;
    final canEdit = !isBusy && !_hasNickname;

    return CreamCard(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              controller: _nicknameController,
              enabled: canEdit,
              // Show the counter but let the validator report "too long":
              // the limit applies to the normalized text, not the raw input.
              maxLength: UserProfileService.maxNicknameLength,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _saveNickname(),
              validator: (value) {
                final code = UserProfileService.validateNickname(value ?? '');
                return code == null ? null : _nicknameErrorMessage(l10n, code);
              },
              decoration: InputDecoration(
                labelText: l10n.nicknameLabel,
                helperText: _hasNickname
                    ? l10n.nicknameLockedNote
                    : '${l10n.nicknameHelper(
                        UserProfileService.minNicknameLength,
                        UserProfileService.maxNicknameLength,
                      )}\n${l10n.nicknameOnceNote}',
                helperMaxLines: 2,
                errorMaxLines: 2,
                suffixIcon: _isLoadingNickname
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 16.0,
                          height: 16.0,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        ),
                      )
                    : null,
                focusedBorder: const UnderlineInputBorder(
                  borderSide:
                      BorderSide(color: AppColors.primaryDark, width: 2.0),
                ),
              ),
            ),
            const SizedBox(height: 8.0),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _nicknameController,
              builder: (context, value, _) {
                final isValid =
                    UserProfileService.validateNickname(value.text) == null;
                final name = authorDisplayName(
                      nickname: isValid
                          ? UserProfileService.normalizeNickname(value.text)
                          : null,
                      email: _email,
                    ) ??
                    l10n.anonymousAuthor;
                return Text(
                  l10n.nicknamePublicPreview(name),
                  style: TextStyle(
                    fontSize: 14.0,
                    color: AppColors.ink.withValues(alpha: 0.75),
                  ),
                );
              },
            ),
            if (_loadFailed) ...[
              const SizedBox(height: 12.0),
              Row(
                children: <Widget>[
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 20.0),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      l10n.nicknameLoadFailed,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadNickname,
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
            ],
            if (!_hasNickname) ...[
              const SizedBox(height: 16.0),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: isBusy ? null : _saveNickname,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.cream,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18.0,
                          height: 18.0,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            color: AppColors.cream,
                          ),
                        )
                      : Text(l10n.nicknameSaveButton),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Picks a language room. Like the old room menu, this also leaves the
  /// private room (the home screen clears it); the snackbar's Undo goes
  /// back into it.
  void _selectLanguage(String code) {
    final leftRoom = widget.privateRoom;
    widget.onLanguageChanged?.call(code);
    if (leftRoom != null) _showLeftPrivateRoom(leftRoom);
  }

  Future<void> _openPrivateRoomPicker() async {
    final l10n = AppLocalizations.of(context)!;
    final room = await Navigator.push<PrivateRoom>(
      context,
      MaterialPageRoute(builder: (_) => const PrivateRoomScreen()),
    );
    if (room == null || !mounted) return;
    widget.onPrivateRoomChanged?.call(room);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.privateRoomJoinedSnackbar(room.name))),
      );
  }

  void _leavePrivateRoom(PrivateRoom room) {
    widget.onPrivateRoomChanged?.call(null);
    _showLeftPrivateRoom(room);
  }

  /// Confirms leaving [room], with an Undo that rejoins it without asking
  /// for the password again.
  void _showLeftPrivateRoom(PrivateRoom room) {
    final l10n = AppLocalizations.of(context)!;
    final onPrivateRoomChanged = widget.onPrivateRoomChanged;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.privateRoomLeftSnackbar(room.name)),
          action: SnackBarAction(
            label: l10n.undoButton,
            onPressed: () => onPrivateRoomChanged?.call(room),
          ),
        ),
      );
  }

  Widget _buildLanguageRow(StoryLanguage language) {
    final isSelected = language.code == widget.languageCode;
    final inPrivateRoom = widget.privateRoom != null;
    // In a private room the selected row only marks the room the user goes
    // back to, so it drops the fill that means "you are here".
    final isFilled = isSelected && !inPrivateRoom;
    final ink =
        inPrivateRoom ? AppColors.ink.withValues(alpha: 0.75) : AppColors.ink;

    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: isSelected,
        button: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isFilled ? 8.0 : 0.0),
          child: ListTile(
            minTileHeight: 48.0,
            contentPadding:
                EdgeInsets.symmetric(horizontal: isFilled ? 8.0 : 16.0),
            tileColor: isFilled ? AppColors.sage : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
            leading: ExcludeSemantics(
              child: Text(
                language.flag,
                style: const TextStyle(fontSize: 24.0),
              ),
            ),
            title: Text(
              language.nativeName,
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: ink,
              ),
            ),
            trailing: isSelected
                ? Icon(
                    inPrivateRoom ? Icons.check : Icons.check_circle,
                    size: 24.0,
                    color: AppColors.primaryDark,
                  )
                : null,
            onTap: () => _selectLanguage(language.code),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomCard(AppLocalizations l10n) {
    final privateRoom = widget.privateRoom;
    final secondaryStyle = TextStyle(
      fontSize: 14.0,
      color: AppColors.ink.withValues(alpha: 0.75),
    );
    final caption = switch (widget.languageSource) {
      RoomLanguageSource.explicit => null,
      RoomLanguageSource.detected => l10n.languageRoomAutoDetected,
      RoomLanguageSource.fallback => l10n.languageRoomAutoFallback,
    };
    const chevron = Icon(Icons.chevron_right);

    return CreamCard(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    l10n.roomSectionTitle,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(l10n.roomSectionDescription, style: secondaryStyle),
              ],
            ),
          ),
          const SizedBox(height: 12.0),
          if (privateRoom != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: AppColors.sage,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Row(
                children: <Widget>[
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.lock,
                      size: 20.0,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      l10n.privateRoomActiveNotice(privateRoom.name),
                      style: const TextStyle(
                        fontSize: 14.0,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12.0),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Semantics(
              header: true,
              child: Text(
                l10n.languageRoomHeading,
                style: const TextStyle(
                  fontSize: 14.0,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4.0),
          for (final language in kStoryLanguages) _buildLanguageRow(language),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 0.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.smartphone,
                      size: 16.0,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: Text(
                      caption,
                      style: secondaryStyle.copyWith(fontSize: 13.0),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 24.0, indent: 16.0, endIndent: 16.0),
          ListTileTheme.merge(
            iconColor: AppColors.ink.withValues(alpha: 0.6),
            child: privateRoom == null
                ? ListTile(
                    minTileHeight: 56.0,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16.0),
                    leading: const Icon(
                      Icons.lock_outline,
                      size: 24.0,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      l10n.privateRoomMenuItem,
                      style: const TextStyle(
                        fontSize: 16.0,
                        color: AppColors.ink,
                      ),
                    ),
                    subtitle: Text(
                      l10n.privateRoomRowSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: secondaryStyle,
                    ),
                    trailing: chevron,
                    onTap: _openPrivateRoomPicker,
                  )
                : ListTile(
                    minTileHeight: 56.0,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16.0),
                    leading: const Icon(
                      Icons.lock,
                      size: 24.0,
                      color: AppColors.primaryDark,
                    ),
                    title: Text(
                      privateRoom.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    subtitle:
                        Text(l10n.privateRoomMenuItem, style: secondaryStyle),
                    trailing: chevron,
                    onTap: _openPrivateRoomPicker,
                  ),
          ),
          if (privateRoom != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0.0, 8.0, 0.0),
                child: TextButton.icon(
                  onPressed: () => _leavePrivateRoom(privateRoom),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                  ),
                  icon: const Icon(Icons.logout),
                  label: Text(l10n.leavePrivateRoomMenuItem),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              // Keep the content vertically centred when it fits, and let it
              // scroll when it doesn't (e.g. with the keyboard open).
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48.0).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Center(
                        child: CircleAvatar(
                          radius: 40.0,
                          backgroundColor: AppColors.primary,
                          child: Icon(
                            Icons.person,
                            size: 40.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      Text(
                        _email ?? '',
                        style: const TextStyle(
                          fontSize: 18.0,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_email != null) ...[
                        const SizedBox(height: 24.0),
                        _buildNicknameCard(l10n),
                      ],
                      const SizedBox(height: 24.0),
                      _buildRoomCard(l10n),
                      const SizedBox(height: 32.0),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await AuthService.signOut();
                            // Mature stories lock again for the next user,
                            // and their age signals are asked afresh.
                            CompleteStoriesScreen.clearSessionState();
                            AgeGate.clearSessionCache();
                            if (!context.mounted) return;
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              WelcomeScreen.id,
                              (route) => false,
                            );
                          },
                          icon: const Icon(Icons.logout),
                          label: Text(l10n.logoutButton),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      if (_email != null) ...[
                        const SizedBox(height: 16.0),
                        Center(
                          child: TextButton(
                            onPressed: _isDeleting ? null : _deleteAccount,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: _isDeleting
                                ? const SizedBox(
                                    width: 18.0,
                                    height: 18.0,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                    ),
                                  )
                                : Text(l10n.deleteAccountButton),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The user's answer to [_DeleteAccountDialog]: [password] is set for
/// email/password users and null for Google users.
class _DeleteConfirmation {
  const _DeleteConfirmation(this.password);

  final String? password;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.usesPassword});

  final bool usesPassword;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (widget.usesPassword && _passwordController.text.isEmpty) return;
    Navigator.pop(
      context,
      _DeleteConfirmation(
        widget.usesPassword ? _passwordController.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.deleteAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.deleteAccountMessage),
          const SizedBox(height: 16.0),
          if (widget.usesPassword)
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(hintText: l10n.passwordHint),
            )
          else
            Text(l10n.deleteAccountGoogleHint),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          onPressed: _confirm,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(l10n.deleteAccountConfirmButton),
        ),
      ],
    );
  }
}
