import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/button.dart';
import 'package:cadavre_exquisite/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/services/private_room_service.dart';

class JoinPrivateRoomScreen extends StatefulWidget {
  const JoinPrivateRoomScreen({super.key});

  @override
  State<JoinPrivateRoomScreen> createState() => _JoinPrivateRoomScreenState();
}

class _JoinPrivateRoomScreenState extends State<JoinPrivateRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _roomService = PrivateRoomService();
  String _name = '';
  String _password = '';
  bool _isSubmitting = false;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final room = await _roomService.joinRoom(name: _name, password: _password);
      if (!mounted) return;
      Navigator.pop(context, room);
    } on PrivateRoomServiceException {
      // Room-not-found and wrong-password both show the same message, so a
      // join attempt can't be used to probe whether a room name is taken.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.errorRoomJoinFailed),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.genericError), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.joinRoomTitle),
        backgroundColor: Colors.lightBlueAccent,
      ),
      body: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextFormField(
                    onChanged: (value) => _name = value,
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? l10n.roomNameRequired
                        : null,
                    decoration:
                        kTextFieldDecoration.copyWith(hintText: l10n.roomNameHint),
                  ),
                  const SizedBox(height: 8.0),
                  TextFormField(
                    obscureText: true,
                    onChanged: (value) => _password = value,
                    validator: (value) => (value == null || value.length < 4)
                        ? l10n.roomPasswordTooShort
                        : null,
                    decoration: kTextFieldDecoration.copyWith(
                        hintText: l10n.roomPasswordHint),
                  ),
                  const SizedBox(height: 24.0),
                  ChatButton(
                    text: l10n.joinRoomButton,
                    color: Colors.blueAccent,
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
          if (_isSubmitting) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
