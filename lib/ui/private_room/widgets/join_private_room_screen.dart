import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/ui/core/ui/button.dart';
import 'package:cadavre_exquisite/ui/core/themes/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/ui/private_room/view_models/join_private_room_view_model.dart';

/// Form to join an existing private room. Pops with the joined
/// [PrivateRoom]. Owns [viewModel] and disposes it.
class JoinPrivateRoomScreen extends StatefulWidget {
  const JoinPrivateRoomScreen({super.key, required this.viewModel});

  final JoinPrivateRoomViewModel viewModel;

  @override
  State<JoinPrivateRoomScreen> createState() => _JoinPrivateRoomScreenState();
}

class _JoinPrivateRoomScreenState extends State<JoinPrivateRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _password = '';

  JoinPrivateRoomViewModel get _viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel.join.addListener(_onJoinChanged);
  }

  @override
  void dispose() {
    _viewModel.join.removeListener(_onJoinChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _viewModel.join.execute((name: _name, password: _password));
  }

  void _onJoinChanged() {
    final join = _viewModel.join;
    if (join.running) return;
    final l10n = AppLocalizations.of(context)!;
    final error = join.error;
    if (error != null) {
      join.clearResult();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Room-not-found and wrong-password both show the same message,
          // so a join attempt can't be used to probe whether a room name is
          // taken.
          content: Text(error is PrivateRoomException
              ? l10n.errorRoomJoinFailed
              : l10n.genericError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (join.completed) Navigator.pop(context, join.value);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel.join,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSubmitting = _viewModel.join.running;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.joinRoomTitle),
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
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? l10n.roomNameRequired
                            : null,
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
                  const SizedBox(height: 24.0),
                  ChatButton(
                    text: l10n.joinRoomButton,
                    color: AppColors.primaryDark,
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
