import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_search.dart';

Story _story({
  String id = 's',
  String? title,
  List<String> keywords = const [],
  String text = '',
}) =>
    Story(
      id: id,
      status: 'complete',
      currentPosition: 'epilogo',
      parts: [
        StoryPart(
          position: 'introduzione',
          text: text,
          author: 'ada@x.com',
          timestamp: DateTime(2026, 10, 21),
        ),
      ],
      title: title,
      keywords: keywords,
    );

bool _matches(String query, Story story) => StoryQuery(query).matches(story);

void main() {
  group('foldForSearch', () {
    test('lowercases', () {
      expect(foldForSearch('Il DRAGO'), 'il drago');
    });

    test('folds the accents of the room languages', () {
      expect(foldForSearch('Città'), 'citta');
      expect(foldForSearch('àáâãäå'), 'aaaaaa');
      expect(foldForSearch('èéêë'), 'eeee');
      expect(foldForSearch('ìíîï'), 'iiii');
      expect(foldForSearch('òóôõöø'), 'oooooo');
      expect(foldForSearch('ùúûü'), 'uuuu');
      expect(foldForSearch('ýÿ'), 'yy');
      expect(foldForSearch('ç ñ'), 'c n');
    });

    test('folds uppercase accented letters after lowercasing them', () {
      expect(foldForSearch('ÀÉÎÕÜ ÇÑ'), 'aeiou cn');
      expect(foldForSearch('Müller'), 'muller');
    });

    test('expands ligatures and sharp s', () {
      expect(foldForSearch('Straße'), 'strasse');
      expect(foldForSearch('Æsir'), 'aesir');
      expect(foldForSearch('cœur'), 'coeur');
    });

    test('leaves other characters alone', () {
      expect(foldForSearch("l'isola 42!"), "l'isola 42!");
      expect(foldForSearch(''), '');
    });
  });

  group('searchTokens', () {
    test('splits on spaces and punctuation, dropping empty pieces', () {
      expect(searchTokens('  Il  drago,  e il faro!  '), [
        'il',
        'drago',
        'e',
        'il',
        'faro',
      ]);
    });

    test('splits on apostrophes', () {
      expect(searchTokens("L'isola dell’orso"), ['l', 'isola', 'dell', 'orso']);
    });

    test('splits on hyphens', () {
      expect(searchTokens('castello-fantasma'), ['castello', 'fantasma']);
    });

    test('keeps digits and accented letters inside words', () {
      expect(searchTokens('Il 2° Città'), ['il', '2', 'citta']);
    });

    test('gives no tokens for empty or separator-only text', () {
      expect(searchTokens(''), isEmpty);
      expect(searchTokens("  ' - , "), isEmpty);
    });
  });

  group('StoryQuery tokens', () {
    test('keep the input order', () {
      expect(StoryQuery('faro drago tempesta').tokens, [
        'faro',
        'drago',
        'tempesta',
      ]);
    });

    test('drop short tokens when a longer one is present', () {
      expect(StoryQuery("il drago e l'isola").tokens, ['drago', 'isola']);
    });

    test('keep short tokens when all are short', () {
      expect(StoryQuery('re').tokens, ['re']);
      expect(StoryQuery('il re').tokens, ['il', 're']);
    });

    test('keep a token of exactly 3 characters', () {
      expect(StoryQuery('il re sol').tokens, ['sol']);
    });

    test('keep the raw text', () {
      expect(StoryQuery(' Il Drago ').text, ' Il Drago ');
    });

    test('empty and whitespace-only queries are empty', () {
      expect(StoryQuery('').isEmpty, isTrue);
      expect(StoryQuery('   ').isEmpty, isTrue);
      expect(StoryQuery(" ' - ").isEmpty, isTrue);
      expect(StoryQuery.empty.isEmpty, isTrue);
      expect(StoryQuery('drago').isEmpty, isFalse);
    });

    test('hasSameTokens compares the effective tokens', () {
      final query = StoryQuery('drago');
      expect(query.hasSameTokens(StoryQuery(' Drago ')), isTrue);
      expect(query.hasSameTokens(StoryQuery('il drago')), isTrue);
      expect(query.hasSameTokens(StoryQuery('drag')), isFalse);
      expect(query.hasSameTokens(StoryQuery('drago faro')), isFalse);
      expect(
        StoryQuery('faro drago').hasSameTokens(StoryQuery('drago faro')),
        isFalse,
      );
      expect(StoryQuery('').hasSameTokens(StoryQuery('  ')), isTrue);
    });
  });

  group('StoryQuery.matches', () {
    final dragon = _story(
      title: 'Un drago a Milano',
      keywords: ['principessa', "l'isola", 'castello-fantasma'],
    );

    test('matches the title', () {
      expect(_matches('milano', dragon), isTrue);
    });

    test('matches the keywords', () {
      expect(_matches('principessa', dragon), isTrue);
      expect(_matches('fantasma', dragon), isTrue);
    });

    test('ignores case', () {
      expect(_matches('MILANO', dragon), isTrue);
      expect(_matches('Drago', _story(title: 'IL DRAGO')), isTrue);
    });

    test('folds accents on both sides', () {
      expect(_matches('citta', _story(title: 'La città perduta')), isTrue);
      expect(_matches('città', _story(title: 'La citta perduta')), isTrue);
      expect(_matches('muller', _story(keywords: ['Müller'])), isTrue);
      expect(_matches('strasse', _story(keywords: ['Straße'])), isTrue);
      expect(_matches('straße', _story(keywords: ['strasse'])), isTrue);
    });

    test('finds a word after an apostrophe', () {
      expect(_matches('isola', dragon), isTrue);
      expect(_matches("l'isola", dragon), isTrue);
    });

    test('matches prefixes of story words', () {
      expect(_matches('drag', dragon), isTrue);
      expect(_matches('princip', dragon), isTrue);
    });

    test('matches only at the start of a word', () {
      expect(_matches('rago', dragon), isFalse);
      expect(_matches('ilano', dragon), isFalse);
    });

    test('a query word longer than the story word does not match', () {
      expect(_matches('draghi', _story(title: 'Il drago')), isFalse);
      expect(_matches('dragone', _story(title: 'Il drago')), isFalse);
    });

    test('requires every query word to match (AND)', () {
      expect(_matches('drago milano', dragon), isTrue);
      expect(_matches('drago principessa', dragon), isTrue);
      expect(_matches('drago roma', dragon), isFalse);
    });

    test('query words may match the same story word', () {
      expect(_matches('drag drago', dragon), isTrue);
    });

    test('ignores short query words when a longer one is present', () {
      expect(_matches('il drago', dragon), isTrue);
      expect(_matches('la principessa', dragon), isTrue);
    });

    test('uses short query words when all are short', () {
      final king = _story(title: 'Il re di Roma');
      expect(_matches('re', king), isTrue);
      expect(_matches('re', dragon), isFalse);
      expect(_matches('il re', king), isTrue);
      expect(_matches('un re', king), isFalse);
    });

    test('an empty or whitespace-only query matches every story', () {
      expect(_matches('', dragon), isTrue);
      expect(_matches('   ', dragon), isTrue);
      expect(_matches('', _story()), isTrue);
      expect(StoryQuery.empty.matches(dragon), isTrue);
    });

    test('a story without title and keywords matches only the empty query', () {
      final bare = _story(text: 'Il drago volava su Milano');
      expect(_matches('', bare), isTrue);
      expect(_matches('drago', bare), isFalse);
      expect(_matches('re', bare), isFalse);
    });

    test('never matches the part text', () {
      final story = _story(title: 'Il faro', text: 'Un drago segreto');
      expect(_matches('faro', story), isTrue);
      expect(_matches('drago', story), isFalse);
      expect(_matches('segreto', story), isFalse);
    });

    test('a query of separators only matches every story', () {
      expect(_matches(" ' - ", dragon), isTrue);
    });
  });

  group('StoryQuery.highlights', () {
    bool highlights(String query, String keyword) =>
        StoryQuery(query).highlights(keyword);

    test('an empty or whitespace-only query highlights nothing', () {
      expect(highlights('', 'drago'), isFalse);
      expect(highlights('   ', 'drago'), isFalse);
      expect(StoryQuery.empty.highlights('drago'), isFalse);
    });

    test('highlights a keyword a query word is a prefix of', () {
      expect(highlights('drago', 'drago'), isTrue);
      expect(highlights('drag', 'drago'), isTrue);
      expect(highlights('drago', 'castello'), isFalse);
    });

    test('ignores case and folds accents on both sides', () {
      expect(highlights('DRAGO', 'Drago'), isTrue);
      expect(highlights('citta', 'Città'), isTrue);
      expect(highlights('straße', 'strasse'), isTrue);
    });

    test('matches only at the start of a word of the keyword', () {
      expect(highlights('rago', 'drago'), isFalse);
      expect(highlights('fantasma', 'castello-fantasma'), isTrue);
      expect(highlights('isola', "l'isola"), isTrue);
    });

    test('a query word longer than the keyword does not highlight it', () {
      expect(highlights('draghi', 'drago'), isFalse);
    });

    test('any one query word is enough for a keyword', () {
      // The story needs every word (AND); each keyword shows which ones it
      // satisfies.
      expect(highlights('drago milano', 'drago'), isTrue);
      expect(highlights('drago milano', 'milano'), isTrue);
      expect(highlights('drago milano', 'castello'), isFalse);
    });

    test('follows the short-token rule', () {
      expect(highlights('il drago', 'isola'), isFalse);
      expect(highlights('il drago', 'drago'), isTrue);
      expect(highlights('re', 'regina'), isTrue);
    });

    test('agrees with matches for a story with one keyword', () {
      for (final query in ['drag', 'il drago', 'rago', 'citta', 're', '']) {
        for (final keyword in ['drago', 'Città', 'regina']) {
          final story = _story(keywords: [keyword]);
          final parsed = StoryQuery(query);
          if (parsed.isEmpty) continue;
          // With one query token, highlighting and matching coincide.
          if (parsed.tokens.length == 1) {
            expect(parsed.highlights(keyword), parsed.matches(story),
                reason: '"$query" vs "$keyword"');
          }
        }
      }
    });
  });

  group('StoryQuery.filter', () {
    final stories = [
      _story(id: 'c', title: 'Il drago di ghiaccio'),
      _story(id: 'a', title: 'Il faro', keywords: ['tempesta']),
      _story(id: 'd', keywords: ['drago', 'faro']),
      _story(id: 'b', title: 'Draghi e principesse'),
    ];

    List<String> ids(List<Story> list) => [for (final s in list) s.id];

    test('keeps the matching stories in the input order', () {
      expect(ids(StoryQuery('drag').filter(stories)), ['c', 'd', 'b']);
      expect(ids(StoryQuery('faro').filter(stories)), ['a', 'd']);
    });

    test('an empty query keeps every story in order', () {
      expect(ids(StoryQuery('').filter(stories)), ['c', 'a', 'd', 'b']);
    });

    test('no match gives an empty list', () {
      expect(StoryQuery('astronave').filter(stories), isEmpty);
    });
  });
}
