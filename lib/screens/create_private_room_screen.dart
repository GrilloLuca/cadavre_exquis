import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/button.dart';
import 'package:cadavre_exquisite/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/services/private_room_service.dart';

class CreatePrivateRoomScreen extends StatefulWidget {
  const CreatePrivateRoomScreen({super.key});

  @override
  State<CreatePrivateRoomScreen> createState() =>
      _CreatePrivateRoomScreenState();
}

class _CreatePrivateRoomScreenState extends State<CreatePrivateRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _roomService = PrivateRoomService();
  String _name = '';
  String _password = '';
  bool _isSubmitting = false;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;

    setState(() => _isSubmitting = true);
    try {
      final room = await _roomService.createRoom(
        name: _name,
        password: _password,
        createdBy: email,
      );
      if (!mounted) return;
      Navigator.pop(context, room);
    } on PrivateRoomServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == PrivateRoomServiceErrorCode.nameTaken
                ? l10n.errorRoomNameTaken
                : l10n.genericError,
          ),
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
        title: Text(l10n.createRoomTitle),
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
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return l10n.roomNameRequired;
                      if (trimmed.contains('/') || trimmed.length > 40) {
                        return l10n.roomNameInvalid;
                      }
                      return null;
                    },
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
                  const SizedBox(height: 8.0),
                  TextFormField(
                    obscureText: true,
                    validator: (value) => value != _password
                        ? l10n.roomPasswordMismatch
                        : null,
                    decoration: kTextFieldDecoration.copyWith(
                        hintText: l10n.roomPasswordConfirmHint),
                  ),
                  const SizedBox(height: 24.0),
                  ChatButton(
                    text: l10n.createRoomButton,
                    color: Colors.lightBlueAccent,
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
