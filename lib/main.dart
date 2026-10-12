import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/config/dependencies.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/services/google_sign_in_service.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/login_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/registration_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/welcome_screen.dart';
import 'package:cadavre_exquisite/ui/home/widgets/home_screen.dart';
import 'package:cadavre_exquisite/ui/core/themes/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final googleSignIn = GoogleSignInService();
  await googleSignIn.initialize();
  runApp(MultiProvider(
    providers: providers(googleSignIn: googleSignIn),
    child: const CadavreExquisiteApp(),
  ));
}

class CadavreExquisiteApp extends StatelessWidget {
  const CadavreExquisiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cadavre Exquisite',
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AuthWrapper(),
      routes: {
        WelcomeScreen.id: (context) => WelcomeScreen(),
        HomeScreen.id: (context) => const HomeScreen(),
        LoginScreen.id: (context) => const LoginScreen(),
        RegistrationScreen.id: (context) => const RegistrationScreen(),
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    if (!auth.isReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (auth.isAuthenticated) {
      return const HomeScreen();
    }
    return WelcomeScreen();
  }
}
