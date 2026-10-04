import 'package:cadavre_exquisite/button.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/login_screen.dart';
import 'package:cadavre_exquisite/screens/home_screen.dart';
import 'package:cadavre_exquisite/screens/registration_screen.dart';
import 'package:cadavre_exquisite/services/auth_service.dart';
import 'package:flutter/material.dart';

class WelcomeScreen extends StatefulWidget {
  static String id = "welcome_screen";

  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {

  late AnimationController controller;
  late Animation animation;
  bool showSpinner = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );
    
    animation = CurvedAnimation(parent: controller, curve: Curves.decelerate);
    controller.forward();
    controller.addListener(() {
      setState(() {

      });
      print(animation.value);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Hero(
                  tag: "logo",
                  child: Container(
                    child: Image.asset('images/logo.png'),
                    height: animation.value * 100,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Cadavre Exquisite',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 36.0,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 48.0,
            ),
            ChatButton(
              text: AppLocalizations.of(context)!.loginButton,
              color: Colors.lightBlueAccent,
              onPressed: () {
                Navigator.pushNamed(context, LoginScreen.id);
              },
            ),
            ChatButton(
              text: AppLocalizations.of(context)!.registerButton,
              color: Colors.blueAccent,
              onPressed: () {
                Navigator.pushNamed(context, RegistrationScreen.id);
              },
            ),
            showSpinner
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ChatButton(
                    text: AppLocalizations.of(context)!.googleSignInButton,
                    color: Colors.white,
                    onPressed: _signInWithGoogle,
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      showSpinner = true;
    });
    try {
      final result = await AuthService.signInWithGoogle();
      if (!mounted) return;
      if (result != null) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          HomeScreen.id,
          (route) => false,
        );
        return;
      }
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
