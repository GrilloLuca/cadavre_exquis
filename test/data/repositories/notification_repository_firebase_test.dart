import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/repositories/notification/notification_repository_firebase.dart';

void main() {
  test('notifications are written in the language the app shows', () {
    expect(notificationLocale(const [Locale('it', 'IT')]), 'it');
    expect(notificationLocale(const [Locale('fr'), Locale('it')]), 'it');
    expect(notificationLocale(const [Locale('fr')]), 'en');
    expect(notificationLocale(const []), 'en');
  });
}
