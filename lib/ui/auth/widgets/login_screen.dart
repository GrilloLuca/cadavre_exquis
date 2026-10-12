import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/button.dart';
import 'package:cadavre_exquisite/ui/core/themes/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/home_screen.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/login_view_model.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/domain/models/auth_error.dart';

/// Email/password sign-in, offered in debug builds only. Owns [viewModel]
/// and disposes it.
class LoginScreen extends StatefulWidget {
  static String id = "login_screen";

  const LoginScreen({super.key, required this.viewModel});

  final LoginViewModel viewModel;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String email = '';
  String password = '';

  LoginViewModel get _viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel.login.addListener(_onLoginChanged);
  }

  @override
  void dispose() {
    _viewModel.login.removeListener(_onLoginChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel.login,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showSpinner = _viewModel.login.running;
    return Scaffold(
      body: Background(
        child: Stack(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0),
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
                  TextField(
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (value) {
                      email = value;
                    },
                    decoration: kTextFieldDecoration.copyWith(
                        filled: true,
                        fillColor: AppColors.cream,
                        hintText: l10n.emailHint),
                  ),
                  SizedBox(
                    height: 8.0,
                  ),
                  TextField(
                    obscureText: true,
                    onChanged: (value) {
                      password = value;
                    },
                    decoration: kTextFieldDecoration.copyWith(
                        filled: true,
                        fillColor: AppColors.cream,
                        hintText: l10n.passwordHint),
                  ),
                  SizedBox(
                    height: 24.0,
                  ),
                  ChatButton(
                    text: l10n.loginButton,
                    color: AppColors.primary,
                    onPressed: showSpinner
                        ? null
                        : () => _viewModel.login
                            .execute((email: email, password: password)),
                  ),
                ],
              ),
            ),
            if (showSpinner) Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  void _onLoginChanged() {
    final login = _viewModel.login;
    if (login.running) return;
    final l10n = AppLocalizations.of(context)!;
    final error = login.error;
    if (error != null) {
      login.clearResult();
      final message = error is AuthException
          ? (error.code == AuthErrorCode.invalidCredentials
              ? l10n.loginInvalidCredentials
              : (error.message ?? l10n.loginFailed))
          : l10n.loginFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (login.completed) {
      // This disposes the screen, so nothing may touch its state or
      // context afterwards.
      Navigator.pushNamedAndRemoveUntil(
        context,
        HomeScreen.id,
        (route) => false,
      );
    }
  }
}
