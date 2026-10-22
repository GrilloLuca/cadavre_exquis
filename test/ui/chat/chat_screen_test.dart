import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_composer.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_turn_card.dart';
import 'package:cadavre_exquisite/ui/core/ui/message_bubble.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

/// Counts how many times the story was locked.
class _CountingStoryRepository extends FakeStoryRepository {
  _CountingStoryRepository({super.stories, super.now});

  int locks = 0;

  @override
  Future<void> lockStory({
    required String storyId,
    required String authorEmail,
  }) {
    locks++;
    return super.lockStory(storyId: storyId, authorEmail: authorEmail);
  }
}

/// Holds locking or submitting until a gate opens, and can make submitting
/// fail.
class _GatedStoryRepository extends FakeStoryRepository {
  _GatedStoryRepository({super.stories, super.now});

  Completer<void>? lockGate;
  Completer<void>? submitGate;
  Object? submitError;

  @override
  Future<void> lockStory({
    required String storyId,
    required String authorEmail,
  }) async {
    await lockGate?.future;
    return super.lockStory(storyId: storyId, authorEmail: authorEmail);
  }

  @override
  Future<void> submitPart({
    required String storyId,
    required String expectedPosition,
    required String text,
    required String authorEmail,
  }) async {
    await submitGate?.future;
    final error = submitError;
    if (error != null) throw error;
    return super.submitPart(
      storyId: storyId,
      expectedPosition: expectedPosition,
      text: text,
      authorEmail: authorEmail,
    );
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 12, 10);

  /// A story whose [parts] all have a verdict, unless [reviewed] is false
  /// (then the last one awaits the AI review).
  Story story({
    String? lockedBy,
    List<StoryPart> parts = const [],
    List<String> keywords = const [],
    bool reviewed = true,
  }) =>
      Story(
        id: 's1',
        status: 'incomplete',
        currentPosition: kStoryPositions[parts.length],
        parts: parts,
        lockedBy: lockedBy,
        lockedAt: lockedBy == null ? null : now,
        language: 'it',
        keywords: keywords,
        partReviews: {
          for (final (i, part) in parts.indexed)
            if (reviewed || i < parts.length - 1)
              part.position: PartVerdict.safe,
        },
      );

  StoryPart part(int index, String text) => StoryPart(
        position: kStoryPositions[index],
        text: text,
        author: 'other@example.com',
        // Shown relative to the real clock, not to [now].
        timestamp: DateTime.now().subtract(const Duration(hours: 4)),
      );

  final introduction = part(0, 'Un drago viveva nel faro durante la tempesta');

  /// The first [count] parts, the last one ending in [lastText].
  List<StoryPart> parts(int count,
          {String lastText = 'quando il faro si spense'}) =>
      [
        for (var i = 0; i < count; i++)
          part(i, i == count - 1 ? lastText : 'Parte numero $i'),
      ];

  late AppLocalizations l10n;

  /// The label above the previous part's last words, for the default
  /// author and timestamp of [part].
  String previousAuthorLabel([String name = 'Lupo']) =>
      l10n.chatPreviousAuthorLabel(name, l10n.timeHoursAgo(4));

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  /// Rebuilds the whole app, as a change above the Navigator does.
  late StateSetter rebuildApp;

