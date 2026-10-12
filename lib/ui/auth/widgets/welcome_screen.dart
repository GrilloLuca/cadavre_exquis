import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/button.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/home_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/login_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/welcome_view_model.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// First screen for signed-out users: Google sign-in (and email login in
/// debug builds). It is also built directly by `AuthWrapper`, whose build
/// runs on every auth change, so it creates its own [WelcomeViewModel]
/// instead of receiving one.
class WelcomeScreen extends StatefulWidget {
  static String id = "welcome_screen";

  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late Animation animation;
  late final WelcomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        WelcomeViewModel(authRepository: context.read<AuthRepository>());
    _viewModel.signInWithGoogle.addListener(_onSignInChanged);
    controller = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );

    animation = CurvedAnimation(parent: controller, curve: Curves.decelerate);
    controller.forward();
    controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _viewModel.signInWithGoogle.removeListener(_onSignInChanged);
    _viewModel.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Background(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Row(
              //   children: <Widget>[
              //     Hero(
              //       tag: "logo",
              //       child: SizedBox(
              //         height: animation.value * 100,
              //         child: Image.asset('images/logo.png'),
              //       ),
              //     ),
              //     Expanded(
              //       child: Text(
              //         'Cadavre Exquisite',
              //         style: TextStyle(
              //           color: AppColors.ink,
              //           fontSize: 36.0,
              //           fontWeight: FontWeight.w900,
              //         ),
              //       ),
              //     ),
              //   ],
              // ),
              SizedBox(
                height: 48.0,
              ),
              // Email/password login is only offered in debug builds.
              if (kDebugMode)
                ChatButton(
                  text: AppLocalizations.of(context)!.loginButton,
                  color: AppColors.primary,
                  onPressed: () {
                    Navigator.pushNamed(context, LoginScreen.id);
                  },
                ),
              // ChatButton(
              //   text: AppLocalizations.of(context)!.registerButton,
              //   color: AppColors.primaryDark,
              //   onPressed: () {
              //     Navigator.pushNamed(context, RegistrationScreen.id);
              //   },
              // ),
              ListenableBuilder(
                listenable: _viewModel.signInWithGoogle,
                builder: (context, _) => _viewModel.signInWithGoogle.running
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : ChatButton(
                        text: AppLocalizations.of(context)!.googleSignInButton,
                        color: Colors.white,
                        icon: SvgPicture.asset(
                          'images/google_g.svg',
                          height: 20.0,
                          width: 20.0,
                        ),
                        onPressed: _viewModel.signInWithGoogle.execute,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSignInChanged() {
    final signIn = _viewModel.signInWithGoogle;
    if (signIn.running) return;
    if (signIn.error != null) {
      signIn.clearResult();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginFailed),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // False: the user dismissed the account picker; stay here.
    if (signIn.completed && signIn.value == true) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        HomeScreen.id,
        (route) => false,
      );
    }
  }
}
