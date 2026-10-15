import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:flutter/material.dart';

const kMessageContainerDecoration = BoxDecoration(
  border: Border(
    top: BorderSide(color: AppColors.primary, width: 2.0),
  ),
);

const kTextFieldDecoration = InputDecoration(
  contentPadding:
  EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(32.0)),
  ),
  enabledBorder: OutlineInputBorder(
    borderSide: BorderSide(color: AppColors.primaryDark),
    borderRadius: BorderRadius.all(Radius.circular(32.0)),
  ),
  focusedBorder: OutlineInputBorder(
    borderSide: BorderSide(color: AppColors.primaryDark, width: 2.0),
    borderRadius: BorderRadius.all(Radius.circular(32.0)),
  ),
);