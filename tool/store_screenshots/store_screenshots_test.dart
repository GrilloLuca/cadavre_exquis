// Renders the store screenshots from the real screens, filled with the
// in-memory fakes, and writes them where fastlane's deliver (iOS) and
// supply (Android) look for them:
//
//   flutter test tool/store_screenshots
//
// Not under test/, so CI's `flutter test` never runs it. The captions and
// sample stories are store copy, not app text, so they live in
// store_copy.dart rather than in the ARB files.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/themes/theme.dart';
import 'package:cadavre_exquisite/ui/home/widgets/home_screen.dart';
import 'package:cadavre_exquisite/ui/story_read/widgets/story_read_screen.dart';

import '../../testing/fakes/repositories/fake_ads_repository.dart';
import '../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../testing/fakes/repositories/fake_private_room_repository.dart';
import '../../testing/fakes/repositories/fake_room_repository.dart';
import '../../testing/fakes/repositories/fake_story_repository.dart';
import '../../testing/fakes/repositories/fake_user_profile_repository.dart';
import 'store_copy.dart';

/// A store slot: the image size, and the screen of the device drawn in it.
class _Target {
  const _Target({
    required this.name,
    required this.canvas,
    required this.pixelRatio,
    required this.screen,
    required this.screenPadding,
    required this.directory,
    this.deviceWidth = 0.82,
  });

  final String name;

  /// Width of the drawn device, as a fraction of [canvas]'s.
  final double deviceWidth;

  /// Logical size of the whole image; times [pixelRatio] gives the pixels
  /// the store asks for.
  final Size canvas;
  final double pixelRatio;

  /// Logical size of the device the app is laid out on, and its system
  /// insets (status bar, home indicator).
  final Size screen;
  final EdgeInsets screenPadding;

  /// Where the images go, given the store locale.
  final String Function(String storeLocale) directory;

  bool get isTablet => screen.shortestSide >= 600.0;
}

String _ios(String locale) => 'ios/fastlane/screenshots/$locale';
String _android(String locale, String kind) =>
    'android/fastlane/metadata/android/$locale/images/$kind';

final _targets = [
  // iPhone 6.9" (1320 x 2868), which App Store Connect scales down for
  // the smaller iPhones.
  _Target(
    name: 'iphone69',
    canvas: const Size(440.0, 956.0),
    pixelRatio: 3.0,
    screen: const Size(393.0, 852.0),
    screenPadding: const EdgeInsets.only(top: 59.0, bottom: 34.0),
    directory: _ios,
  ),
  // iPad 13" (2064 x 2752), required since the app runs on iPad.
  _Target(
    name: 'ipad13',
    canvas: const Size(1032.0, 1376.0),
    pixelRatio: 2.0,
    screen: const Size(834.0, 1194.0),
    screenPadding: const EdgeInsets.only(top: 24.0, bottom: 20.0),
    directory: _ios,
    deviceWidth: 0.78,
  ),
  // Play phone (1080 x 1920).
  _Target(
    name: 'phone',
    canvas: const Size(360.0, 640.0),
    pixelRatio: 3.0,
    screen: const Size(360.0, 760.0),
    screenPadding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
    directory: (locale) => _android(locale, 'phoneScreenshots'),
    // A 16:9 image: a smaller device shows the whole screen.
    deviceWidth: 0.66,
  ),
  // Play 10" tablet (1600 x 2560).
  _Target(
    name: 'tablet10',
    canvas: const Size(800.0, 1280.0),
    pixelRatio: 2.0,
    screen: const Size(800.0, 1280.0),
    screenPadding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
    directory: (locale) => _android(locale, 'tenInchScreenshots'),
    deviceWidth: 0.78,
  ),
];

/// One screenshot: what the caption says and which screen it shows.
class _Shot {
  const _Shot(this.id, this.caption, this.build, {this.prepare});

  final String id;
  final Caption Function(StoreCopy copy) caption;
  final Widget Function(StoreCopy copy) build;

  /// Gets the screen to the state shown (switch tab, type text) once it's
  /// on screen.
  final Future<void> Function(WidgetTester tester, StoreCopy copy)? prepare;
}

final _shots = [
  _Shot(
    '1_write',
    (copy) => copy.captionWrite,
    (copy) => ChatScreen(story: copy.storyToContinue),
    prepare: (tester, copy) async {
      await tester.enterText(find.byType(TextField), copy.draft);
      FocusManager.instance.primaryFocus?.unfocus();
    },
  ),
  _Shot(
    '2_stories',
    (copy) => copy.captionPick,
    (copy) => const HomeScreen(),
  ),
  _Shot(
    '3_read',
    (copy) => copy.captionRead,
    (copy) => StoryReadScreen(story: copy.completeStories.first),
  ),
  _Shot(
    '4_archive',
    (copy) => copy.captionArchive,
    (copy) => const HomeScreen(),
    prepare: (tester, copy) async {
      await tester.tap(find.byIcon(Icons.menu_book));
    },
  ),
  _Shot(
    '5_rooms',
    (copy) => copy.captionRooms,
    (copy) => const HomeScreen(),
    prepare: (tester, copy) async {
      await tester.tap(find.byIcon(Icons.person));
    },
  ),
];

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent
          .parent.path;
  final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('$fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const roboto = [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ];
  await load('Roboto', roboto);
  // Text styles that set no family (button labels) use the test font.
  await load('FlutterTest', roboto);
  await load('Ahem', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);

  // The room's flag; macOS only, which is where this runs.
  final emoji = FontLoader('AppleColorEmoji')
    ..addFont(Future.value(ByteData.sublistView(
        File('/System/Library/Fonts/Apple Color Emoji.ttc')
            .readAsBytesSync())));
  await emoji.load();
}

