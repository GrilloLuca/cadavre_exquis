import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/ui/core/ui/button.dart';
import 'package:cadavre_exquisite/ui/core/themes/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/ui/private_room/view_models/create_private_room_view_model.dart';

/// Form to create a new private room. Pops with the created
/// [PrivateRoom]. Owns [viewModel] and disposes it.
class CreatePrivateRoomScreen extends StatefulWidget {
  const CreatePrivateRoomScreen({super.key, required this.viewModel});

  final CreatePrivateRoomViewModel viewModel;

  @override
  State<CreatePrivateRoomScreen> createState() =>
      _CreatePrivateRoomScreenState();
}

class _CreatePrivateRoomScreenState extends State<CreatePrivateRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _password = '';

  CreatePrivateRoomViewModel get _viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel.create.addListener(_onCreateChanged);
  }

  @override
  void dispose() {
    _viewModel.create.removeListener(_onCreateChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _viewModel.create.execute((name: _name, password: _password));
  }

  void _onCreateChanged() {
    final create = _viewModel.create;
    if (create.running) return;
    final l10n = AppLocalizations.of(context)!;
    final error = create.error;
    if (error != null) {
      create.clearResult();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is PrivateRoomException &&
                    error.code == PrivateRoomErrorCode.nameTaken
                ? l10n.errorRoomNameTaken
                : l10n.genericError,
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final room = create.value;
    if (create.completed && room != null) Navigator.pop(context, room);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel.create,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSubmitting = _viewModel.create.running;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createRoomTitle),
        backgroundColor: AppColors.primary,
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
                    decoration: kTextFieldDecoration.copyWith(
                        hintText: l10n.roomNameHint),
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
                    validator: (value) =>
                        value != _password ? l10n.roomPasswordMismatch : null,
                    decoration: kTextFieldDecoration.copyWith(
                        hintText: l10n.roomPasswordConfirmHint),
                  ),
                  const SizedBox(height: 24.0),
                  ChatButton(
                    text: l10n.createRoomButton,
                    color: AppColors.primary,
                    onPressed: isSubmitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
          if (isSubmitting) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