  /// Pumps a page with an "open" button that pushes the chat screen. With
  /// [settle] false it doesn't wait for animations to end, for states with
  /// a progress indicator.
  Future<void> pumpAndOpen(
    WidgetTester tester,
    FakeStoryRepository stories, {
    FakeNotificationRepository? notifications,
    FakeUserProfileRepository? profiles,
    Locale locale = const Locale('en'),
    bool settle = true,
  }) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: 'me@example.com')),
        Provider<StoryRepository>.value(value: stories),
        ChangeNotifierProvider<NotificationRepository>(
            create: (_) => notifications ?? FakeNotificationRepository()),
        Provider<UserProfileRepository>(
            create: (_) =>
                profiles ??
                FakeUserProfileRepository(
                    nicknames: const {'other@example.com': 'Lupo'})),
      ],
      child: StatefulBuilder(builder: (context, setState) {
        rebuildApp = setState;
        return MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(story: stories.stories['s1']!),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// The Send button (the screen's only filled button), in any state.
  Finder sendButton() => find.byWidgetPredicate((w) => w is FilledButton);

  bool sendEnabled(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(sendButton()).enabled;

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('writes and sends a part, then closes with a message',
      (tester) async {
    final stories = FakeStoryRepository(stories: [story()], now: () => now);
    await pumpAndOpen(tester, stories);

    expect(find.byType(ChatScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Once upon a time');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(stories.stories['s1']!.parts.single.text, 'Once upon a time');
    expect(find.text(l10n.chatSentSnackbar), findsOneWidget);
  });

  testWidgets('sending the ending says the story is complete', (tester) async {
    final stories =
        FakeStoryRepository(stories: [story(parts: parts(3))], now: () => now);
    await pumpAndOpen(tester, stories);

    await tester.enterText(find.byType(TextField), 'The end');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(stories.stories['s1']!.isComplete, isTrue);
    expect(find.text(l10n.chatCompletedSnackbar), findsOneWidget);
    expect(find.text(l10n.chatSentSnackbar), findsNothing);
  });

  testWidgets('a story locked by someone else closes with a message',
      (tester) async {
    final stories = FakeStoryRepository(
        stories: [story(lockedBy: 'other@example.com')], now: () => now);
    await pumpAndOpen(tester, stories);

    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text(l10n.errorStoryLockedByOther), findsOneWidget);
  });

  testWidgets(
      'a story whose last part is under review closes with a message on the '
      'screen below', (tester) async {
    final stories = FakeStoryRepository(
        stories: [story(parts: parts(1), reviewed: false)], now: () => now);
    await pumpAndOpen(tester, stories);

    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text(l10n.storyUnderReviewError), findsOneWidget);
    expect(stories.stories['s1']!.lockedBy, isNull);
  });

  testWidgets('a submit refused as under review keeps the text, in the chat',
      (tester) async {
    final stories = _GatedStoryRepository(stories: [story()], now: () => now)
      ..submitError = const StoryException(StoryErrorCode.underReview);
    await pumpAndOpen(tester, stories);

    await tester.enterText(find.byType(TextField), 'Once upon a time');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text(l10n.storyUnderReviewError), findsOneWidget);
    expect(find.text('Once upon a time'), findsOneWidget);
  });

  testWidgets('a failed submit keeps the text, editable', (tester) async {
    final stories = _GatedStoryRepository(stories: [story()], now: () => now)
      ..submitError = const StoryException(StoryErrorCode.positionTaken);
    await pumpAndOpen(tester, stories);

    await tester.enterText(find.byType(TextField), 'Once upon a time');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text(l10n.errorStoryPositionTaken), findsOneWidget);
    expect(find.text('Once upon a time'), findsOneWidget);
    expect(field(tester).enabled, isTrue);
    expect(field(tester).readOnly, isFalse);
    expect(sendEnabled(tester), isTrue);
  });

  testWidgets('leaving without sending gives the lock back', (tester) async {
    final stories = FakeStoryRepository(stories: [story()], now: () => now);
    await pumpAndOpen(tester, stories);
    expect(stories.stories['s1']!.lockedBy, 'me@example.com');

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(stories.stories['s1']!.lockedBy, isNull);
  });

  group('leaving with unsent text', () {
    testWidgets('asks first, and "Keep writing" stays', (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);
      await tester.enterText(find.byType(TextField), 'Once upon a time');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text(l10n.chatLeaveTitle), findsOneWidget);
      expect(find.text(l10n.chatLeaveBody), findsOneWidget);

      await tester.tap(find.text(l10n.chatLeaveCancel));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Once upon a time'), findsOneWidget);
      expect(stories.stories['s1']!.lockedBy, 'me@example.com');
    });

    testWidgets('"Leave" closes and gives the lock back', (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);
      await tester.enterText(find.byType(TextField), 'Once upon a time');
      await tester.pump();

      // System back asks too.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(l10n.chatLeaveTitle), findsOneWidget);

      await tester.tap(find.text(l10n.chatLeaveConfirm));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(stories.stories['s1']!.lockedBy, isNull);
    });

    testWidgets('whitespace only doesn\'t ask', (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);
      await tester.enterText(find.byType(TextField), '  \n ');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text(l10n.chatLeaveTitle), findsNothing);
      expect(find.byType(ChatScreen), findsNothing);
    });
  });

  testWidgets('an app rebuild while open keeps the same ViewModel',
      (tester) async {
    // The route's builder runs again when the Navigator's dependencies
    // change; a ViewModel created there would lock the story again and
    // leave the screen listening to the old one.
    final stories =
        _CountingStoryRepository(stories: [story()], now: () => now);
    await pumpAndOpen(tester, stories);

    rebuildApp(() {});
    await tester.pumpAndSettle();
    expect(stories.locks, 1);

    await tester.enterText(find.byType(TextField), 'Once upon a time');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('offers notifications after sending, then closes',
      (tester) async {
    final stories = FakeStoryRepository(stories: [story()], now: () => now);
    final notifications = FakeNotificationRepository(
      permission: NotificationPermission.notDetermined,
      offer: true,
    );
    await pumpAndOpen(tester, stories, notifications: notifications);

    await tester.enterText(find.byType(TextField), 'Once upon a time');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Want to know when someone continues your story?'),
        findsOneWidget);
    expect(find.text(l10n.chatSentSnackbar), findsNothing);
    await tester.tap(find.text('Yes, notify me'));
    await tester.pumpAndSettle();

    expect(notifications.calls, ['enable']);
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text(l10n.chatSentSnackbar), findsOneWidget);
  });

  testWidgets('"Not now" closes without asking for the permission',
      (tester) async {
    final stories = FakeStoryRepository(stories: [story()], now: () => now);
    final notifications = FakeNotificationRepository(
      permission: NotificationPermission.notDetermined,
      offer: true,
    );
    await pumpAndOpen(tester, stories, notifications: notifications);

    await tester.enterText(find.byType(TextField), 'Once upon a time');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(notifications.calls, ['dismissOffer']);
    expect(find.byType(ChatScreen), findsNothing);
  });

  group('turn card', () {
    /// The fills and borders of the 4 progress segments, as
    /// 'done' / 'current' / 'future'.
    List<String> segments(WidgetTester tester) => tester
            .widgetList<DecoratedBox>(find.descendant(
          of: find.byKey(const ValueKey('chatProgressSegments')),
          matching: find.byType(DecoratedBox),
        ))
            .map((box) {
          final decoration = box.decoration as BoxDecoration;
          if (decoration.color == AppColors.primary) return 'done';
          if (decoration.color == AppColors.primaryDark) return 'current';
          expect(decoration.color, isNull);
          expect(decoration.border, isNotNull);
          return 'future';
        }).toList();

    testWidgets('the first part: progress 1 of 4, headline and lead',
        (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(find.text('Part 1 of 4'), findsOneWidget);
      expect(segments(tester), ['current', 'future', 'future', 'future']);
      expect(find.text(l10n.chatHeadlineFirst), findsOneWidget);
      expect(find.text(l10n.chatLeadFirst), findsOneWidget);
    });

    testWidgets('the ending: progress 4 of 4, headline and lead',
        (tester) async {
      final stories = FakeStoryRepository(
          stories: [story(parts: parts(3))], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(find.text('Part 4 of 4'), findsOneWidget);
      expect(segments(tester), ['done', 'done', 'done', 'current']);
      expect(find.text(l10n.chatHeadlineLast), findsOneWidget);
      expect(find.text(l10n.chatLeadLast), findsOneWidget);
    });

    for (final count in [1, 2]) {
      testWidgets('middle part ${count + 1}: progress, headline and lead',
          (tester) async {
        final stories = FakeStoryRepository(
            stories: [story(parts: parts(count))], now: () => now);
        await pumpAndOpen(tester, stories);

        expect(find.text('Part ${count + 1} of 4'), findsOneWidget);
        expect(segments(tester).where((s) => s == 'done'), hasLength(count));
        expect(find.text(l10n.chatHeadlineMiddle), findsOneWidget);
        expect(find.text(l10n.chatLeadMiddle), findsOneWidget);
      });
    }

    testWidgets('headings are headers for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      final stories = FakeStoryRepository(stories: [
        story(parts: [introduction], keywords: const ['drago'])
      ], now: () => now);
      await pumpAndOpen(tester, stories);

      for (final heading in [
        l10n.chatHeadlineMiddle,
        l10n.storyKeywordsLabel
      ]) {
        expect(
          tester.getSemantics(find.text(heading)),
          matchesSemantics(label: heading, isHeader: true),
        );
      }
      semantics.dispose();
    });
  });

  group('keywords', () {
    testWidgets('shows the heading and the tags in the card', (tester) async {
      final semantics = tester.ensureSemantics();
      final stories = FakeStoryRepository(stories: [
        story(
          parts: [introduction],
          keywords: const ['drago', 'faro', 'tempesta', 'segreto', 'quinto'],
        ),
      ], now: () => now);
      await pumpAndOpen(tester, stories);

      final card = find.byType(Card);
      expect(
          find.descendant(
              of: card, matching: find.text("What it's about so far")),
          findsOneWidget);
      for (final keyword in ['drago', 'faro', 'tempesta', 'segreto']) {
        expect(find.descendant(of: card, matching: find.text(keyword)),
            findsOneWidget);
        // A label, not a button.
        expect(tester.getSemantics(find.text(keyword)),
            matchesSemantics(label: keyword));
      }
      expect(find.text('quinto'), findsNothing);
      expect(find.byType(Chip), findsNothing);

      // Tapping a tag does nothing.
      await tester.tap(find.text('drago'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('drago'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('shows no section when the story has no keywords',
        (tester) async {
      final stories = FakeStoryRepository(stories: [
        story(parts: [introduction])
      ], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(find.text(previousAuthorLabel()), findsOneWidget);
      expect(find.text(l10n.storyKeywordsLabel), findsNothing);
    });

    testWidgets('shows no section when the story has no parts yet',
        (tester) async {
      final stories = FakeStoryRepository(stories: [
        story(keywords: const ['drago', 'faro'])
      ], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(find.text(l10n.chatHeadlineFirst), findsOneWidget);
      expect(find.text(l10n.storyKeywordsLabel), findsNothing);
      expect(find.text('drago'), findsNothing);
    });
  });

  group('lead-in', () {
    testWidgets('shows the last five words in a bubble above the composer',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final stories = FakeStoryRepository(
          stories: [story(parts: parts(1))], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(find.text(previousAuthorLabel()), findsOneWidget);
      final words = find.text('…quando il faro si spense');
      expect(words, findsOneWidget);
      expect(find.ancestor(of: words, matching: find.byType(MessageBubble)),
          findsOneWidget);
      expect(tester.getBottomLeft(words).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy));
      // Read as one node.
      expect(
        tester.getSemantics(words),
        matchesSemantics(
            label: 'Lupo wrote 4 hours ago:\n…quando il faro si spense'),
      );
      semantics.dispose();
    });

    testWidgets('is absent for the first part', (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(find.textContaining(' wrote '), findsNothing);
      expect(find.textContaining('…'), findsOneWidget); // The field's hint.
      expect(find.text(l10n.chatInputHint), findsOneWidget);
    });

    testWidgets('names an author without a nickname by the masked email',
        (tester) async {
      final stories = FakeStoryRepository(
          stories: [story(parts: parts(1))], now: () => now);
      await pumpAndOpen(tester, stories, profiles: FakeUserProfileRepository());

      expect(find.text(previousAuthorLabel('ot***')), findsOneWidget);
    });

    testWidgets('a "word" over 120 characters shows only its end',
        (tester) async {
      final text = '${'a' * 299}z';
      final stories = FakeStoryRepository(
          stories: [story(parts: parts(1, lastText: text))], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(find.text('…${'a' * 119}z'), findsOneWidget);
    });

    testWidgets('shows no other story text', (tester) async {
      final stories = FakeStoryRepository(stories: [
        story(parts: [
          part(0, 'Il drago Zanzibarre viveva nel faro'),
          part(1, 'sesta prima quinta quarta terza seconda ultima'),
        ])
      ], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(find.text('…quinta quarta terza seconda ultima'), findsOneWidget);
      expect(find.textContaining('Zanzibarre'), findsNothing);
      expect(find.textContaining('prima'), findsNothing);
    });
  });

  group('composer', () {
    testWidgets('Send needs the lock and some text', (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(sendEnabled(tester), isFalse);
      await tester.enterText(find.byType(TextField), '   \n  ');
      await tester.pump();
      expect(sendEnabled(tester), isFalse);
      await tester.enterText(find.byType(TextField), 'C\'era una volta');
      await tester.pump();
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('the field has its label and isn\'t focused once locked',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final stories = FakeStoryRepository(
          stories: [story(parts: parts(1))], now: () => now);
      await pumpAndOpen(tester, stories);

      expect(field(tester).enabled, isTrue);
      expect(field(tester).focusNode?.hasFocus ?? false, isFalse);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
      expect(find.bySemanticsLabel(RegExp('^Your part: Development \\(1/2\\)')),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('while reserving the turn the card stays readable',
        (tester) async {
      final stories = _GatedStoryRepository(stories: [story()], now: () => now)
        ..lockGate = Completer<void>();
      await pumpAndOpen(tester, stories, settle: false);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
          find.descendant(
              of: find.byType(ChatComposer),
              matching: find.byType(LinearProgressIndicator)),
          findsOneWidget);
      expect(field(tester).enabled, isFalse);
      expect(field(tester).decoration?.hintText, l10n.chatReservingTurn);
      expect(sendEnabled(tester), isFalse);
      expect(find.text(l10n.chatHeadlineFirst), findsOneWidget);

      stories.lockGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(field(tester).enabled, isTrue);
      expect(field(tester).decoration?.hintText, l10n.chatInputHint);
    });

    testWidgets('while sending nothing can close the screen', (tester) async {
      final stories = _GatedStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);
      await tester.enterText(find.byType(TextField), 'Once upon a time');
      await tester.pump();

      stories.submitGate = Completer<void>();
      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(find.text(l10n.chatSending), findsOneWidget);
      expect(
          find.descendant(
              of: sendButton(),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(sendEnabled(tester), isFalse);
      expect(field(tester).readOnly, isTrue);
      expect(find.text('Once upon a time'), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
              .onPressed,
          isNull);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text(l10n.chatLeaveTitle), findsNothing);

      stories.submitGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(stories.stories['s1']!.parts.single.text, 'Once upon a time');
    });

    testWidgets('the field takes at most 5000 characters', (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);

      await tester.enterText(find.byType(TextField), 'a' * 5200);
      await tester.pump();
      expect(field(tester).controller!.text, hasLength(kMaxPartLength));
      expect(find.text('5,000/5,000'), findsOneWidget);
    });

    testWidgets('the counter shows from 4500 characters on', (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories);

      await tester.enterText(find.byType(TextField), 'a' * 4499);
      await tester.pump();
      expect(find.textContaining('/5,000'), findsNothing);

      await tester.enterText(find.byType(TextField), 'a' * 4500);
      await tester.pump();
      expect(find.text('4,500/5,000'), findsOneWidget);
    });

    testWidgets('the counter uses the Italian number format', (tester) async {
      final stories = FakeStoryRepository(stories: [story()], now: () => now);
      await pumpAndOpen(tester, stories, locale: const Locale('it'));

      await tester.enterText(find.byType(TextField), 'a' * 4500);
      await tester.pump();
      expect(find.text('4.500/5.000'), findsOneWidget);
    });
  });

  group('layout', () {
    void setScreen(WidgetTester tester, Size size,
        {double keyboard = 0.0, double textScale = 1.0}) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    Story laterPart() => story(
          parts: parts(2),
          keywords: const ['drago', 'faro', 'tempesta', 'segreto'],
        );

    testWidgets('the last words sit at the bottom, right above the composer',
        (tester) async {
      setScreen(tester, const Size(360, 800));
      final stories = FakeStoryRepository(
          stories: [story(parts: parts(1))], now: () => now);
      await pumpAndOpen(tester, stories);

      final bubble = tester.getRect(find.byType(MessageBubble));
      final composer = tester.getRect(find.byType(ChatComposer));
      expect(composer.top - bubble.bottom, lessThanOrEqualTo(16.0));
      // Far from the turn card on a tall screen.
      expect(bubble.top - tester.getRect(find.byType(ChatTurnCard)).bottom,
          greaterThan(100.0));
    });

    testWidgets('a small phone with the keyboard open keeps the composer',
        (tester) async {
      setScreen(tester, const Size(360, 640), keyboard: 260);
      final stories =
          FakeStoryRepository(stories: [laterPart()], now: () => now);
      await pumpAndOpen(tester, stories);
      // Typing, as with the keyboard open.
      await tester.enterText(find.byType(TextField), "C'era una volta");
      await tester.pump();

      expect(tester.takeException(), isNull);
      const visible = Rect.fromLTRB(0, 0, 360, 640 - 260);
      for (final finder in [
        find.text('…quando il faro si spense'),
        find.byType(TextField),
        sendButton(),
      ]) {
        final rect = tester.getRect(finder);
        expect(visible.contains(rect.topLeft), isTrue, reason: '$finder');
        expect(rect.bottom, lessThanOrEqualTo(visible.bottom),
            reason: '$finder');
      }
    });

    for (final keyboard in [0.0, 260.0]) {
      testWidgets('large text with keyboard $keyboard: no overflow',
          (tester) async {
        setScreen(tester, const Size(320, 640),
            keyboard: keyboard, textScale: 2.0);
        final stories =
            FakeStoryRepository(stories: [laterPart()], now: () => now);
        await pumpAndOpen(tester, stories);

        expect(tester.takeException(), isNull);
        final body = tester.getSize(find.byType(Background)).height;
        expect(tester.getSize(find.byType(ChatComposer)).height,
            lessThanOrEqualTo(body * 0.6 + 0.01));
      });
    }
  });
}
