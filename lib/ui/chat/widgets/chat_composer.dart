import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/themes/constants.dart';

/// The bottom of the writing screen, docked above the keyboard: the field,
/// how many words are still missing (below [kMinPartWords]) or the
/// character counter (near the limit only), and Send, enabled from
/// [kMinPartWords] words on.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.positionLabel,
    required this.reserving,
    required this.sending,
    required this.canWrite,
    required this.keyboardOpen,
    required this.onSend,
  });

  final TextEditingController controller;

  /// The localized name of the part being written, for the field's label.
  final String positionLabel;

  /// Whether the story's lock is being taken.
  final bool reserving;

  /// Whether the part is being sent.
  final bool sending;

  /// Whether the lock is held and nothing is being sent.
  final bool canWrite;

  /// Whether the keyboard is open. Read above the Scaffold, which removes
  /// the keyboard's inset from its body.
  final bool keyboardOpen;

  /// Sends the field's text.
  final VoidCallback onSend;

  /// The counter appears from this many characters on.
  static const counterThreshold = 4500;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.0),
      borderSide: const BorderSide(color: AppColors.primaryDark),
    );

    return Stack(
      children: [
        Container(
          decoration: kMessageContainerDecoration.copyWith(
            color: AppColors.cream,
          ),
          child: SafeArea(
            top: false,
            // Scrolls only when even the smallest composer doesn't fit its
            // height cap (large text with the keyboard open).
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: l10n.chatInputLabel(positionLabel),
                    child: TextField(
                      controller: controller,
                      enabled: canWrite || sending,
                      readOnly: sending,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      // With the keyboard open the field starts at one line
                      // so field and Send fit a small phone.
                      minLines: keyboardOpen ? 1 : 3,
                      maxLines: keyboardOpen ? 4 : 6,
                      maxLength: kMaxPartLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      buildCounter: (context,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          null,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 16.0,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: reserving
                            ? l10n.chatReservingTurn
                            : l10n.chatInputHint,
                        hintStyle: TextStyle(
                          color: AppColors.ink.withValues(alpha: 0.6),
                        ),
                        // The field is sized for its hint too, even when
                        // hidden: keep it to one line with the keyboard open.
                        hintMaxLines: keyboardOpen ? 1 : null,
                        contentPadding: const EdgeInsets.all(12.0),
                        border: border,
                        enabledBorder: border,
                        focusedBorder: border.copyWith(
                          borderSide: const BorderSide(
                            color: AppColors.primaryDark,
                            width: 2.0,
                          ),
                        ),
                        disabledBorder: border.copyWith(
                          borderSide: BorderSide(
                            color: AppColors.ink.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final words = wordCount(value.text);
                      return _Footer(
                        length: value.text.characters.length,
                        missingWords: canWrite && words < kMinPartWords
                            ? kMinPartWords - words
                            : 0,
                        sending: sending,
                        onSend:
                            canWrite && words >= kMinPartWords ? onSend : null,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        if (reserving)
          const Positioned(
            top: 0.0,
            left: 0.0,
            right: 0.0,
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                minHeight: 2.0,
                color: AppColors.primary,
                backgroundColor: AppColors.sage,
              ),
            ),
          ),
      ],
    );
  }
}

/// How many words are still missing, or else the counter (from
/// [ChatComposer.counterThreshold] characters on), and Send, disabled when
/// [onSend] is null.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.length,
    required this.missingWords,
    required this.sending,
    required this.onSend,
  });

  final int length;

  /// Words to add before Send is enabled; 0 hides the hint.
  final int missingWords;
  final bool sending;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final atLimit = length >= kMaxPartLength;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48.0),
      child: Row(
        children: [
          Expanded(
            child: missingWords > 0
                ? Text(
                    l10n.chatWordsMissing(missingWords),
                    style: TextStyle(
                      color: AppColors.ink.withValues(alpha: 0.75),
                      fontSize: 13.0,
                    ),
                  )
                : length < ChatComposer.counterThreshold
                    ? const SizedBox.shrink()
                    : Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.chatCharacterCount(length, kMaxPartLength),
                          style: TextStyle(
                            color: atLimit
                                ? AppColors.primaryDark
                                : AppColors.ink.withValues(alpha: 0.75),
                            fontSize: 13.0,
                            fontWeight: atLimit ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
          ),
          FilledButton.icon(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 18.0,
                    height: 18.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: AppColors.primaryDark,
                    ),
                  )
                : const Icon(Icons.send, size: 18.0),
            label: Text(sending ? l10n.chatSending : l10n.sendButton),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.sage,
              disabledForegroundColor: AppColors.ink.withValues(alpha: 0.75),
              minimumSize: const Size(0.0, 48.0),
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
