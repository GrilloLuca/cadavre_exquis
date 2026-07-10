import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/message_bubble.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/story_service.dart';

/// Chat screen used to write the next part of a single incomplete story.
class ChatScreen extends StatefulWidget {
  final Story story;

  const ChatScreen({super.key, required this.story});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _storyService = StoryService();
  final _messageTextController = TextEditingController();
  String _messageText = '';
  bool _isSending = false;
  bool _isLocking = true;
  bool _lockAcquired = false;

  @override
  void initState() {
    super.initState();
    _acquireLock();
  }

  Future<void> _acquireLock() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    try {
      await _storyService.lockStory(storyId: widget.story.id, authorEmail: email);
      if (!mounted) return;
      setState(() {
        _lockAcquired = true;
        _isLocking = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = _errorMessage(context, e);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  void dispose() {
    _messageTextController.dispose();
    if (_lockAcquired) {
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email != null) {
        _storyService.unlockStory(storyId: widget.story.id, authorEmail: email);
      }
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (_messageText.trim().isEmpty || email == null || !_lockAcquired) return;

    setState(() => _isSending = true);
    try {
      await _storyService.submitPart(
        storyId: widget.story.id,
        expectedPosition: widget.story.currentPosition,
        text: _messageText.trim(),
        authorEmail: email,
      );
      _lockAcquired = false;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(context, e))),
      );
    }
  }

  String _errorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is StoryServiceException) {
      switch (error.code) {
        case StoryServiceErrorCode.alreadyCompleted:
          return l10n.errorStoryAlreadyCompleted;
        case StoryServiceErrorCode.positionTaken:
          return l10n.errorStoryPositionTaken;
        case StoryServiceErrorCode.lockedByOther:
          return l10n.errorStoryLockedByOther;
        case StoryServiceErrorCode.consecutiveTurnNotAllowed:
          return l10n.errorConsecutiveTurnNotAllowed;
      }
    }
    return l10n.genericError;
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final l10n = AppLocalizations.of(context)!;
    final position = positionLabel(context, story.currentPosition);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(position),
        backgroundColor: Colors.lightBlueAccent,
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: story.parts.isEmpty
                      ? Text(
                          l10n.chatFirstWriterHint,
                          style: const TextStyle(color: Colors.black54, fontSize: 15.0),
                        )
                      : MessageBubble(
                          sender: l10n.storySoFarLabel,
                          text: '"...${story.lastFiveWords}"',
                          isMe: false,
                        ),
                ),
                Container(
                  decoration: kMessageContainerDecoration,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _messageTextController,
                          enabled: !_isSending && _lockAcquired,
                          minLines: 1,
                          maxLines: 5,
                          onChanged: (value) => _messageText = value,
                          decoration: kMessageTextFieldDecoration.copyWith(
                            hintText: l10n.chatMessageHint(position.toLowerCase()),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: (_isSending || !_lockAcquired) ? null : _submit,
                        child: Text(l10n.sendButton, style: kSendButtonTextStyle),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isLocking) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
