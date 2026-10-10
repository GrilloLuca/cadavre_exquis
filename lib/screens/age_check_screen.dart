import 'package:cadavre_exquisite/app_colors.dart';
import 'package:cadavre_exquisite/background.dart';
import 'package:cadavre_exquisite/cream_card.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/services/age_check_service.dart';
import 'package:flutter/material.dart';

/// Neutral age screen: asks for the birth year without hinting at the age
/// required, and without preselecting an answer. Pops with the chosen year.
class AgeCheckScreen extends StatefulWidget {
  const AgeCheckScreen({super.key});

  @override
  State<AgeCheckScreen> createState() => _AgeCheckScreenState();
}

class _AgeCheckScreenState extends State<AgeCheckScreen> {
  int? _birthYear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentYear = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ageCheckTitle),
        backgroundColor: AppColors.primary,
      ),
      body: Background(
        opacity: 0.2,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: CreamCard(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.ageCheckQuestion,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  // Explicit colours: the app theme doesn't style dropdown
                  // menus, which otherwise render white on white.
                  DropdownButtonFormField<int>(
                    initialValue: _birthYear,
                    hint: Text(
                      l10n.ageCheckHint,
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.6),
                      ),
                    ),
                    menuMaxHeight: 320.0,
                    dropdownColor: AppColors.cream,
                    focusColor: AppColors.sage,
                    iconEnabledColor: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(12.0),
                    style: const TextStyle(
                      fontSize: 16.0,
                      color: AppColors.ink,
                    ),
                    decoration: const InputDecoration(
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.primaryDark,
                          width: 2.0,
                        ),
                      ),
                    ),
                    items: [
                      for (var year = currentYear;
                          year >= AgeCheckService.oldestBirthYear;
                          year--)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (year) => setState(() => _birthYear = year),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    l10n.ageCheckNote,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.0,
                      color: AppColors.ink.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  ElevatedButton(
                    onPressed: _birthYear == null
                        ? null
                        : () => Navigator.pop(context, _birthYear),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.cream,
                    ),
                    child: Text(l10n.ageCheckConfirm),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
