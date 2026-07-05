import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/constants.dart';
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
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
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
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final position = positionLabel(story.currentPosition);

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
                      ? const Text(
                          'Sei il primo: scrivi tu l\'introduzione della storia!',
                          style: TextStyle(color: Colors.black54, fontSize: 15.0),
                        )
                      : MessageBubble(
                          sender: 'Finora è stato scritto...',
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
                            hintText: 'Scrivi qui: ${position.toLowerCase()}...',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: (_isSending || !_lockAcquired) ? null : _submit,
                        child: Text('Invia', style: kSendButtonTextStyle),
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
