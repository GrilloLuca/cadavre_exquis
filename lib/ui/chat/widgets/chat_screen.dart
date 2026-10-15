import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/view_models/chat_view_model.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_composer.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_turn_card.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/notification_offer_dialog.dart';
import 'package:cadavre_exquisite/ui/core/position_label.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/message_bubble.dart';

/// Screen used to write the next part of [story]: a turn card (which part,
/// what to do, the story's keywords) above a composer docked over the
/// keyboard, which starts from the previous part's last five words.
///
/// Creates its [ChatViewModel] once, in `initState`: a route's builder can
/// run again (whenever the Navigator's dependencies change), so the
/// ViewModel must not be created there. Disposing the screen disposes the
/// ViewModel, which gives the story's lock back if the part wasn't
/// submitted.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.story});

  final Story story;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageTextController = TextEditingController();

  late final ChatViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ChatViewModel(
      story: widget.story,
      storyRepository: context.read<StoryRepository>(),
      authRepository: context.read<AuthRepository>(),
      notificationRepository: context.read<NotificationRepository>(),
    );
    _viewModel.lock.addListener(_onLockChanged);
    _viewModel.submit.addListener(_onSubmitChanged);
  }

  @override
  void dispose() {
    _viewModel.lock.removeListener(_onLockChanged);
    _viewModel.submit.removeListener(_onSubmitChanged);
    _viewModel.dispose();
    _messageTextController.dispose();
    super.dispose();
  }

  // The field isn't focused once the lock is held: the player reads the
  // turn card first, and an auto-opened keyboard would hide it.
  void _onLockChanged() {
    final lock = _viewModel.lock;
    if (lock.running) return;
    final error = lock.error;
    if (error != null) {
      final message = _errorMessage(context, error);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _onSubmitChanged() async {
    final submit = _viewModel.submit;
    if (submit.running) return;
    final error = submit.error;
    if (error != null) {
      submit.clearResult();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(context, error))),
      );
      return;
    }
    if (!submit.completed || submit.value != true) return;
    if (_viewModel.offerNotifications) {
      submit.clearResult();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => const NotificationOfferDialog(),
      );
      if (!mounted) return;
      await _viewModel.answerNotificationOffer.execute(accepted ?? false);
      if (!mounted) return;
    }
    final l10n = AppLocalizations.of(context)!;
    final completed = _viewModel.story.currentPosition == kStoryPositions.last;
    // The messenger outlives this screen: the snack bar shows on the one
    // underneath.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content:
          Text(completed ? l10n.chatCompletedSnackbar : l10n.chatSentSnackbar),
    ));
  }

  /// Leaving with unsent text asks first: it would be lost.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop || _viewModel.submit.running) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.chatLeaveTitle),
          content: Text(l10n.chatLeaveBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.chatLeaveCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.chatLeaveConfirm),
            ),
          ],
        );
      },
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  String _errorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is StoryException) {
      switch (error.code) {
        case StoryErrorCode.alreadyCompleted:
          return l10n.errorStoryAlreadyCompleted;
        case StoryErrorCode.positionTaken:
          return l10n.errorStoryPositionTaken;
        case StoryErrorCode.lockedByOther:
          return l10n.errorStoryLockedByOther;
        case StoryErrorCode.consecutiveTurnNotAllowed:
          return l10n.errorConsecutiveTurnNotAllowed;
      }
    }
    return l10n.genericError;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([_viewModel, _viewModel.lock, _viewModel.submit]),
      builder: (context, _) {
        final sending = _viewModel.submit.running;
        // Back and close are blocked while sending, so the unlock can't
        // race the submit, and ask first while there's unsent text.
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: _messageTextController,
          builder: (context, value, child) => PopScope<Object?>(
            canPop: !sending && value.text.trim().isEmpty,
            onPopInvokedWithResult: _onPopInvoked,
            child: child!,
          ),
          child: _buildScreen(context),
        );
      },
    );
  }

  Widget _buildScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final story = _viewModel.story;
    final position = positionLabel(context, story.currentPosition);
    final sending = _viewModel.submit.running;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          // maybePop goes through the PopScope above.
          onPressed: sending ? null : () => Navigator.maybePop(context),
        ),
        title: Text(position),
        backgroundColor: AppColors.primary,
      ),
      body: Background(
        opacity: 0.2,
        child: SafeArea(
          // The composer handles the bottom inset itself so its cream
          // background reaches the bottom edge of the screen.
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, viewport) => SingleChildScrollView(
                      // With the keyboard open, anchor to the bottom so the
                      // last words stay visible right above the composer.
                      reverse: keyboardOpen,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(_bodyPadding),
                      // At least as tall as the viewport, so the card sits at
                      // the top and the last words at the bottom, next to the
                      // composer.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (viewport.maxHeight - 2 * _bodyPadding)
                              .clamp(0.0, double.infinity),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ChatTurnCard(
                              position: story.currentPosition,
                              keywords: story.parts.isEmpty
                                  ? const []
                                  : story.keywords,
                            ),
                            if (story.parts.isNotEmpty)
                              // Read as one item: label, then the words.
                              MergeSemantics(
                                child: MessageBubble(
                                  sender: l10n.chatContinueFromLabel,
                                  text: l10n.chatLastWords(
                                      _capLastWords(story.lastFiveWords)),
                                  isMe: false,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // At large text scales or in landscape the composer must
                // never cover the whole body.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.6,
                  ),
                  child: ChatComposer(
                    controller: _messageTextController,
                    positionLabel: position,
                    reserving: _viewModel.lock.running,
                    sending: sending,
                    canWrite: _viewModel.canWrite,
                    keyboardOpen: keyboardOpen,
                    onSend: () =>
                        _viewModel.submit.execute(_messageTextController.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Padding around the turn card and the last words.
const _bodyPadding = 16.0;

/// Longest lead-in shown: a part without spaces is a single "word".
const _maxLastWordsLength = 120;

/// [words] cut to its last [_maxLastWordsLength] characters (graphemes).
String _capLastWords(String words) {
  final characters = words.characters;
  return characters.length <= _maxLastWordsLength
      ? words
      : characters.takeLast(_maxLastWordsLength).toString();
}