/// The app's theme with Roboto everywhere: the test engine has no system
/// font to fall back on.
ThemeData _theme() {
  final base = AppTheme.light;
  final typography = Typography.material2021(platform: TargetPlatform.android);
  return base.copyWith(
    textTheme: typography.black.merge(base.textTheme).apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['AppleColorEmoji'],
    ),
    primaryTextTheme: typography.white.apply(fontFamily: 'Roboto'),
  );
}

Widget _app({
  required StoreCopy copy,
  required Widget home,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthRepository>(
          create: (_) => FakeAuthRepository(email: StoreCopy.me)),
      ChangeNotifierProvider<RoomRepository>(
          create: (_) => FakeRoomRepository(languageCode: copy.roomLanguage)),
      Provider<StoryRepository>(
        create: (_) => FakeStoryRepository(
          stories: [...copy.incompleteStories, ...copy.completeStories],
        ),
      ),
      Provider<UserProfileRepository>(
        create: (_) => FakeUserProfileRepository(nicknames: copy.nicknames),
      ),
      Provider<AgeGate>(
          create: (_) => AgeGate(storage: FakeAgeCheckRepository())),
      Provider<PrivateRoomRepository>(
          create: (_) => FakePrivateRoomRepository()),
      ChangeNotifierProvider<AdsRepository>(
          create: (_) => FakeAdsRepository()),
      ChangeNotifierProvider<NotificationRepository>(
        create: (_) => FakeNotificationRepository(
          permission: NotificationPermission.granted,
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(copy.appLocale),
      home: home,
    ),
  );
}

/// The store image: caption on top, the app inside a device below.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.target,
    required this.caption,
    required this.app,
    required this.labels,
  });

  final _Target target;
  final Caption caption;
  final Widget app;

  /// Button labels painted over the app; see [_relabelButtons].
  final ValueNotifier<List<_Label>> labels;

  /// The device's screen, which [_Label.rect] is relative to.
  static final screenKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final canvas = target.canvas;
    final unit = canvas.shortestSide / 100.0;
    final bezel = unit * (target.isTablet ? 1.4 : 2.2);
    final radius = unit * (target.isTablet ? 5.0 : 11.0);
    final captionHeight = canvas.height * (target.isTablet ? 0.17 : 0.22);
    final deviceTop = captionHeight;
    // The device is cut by the bottom edge, as if it rose from below.
    final deviceWidth = canvas.width * target.deviceWidth;
    final scale = (deviceWidth - 2 * bezel) / target.screen.width;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.fromSize(
        size: canvas,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.cream, AppColors.sage],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.18,
                  child: Image.asset(
                    'images/background_portrait.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                left: unit * 7,
                right: unit * 7,
                top: 0,
                height: captionHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      caption.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: unit * (target.isTablet ? 6.0 : 7.6),
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    SizedBox(height: unit * 2.2),
                    Text(
                      caption.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: unit * (target.isTablet ? 3.0 : 4.2),
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: deviceTop,
                left: (canvas.width - deviceWidth) / 2,
                width: deviceWidth,
                height: target.screen.height * scale + 2 * bezel,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(radius + bezel),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.25),
                        blurRadius: unit * 6,
                        offset: Offset(0, unit * 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(bezel),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: SizedBox.fromSize(
                          key: _Frame.screenKey,
                          size: target.screen,
                          child: MediaQuery(
                            data: MediaQueryData(
                              size: target.screen,
                              padding: target.screenPadding,
                              viewPadding: target.screenPadding,
                              devicePixelRatio: target.pixelRatio * scale,
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(child: app),
                                _StatusBar(target: target),
                                ValueListenableBuilder(
                                  valueListenable: labels,
                                  builder: (context, labels, _) => Stack(
                                    children: [
                                      for (final label in labels)
                                        Positioned.fromRect(
                                          rect: label.rect,
                                          child: ColoredBox(
                                            color: label.background,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                label.text,
                                                maxLines: 1,
                                                style: label.style,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A button label repainted in Roboto.
class _Label {
  const _Label(this.rect, this.text, this.style, this.background);

  final Rect rect;
  final String text;
  final TextStyle style;
  final Color background;
}

/// Material buttons set a text style without a font family, which the test
/// engine always draws in its block font. Their labels are painted again
/// on top, in Roboto, with the button's own colours.
List<_Label> _relabelButtons(WidgetTester tester) {
  final screen =
      _Frame.screenKey.currentContext!.findRenderObject()! as RenderBox;
  final labels = <_Label>[];
  for (final element in find
      .descendant(
          of: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          matching: find.byType(RichText))
      .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final style = paragraph.text.style;
    if (style == null || style.fontFamily != null) continue;
    final button = element.findAncestorWidgetOfExactType<Material>();
    final topLeft = paragraph.localToGlobal(Offset.zero, ancestor: screen);
    labels.add(_Label(
      (topLeft & paragraph.size).inflate(1.0),
      paragraph.text.toPlainText(),
      style.copyWith(fontFamily: 'Roboto'),
      button?.color ?? Colors.transparent,
    ));
  }
  return labels;
}

/// Time and battery over the app bar, as on a real device.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.target});

  final _Target target;

  @override
  Widget build(BuildContext context) {
    final height = target.screenPadding.top;
    const style = TextStyle(
      fontFamily: 'Roboto',
      color: Colors.white,
      fontSize: 15.0,
      fontWeight: FontWeight.w600,
    );
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: height,
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: target.isTablet ? 20.0 : 30.0,
          ),
          child: Row(
            children: [
              Text('9:41', style: style.copyWith(fontSize: height > 40 ? 16 : 13)),
              const Spacer(),
              Icon(Icons.signal_cellular_alt,
                  color: Colors.white, size: height > 40 ? 18 : 14),
              const SizedBox(width: 4.0),
              Icon(Icons.wifi, color: Colors.white, size: height > 40 ? 18 : 14),
              const SizedBox(width: 4.0),
              Icon(Icons.battery_full,
                  color: Colors.white, size: height > 40 ? 20 : 15),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final copy in storeCopies) {
    testWidgets('${copy.appLocale} feature graphic', (tester) async {
      tester.view
        ..physicalSize = const Size(1024.0, 500.0)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      final icon =
          MemoryImage(File('assets/icon/icon.png').readAsBytesSync());
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: _FeatureGraphic(copy: copy, icon: icon),
      ));
      final bytes = await tester.runAsync(() async {
        final context = tester.element(find.byType(_FeatureGraphic));
        await precacheImage(icon, context);
        await precacheImage(
            const AssetImage('images/background_landscape.jpeg'), context);
        return null;
      }).then((_) async {
        await tester.pump();
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        return tester.runAsync(() async {
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });
      });
      final dir = Directory(_android(copy.playLocale, ''))
        ..createSync(recursive: true);
      debugDisableShadows = true;
      File('${dir.path}featureGraphic.png').writeAsBytesSync(bytes!);
    });

    for (final target in _targets) {
      for (final shot in _shots) {
        testWidgets('${copy.appLocale} ${target.name} ${shot.id}',
            (tester) async {
          tester.view
            ..physicalSize = target.canvas * target.pixelRatio
            ..devicePixelRatio = target.pixelRatio;
          addTearDown(tester.view.reset);
          // flutter_test draws elevation as solid black outlines; it checks
          // the flag is back before tear-down, so it's restored below.
          debugDisableShadows = false;

          final boundary = GlobalKey();
          final labels = ValueNotifier<List<_Label>>(const []);
          addTearDown(labels.dispose);
          await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: _Frame(
              target: target,
              caption: shot.caption(copy),
              app: _app(copy: copy, home: shot.build(copy)),
              labels: labels,
            ),
          ));
          // Asset images decode outside the fake clock.
          await tester.runAsync(() async {
            final context = tester.element(find.byType(_Frame));
            for (final name in [
              'images/background_portrait.jpeg',
              'images/background_landscape.jpeg',
            ]) {
              await precacheImage(AssetImage(name), context);
            }
          });
          await _settle(tester);
          await shot.prepare?.call(tester, copy);
          await _settle(tester);
          labels.value = _relabelButtons(tester);
          await tester.pump();

          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final bytes = await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: target.pixelRatio);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            return data!.buffer.asUint8List();
          });
          debugDisableShadows = true;
          final dir = Directory(target.directory(
              target.directory == _ios ? copy.iosLocale : copy.playLocale));
          dir.createSync(recursive: true);
          final prefix = target.directory == _ios ? '${target.name}_' : '';
          File('${dir.path}/$prefix${shot.id}.png').writeAsBytesSync(bytes!);
        });
      }
    }
  }
}

/// Play's feature graphic (1024 x 500): the mascot from the app icon next
/// to the name and tagline.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.copy, required this.icon});

  final StoreCopy copy;
  final ImageProvider icon;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 1024.0,
        height: 500.0,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.sage),
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.15,
                  child: Image.asset(
                    'images/background_landscape.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cadavre Exquisite',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 64.0,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 20.0),
                          Text(
                            copy.featureTagline,
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 30.0,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32.0),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(72.0),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.3),
                            blurRadius: 24.0,
                            offset: const Offset(0.0, 8.0),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(72.0),
                        child: Image(image: icon, width: 320.0, height: 320.0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets transitions and loads finish. Not pumpAndSettle: the typing
/// indicator and the text cursor animate forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
