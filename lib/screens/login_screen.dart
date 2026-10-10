import 'package:cadavre_exquisite/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cadavre_exquisite/background.dart';
import 'package:cadavre_exquisite/button.dart';
import 'package:cadavre_exquisite/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/home_screen.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  static String id = "login_screen";

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;
  String email = '';
  String password = '';
  bool showSpinner = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                    onPressed: showSpinner ? null : _signIn,
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

  Future<void> _signIn() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      showSpinner = true;
    });
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // The navigation below disposes this screen, so nothing may touch its
      // state or context afterwards.
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        HomeScreen.id,
        (route) => false,
      );
      return;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      const wrongCredentialsCodes = {
        'invalid-credential',
        'wrong-password',
        'user-not-found',
      };
      final message = wrongCredentialsCodes.contains(e.code)
          ? l10n.loginInvalidCredentials
          : (e.message ?? l10n.loginFailed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.loginFailed),
          backgroundColor: Colors.red,
        ),
      );
    }
    setState(() {
      showSpinner = false;
    });
  }
}
