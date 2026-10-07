import 'package:cadavre_exquisite/app_colors.dart';
import 'package:cadavre_exquisite/cream_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/author_name.dart';
import 'package:cadavre_exquisite/screens/welcome_screen.dart';
import 'package:cadavre_exquisite/services/auth_service.dart';
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
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.profileService, this.email});

  /// Service used to read/write the nickname. Defaults to a
  /// [UserProfileService] backed by the default Firestore instance.
  final UserProfileService? profileService;

  /// Email of the signed-in user. Defaults to the current Firebase user's
  /// email; when provided, [FirebaseAuth] is never accessed while building.
  final String? email;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  late final UserProfileService _profileService;

  String? _email;
  bool _isLoadingNickname = false;
  bool _isSaving = false;

  /// True when the last prefill attempt failed. While set, editing and
  /// saving are disabled so an empty field can't wipe the stored nickname.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? UserProfileService();
    _email = widget.email ?? FirebaseAuth.instance.currentUser?.email;
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
    if (email == null || _isSaving || _isLoadingNickname || _loadFailed) {
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final normalized =
        UserProfileService.normalizeNickname(_nicknameController.text);

    setState(() => _isSaving = true);
    try {
      await _profileService.setNickname(email: email, nickname: normalized);
      if (!mounted) return;
      _nicknameController.text = normalized;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            normalized.isEmpty ? l10n.nicknameRemoved : l10n.nicknameSaved,
          ),
        ),
      );
    } on UserProfileServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_nicknameErrorMessage(l10n, e.code)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.genericError), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildNicknameCard(AppLocalizations l10n) {
    final isBusy = _isLoadingNickname || _isSaving || _loadFailed;

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
              enabled: !isBusy,
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
                helperText: l10n.nicknameHelper(
                  UserProfileService.minNicknameLength,
                  UserProfileService.maxNicknameLength,
                ),
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
        ),
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
                      const SizedBox(height: 32.0),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await AuthService.signOut();
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
