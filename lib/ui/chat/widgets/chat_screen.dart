import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/view_models/chat_view_model.dart';
import 'package:cadavre_exquisite/ui/core/position_label.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/themes/constants.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/message_bubble.dart';

/// Chat screen used to write the next part of [story].
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
  final _messageFocusNode = FocusNode();

  late final ChatViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ChatViewModel(
      story: widget.story,
      storyRepository: context.read<StoryRepository>(),
      authRepository: context.read<AuthRepository>(),
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
    _messageFocusNode.dispose();
    super.dispose();
  }

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
      return;
    }
    if (_viewModel.canWrite) {
      // The field is disabled until the lock is held; focus it once the
      // rebuild has enabled it so the keyboard opens straight away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _messageFocusNode.requestFocus();
      });
    }
  }

  void _onSubmitChanged() {
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
    if (submit.completed && submit.value == true) Navigator.pop(context);
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
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final story = _viewModel.story;
    final canWrite = _viewModel.canWrite;
    final l10n = AppLocalizations.of(context)!;
    final position = positionLabel(context, story.currentPosition);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(position),
        backgroundColor: AppColors.primary,
      ),
      body: Background(
        opacity: 0.2,
        child: SafeArea(
          // The input bar handles the bottom inset itself so its cream
          // background reaches the bottom edge of the screen.
          bottom: false,
          child: Stack(
            children: <Widget>[
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(10.0),
                      child: story.parts.isEmpty
                          ? Material(
                              color: AppColors.cream,
                              elevation: 5.0,
                              borderRadius: BorderRadius.circular(20.0),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0,
                                  vertical: 16.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.chatFirstWriterTitle,
                                      style: const TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 16.0,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12.0),
                                    Text(
                                      l10n.chatFirstWriterHint,
                                      style: const TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 15.0,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : MessageBubble(
                              sender: l10n.storySoFarLabel,
                              text: '"...${story.lastFiveWords}"',
                              isMe: false,
                            ),
                    ),
                  ),
                  Container(
                    decoration: kMessageContainerDecoration.copyWith(
                      color: AppColors.cream,
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _messageTextController,
                              focusNode: _messageFocusNode,
                              enabled: canWrite,
                              minLines: 1,
                              maxLines: 5,
                              decoration: kMessageTextFieldDecoration.copyWith(
                                hintText: l10n
                                    .chatMessageHint(position.toLowerCase()),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: canWrite
                                ? () => _viewModel.submit
                                    .execute(_messageTextController.text)
                                : null,
                            child: Text(l10n.sendButton,
                                style: kSendButtonTextStyle),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_viewModel.lock.running)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}
