import 'package:cadavre_exquisite/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cadavre_exquisite/button.dart';
import 'package:cadavre_exquisite/constants.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/home_screen.dart';
import 'package:flutter/material.dart';

class RegistrationScreen extends StatefulWidget {
  static String id = "registration_screen";
  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _auth = FirebaseAuth.instance;
  final _formKey = GlobalKey<FormState>();
  late String email;
  late String password;
  bool showSpinner = false;

  Future<void> _register() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      showSpinner = true;
    });
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        HomeScreen.id,
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = e.code == 'weak-password'
          ? l10n.passwordTooShort
          : (e.message ?? l10n.registrationFailed);
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
          content: Text(l10n.registrationFailed),
          backgroundColor: Colors.red,
        ),
      );
    }
    if (mounted) {
      setState(() {
        showSpinner = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                    decoration: kTextFieldDecoration.copyWith(
                      hintText: l10n.emailHint
                    ),
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
