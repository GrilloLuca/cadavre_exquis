import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cadavre_exquisite/domain/models/nickname.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/account/view_models/account_view_model.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';

/// Localized message for a nickname validation/service error [code].
String _nicknameErrorMessage(
  AppLocalizations l10n,
  UserProfileErrorCode code,
) {
  switch (code) {
    case UserProfileErrorCode.nicknameTooShort:
      return l10n.errorNicknameTooShort(Nickname.minLength);
    case UserProfileErrorCode.nicknameTooLong:
      return l10n.errorNicknameTooLong(Nickname.maxLength);
    case UserProfileErrorCode.nicknameInvalidCharacters:
      return l10n.errorNicknameInvalidCharacters;
    case UserProfileErrorCode.nicknameAlreadySet:
      return l10n.errorNicknameAlreadySet;
  }
}

/// The nickname section of the profile: the field, a preview of the name
/// other players will see, and saving (once, after a confirmation). Owns
/// the field's controller and form; rebuilt by its parent when [viewModel]
/// or its commands change.
class NicknameCard extends StatefulWidget {
  const NicknameCard({super.key, required this.viewModel});

  final AccountViewModel viewModel;

  @override
  State<NicknameCard> createState() => _NicknameCardState();
}

class _NicknameCardState extends State<NicknameCard> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();

  /// The normalized nickname being saved, put in the field once stored.
  String? _saving;

  AccountViewModel get _viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel.loadNickname.addListener(_onLoadChanged);
    _viewModel.saveNickname.addListener(_onSaveChanged);
    // The load starts with the ViewModel; it may already be done.
    _onLoadChanged();
  }

  @override
  void dispose() {
    _viewModel.loadNickname.removeListener(_onLoadChanged);
    _viewModel.saveNickname.removeListener(_onSaveChanged);
    _nicknameController.dispose();
    super.dispose();
  }

  /// Prefills the field with the stored nickname once loaded.
  void _onLoadChanged() {
    final load = _viewModel.loadNickname;
    if (load.completed) _nicknameController.text = load.value ?? '';
  }

  void _onSaveChanged() {
    final save = _viewModel.saveNickname;
    if (save.running) return;
    final l10n = AppLocalizations.of(context)!;
    final error = save.error;
    if (error != null) {
      save.clearResult();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is UserProfileException
              ? _nicknameErrorMessage(l10n, error.code)
              : l10n.genericError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (save.completed) {
      save.clearResult();
      _nicknameController.text = _saving ?? _nicknameController.text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.nicknameSaved)),
      );
    }
  }

  Future<void> _saveNickname() async {
    if (!_viewModel.canEditNickname) return;
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final normalized = Nickname.normalize(_nicknameController.text);
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

    _saving = normalized;
    _viewModel.saveNickname.execute(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isBusy = _viewModel.isNicknameBusy;
    final canEdit = _viewModel.canEditNickname;
    final hasNickname = _viewModel.hasNickname;

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
              maxLength: Nickname.maxLength,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _saveNickname(),
              validator: (value) {
                final code = Nickname.validate(value ?? '');
                return code == null ? null : _nicknameErrorMessage(l10n, code);
              },
              decoration: InputDecoration(
                labelText: l10n.nicknameLabel,
                helperText: hasNickname
                    ? l10n.nicknameLockedNote
                    : '${l10n.nicknameHelper(
                        Nickname.minLength,
                        Nickname.maxLength,
                      )}\n${l10n.nicknameOnceNote}',
                helperMaxLines: 2,
                errorMaxLines: 2,
                suffixIcon: _viewModel.loadNickname.running
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
                final name =
                    _viewModel.publicName(value.text) ?? l10n.anonymousAuthor;
                return Text(
                  l10n.nicknamePublicPreview(name),
                  style: TextStyle(
                    fontSize: 14.0,
                    color: AppColors.ink.withValues(alpha: 0.75),
                  ),
                );
              },
            ),
            if (_viewModel.nicknameLoadFailed) ...[
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
                    onPressed: _viewModel.loadNickname.execute,
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
            ],
            if (!hasNickname) ...[
              const SizedBox(height: 16.0),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: isBusy ? null : _saveNickname,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.cream,
                  ),
                  child: _viewModel.saveNickname.running
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
}
