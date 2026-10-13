import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/button.dart';
import 'package:cadavre_exquisite/ui/core/themes/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/home/widgets/home_screen.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/registration_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/domain/models/auth_error.dart';

class RegistrationScreen extends StatefulWidget {
  static String id = "registration_screen";

  const RegistrationScreen({super.key});

  /// Owned by the screen, which disposes it.

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String password = '';

  late final RegistrationViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        RegistrationViewModel(authRepository: context.read<AuthRepository>());
    _viewModel.register.addListener(_onRegisterChanged);
  }

  @override
  void dispose() {
    _viewModel.register.removeListener(_onRegisterChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _register() {
    if (!_formKey.currentState!.validate()) return;
    _viewModel.register.execute((email: email, password: password));
  }

  void _onRegisterChanged() {
    final register = _viewModel.register;
    if (register.running) return;
    final l10n = AppLocalizations.of(context)!;
    final error = register.error;
    if (error != null) {
      register.clearResult();
      final message = error is AuthException
          ? (error.code == AuthErrorCode.weakPassword
              ? l10n.passwordTooShort
              : (error.message ?? l10n.registrationFailed))
          : l10n.registrationFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (register.completed) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        HomeScreen.id,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel.register,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showSpinner = _viewModel.register.running;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Hero(
                    tag: "logo",
                    child: SizedBox(
                      height: 200.0,
                      child: Image.asset('images/logo.png'),
                    ),
                  ),
                  SizedBox(
                    height: 48.0,
                  ),
                  TextFormField(
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (value) {
                      email = value;
                    },
                    decoration:
                        kTextFieldDecoration.copyWith(hintText: l10n.emailHint),
                  ),
                  SizedBox(
                    height: 8.0,
                  ),
                  TextFormField(
                    obscureText: true,
                    onChanged: (value) {
                      password = value;
                    },
                    validator: (value) => (value == null || value.length < 6)
                        ? l10n.passwordTooShort
                        : null,
                    decoration: kTextFieldDecoration.copyWith(
                      hintText: l10n.passwordHint,
                    ),
                  ),
                  SizedBox(
                    height: 24.0,
                  ),
                  ChatButton(
                    text: l10n.registerButton,
                    color: AppColors.primaryDark,
                    onPressed: showSpinner ? null : _register,
                  ),
                ],
              ),
            ),
          ),
          if (showSpinner) Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
