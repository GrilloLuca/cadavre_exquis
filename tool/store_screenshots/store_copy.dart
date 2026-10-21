// Captions and sample content of the store screenshots, one StoreCopy per
// store language. Store copy, not app text: it isn't in the ARB files.
import 'package:cadavre_exquisite/domain/models/story.dart';

class Caption {
  const Caption(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class StoreCopy {
  StoreCopy({
    required this.appLocale,
    required this.iosLocale,
    required this.playLocale,
    required this.roomLanguage,
    required this.captionWrite,
    required this.captionPick,
    required this.captionRead,
    required this.captionArchive,
    required this.captionRooms,
    required this.featureTagline,
    required this.draft,
    required this.nicknames,
    required this.continueParts,
    required this.continueKeywords,
    required this.incompleteSamples,
    required this.completeSamples,
  });

  final String appLocale;
  final String iosLocale;
  final String playLocale;
  final String roomLanguage;

  final Caption captionWrite;
  final Caption captionPick;
  final Caption captionRead;
  final Caption captionArchive;
  final Caption captionRooms;

  /// Under the app name on Play's feature graphic.
  final String featureTagline;

  /// What the player is typing on the writing screen.
  final String draft;

  /// Nickname of every sample author, by email. [me] is the signed-in user.
  final Map<String, String> nicknames;

  static const me = 'giulia.writes@example.com';

  /// The two parts already written of the story on the writing screen.
  final List<String> continueParts;
  final List<String> continueKeywords;

  /// Last part (or null for a blank story) and who wrote it, newest first.
  final List<({String? lastPart, int written, String? author, bool locked})>
      incompleteSamples;

  /// Title and four parts of each complete story, newest first. The
  /// second one is the user's.
  final List<({String title, List<String> parts})> completeSamples;

  List<String> get _authors => nicknames.keys.where((e) => e != me).toList();

  DateTime _ago(Duration d) => DateTime.now().subtract(d);

  Story get storyToContinue => Story(
        id: 'continue',
        status: 'incomplete',
        currentPosition: kStoryPositions[continueParts.length],
        parts: [
          for (final (i, text) in continueParts.indexed)
            StoryPart(
              position: kStoryPositions[i],
              text: text,
              author: _authors[i],
              timestamp: _ago(Duration(
                  minutes: 12 + 90 * (continueParts.length - 1 - i))),
            ),
        ],
        language: roomLanguage,
        keywords: continueKeywords,
      );

  List<Story> get incompleteStories => [
        storyToContinue,
        for (final (i, sample) in incompleteSamples.indexed)
          Story(
            id: 'incomplete-$i',
            status: 'incomplete',
            currentPosition: kStoryPositions[sample.written],
            parts: [
              for (var p = 0; p < sample.written; p++)
                StoryPart(
                  position: kStoryPositions[p],
                  text: p == sample.written - 1
                      ? sample.lastPart!
                      : 'Lorem ipsum.',
                  author: p == sample.written - 1
                      ? sample.author!
                      : _authors[(i + p + 1) % _authors.length],
                  timestamp: _ago(Duration(hours: i + 1, minutes: 10 - p)),
                ),
            ],
            lockedBy: sample.locked ? _authors[(i + 3) % _authors.length] : null,
            lockedAt: sample.locked ? _ago(const Duration(minutes: 3)) : null,
            language: roomLanguage,
          ),
      ];

  List<Story> get completeStories => [
        for (final (i, sample) in completeSamples.indexed)
          Story(
            id: 'complete-$i',
            status: 'complete',
            currentPosition: kStoryPositions.last,
            title: sample.title,
            mature: false,
            parts: [
              for (final (p, text) in sample.parts.indexed)
                StoryPart(
                  position: kStoryPositions[p],
                  text: text,
                  author: i == 1 && p == 2
                      ? me
                      : _authors[(i + p) % _authors.length],
                  timestamp: _ago(Duration(hours: 5 * i + 4 - p)),
                ),
            ],
            language: roomLanguage,
          ),
      ];
}

final storeCopies = [
  StoreCopy(
    appLocale: 'it',
    iosLocale: 'it',
    playLocale: 'it-IT',
    roomLanguage: 'it',
    captionWrite: const Caption(
      'Vedi solo cinque parole',
      'Continua la storia di uno sconosciuto alla cieca',
    ),
    captionPick: const Caption(
      'Scegli una storia',
      'Inizia da una pagina bianca o continua quella di altri',
    ),
    captionRead: const Caption(
      'Scopri il finale',
      'Quattro autori, una storia che nessuno si aspettava',
    ),
    captionArchive: const Caption(
      'Un titolo per ogni storia',
      "L'IA dà un nome a ogni racconto completato",
    ),
    captionRooms: const Caption(
      'Gioca con i tuoi amici',
      'Stanze private e stanze in cinque lingue',
    ),
    featureTagline: 'Scrivi una storia con degli sconosciuti.\nVedi solo cinque parole.',
    draft: 'Il faro si spense, e dal buio arrivò una voce che conoscevo',
    nicknames: const {
      StoreCopy.me: 'Giulia',
      'marta@example.com': 'Marta',
      'tommaso@example.com': 'Tommi',
      'elena@example.com': 'Elena_B',
      'pietro@example.com': 'Pierino',
    },
    continueParts: const [
      "Ogni notte il guardiano del faro contava le navi che non arrivavano "
          "mai. Ne aveva un quaderno pieno, con nomi inventati e date "
          "sbagliate.",
      "Una sera, tra le pagine, trovò una nave che non aveva scritto lui: "
          "si chiamava Ritorno, e il suo arrivo era previsto per stanotte, "
          "all'ora esatta in cui la lanterna",
    ],
    continueKeywords: const ['faro', 'quaderno', 'navi', 'mistero'],
    incompleteSamples: const [
      (
        lastPart: 'e da quel giorno la nonna non aprì più la scatola blu',
        written: 1,
        author: 'elena@example.com',
        locked: false,
      ),
      (
        lastPart: null,
        written: 0,
        author: null,
        locked: false,
      ),
      (
        lastPart: 'Il gatto mi fissava come chi conosce un segreto',
        written: 2,
        author: 'tommaso@example.com',
        locked: true,
      ),
      (
        lastPart: 'nessuno in paese aveva mai visto piovere al contrario',
        written: 3,
        author: 'pietro@example.com',
        locked: false,
      ),
      (
        lastPart: 'e così firmai il contratto con la luna',
        written: 2,
        author: StoreCopy.me,
        locked: false,
      ),
      (
        lastPart: "la valigia era leggera, ma dentro c'era un'intera città",
        written: 1,
        author: 'marta@example.com',
        locked: false,
      ),
    ],
    completeSamples: const [
      (
        title: "L'orologiaio che rubava i minuti",
        parts: [
          "In via dei Mille c'era una bottega dove gli orologi andavano "
              "tutti indietro di un minuto. L'orologiaio diceva che era "
              "voluto, ma nessuno gli credeva.",
          "Di notte, infatti, raccoglieva quei minuti in un barattolo di "
              "vetro e li conservava in cantina, etichettati con il nome del "
              "proprietario, come marmellate.",
          "Quando il barattolo della signora Ines si riempì, lui lo aprì in "
              "piazza: per sessanta secondi tutti videro il mare che lei "
              "aveva sognato da bambina.",
          "Da allora in paese nessuno ripara più il proprio orologio. "
              "Ognuno aspetta, paziente, il proprio minuto di mare.",
        ],
      ),
      (
        title: 'La biblioteca dei libri mai scritti',
        parts: [
          "Al terzo piano della biblioteca c'era uno scaffale vuoto con "
              "un cartello: «Riservato ai libri che non avete avuto il "
              "coraggio di scrivere».",
          "Ogni volta che qualcuno rinunciava a un'idea, sullo scaffale "
              "compariva un volume nuovo, rilegato in blu, con il suo nome "
              "in copertina.",
          "Io trovai il mio in un martedì di pioggia: aveva trecento pagine, "
              "tutte bianche tranne l'ultima, dove c'era scritto «Allora?».",
          "Lo presi in prestito. Sono passati due anni e non l'ho ancora "
              "restituito: ogni sera ne riempio una pagina.",
        ],
      ),
      (
        title: 'Il ladro di ombre di Porta Nuova',
        parts: [
          "A Porta Nuova la gente cominciò a perdere l'ombra. Prima i "
              "pendolari, poi i turisti, infine anche il vigile all'incrocio.",
          "Le ombre ricomparvero tutte insieme, una mattina, sul muro della "
              "stazione: ballavano un valzer, e nessuna voleva tornare dal "
              "proprio padrone.",
          "Il sindaco provò a trattare, offrendo lampioni nuovi e "
              "pomeriggi di sole garantiti. Le ombre chiesero un giorno di "
              "festa tutto per loro.",
          "Così ogni ventuno dicembre, il giorno più corto, a Porta Nuova "
              "le persone restano a casa e le ombre escono a passeggio.",
        ],
      ),
      (
        title: 'Lettere al condominio',
        parts: [
          "Qualcuno lasciava biglietti nella cassetta delle lettere di "
              "tutto il condominio, firmati «Il Vicino del Quinto Piano».",
          "Il palazzo, però, aveva solo quattro piani.",
          "Una notte l'amministratore salì le scale con una torcia, e dopo "
              "il quarto piano trovò altri dodici gradini e una porta verde.",
          "Dietro c'era un uomo che annaffiava i gerani di tutti: «Qualcuno "
              "doveva pur farlo», disse, e offrì un caffè.",
        ],
      ),
    ],
  ),
  StoreCopy(
    appLocale: 'en',
    iosLocale: 'en-US',
    playLocale: 'en-US',
    roomLanguage: 'en',
    captionWrite: const Caption(
      'See only five words',
      "Continue a stranger's story, blind",
    ),
    captionPick: const Caption(
      'Pick a story',
      "Start from a blank page or continue someone else's",
    ),
    captionRead: const Caption(
      'Reveal the ending',
      'Four authors, one story nobody saw coming',
    ),
    captionArchive: const Caption(
      'Every story gets a title',
      'AI names each finished tale',
    ),
    captionRooms: const Caption(
      'Play with friends',
      'Private rooms and rooms in five languages',
    ),
    featureTagline: 'Write a story with strangers.\nSee only five words.',
    draft: 'The light went out, and from the dark came a voice I knew',
    nicknames: const {
      StoreCopy.me: 'Giulia',
      'marta@example.com': 'Marta',
      'tommaso@example.com': 'Tom',
      'elena@example.com': 'Ellie_B',
      'pietro@example.com': 'Pete',
    },
    continueParts: const [
      "Every night the lighthouse keeper counted the ships that never "
          "arrived. He kept a notebook full of them, with made-up names and "
          "wrong dates.",
      "One evening, between the pages, he found a ship he hadn't written "
          "down himself: it was called Homecoming, and it was due tonight, "
          "at the very hour the lantern",
    ],
    continueKeywords: const ['lighthouse', 'notebook', 'ships', 'mystery'],
    incompleteSamples: const [
      (
        lastPart: 'and from that day Grandma never opened the blue box',
        written: 1,
        author: 'elena@example.com',
        locked: false,
      ),
      (
        lastPart: null,
        written: 0,
        author: null,
        locked: false,
      ),
      (
        lastPart: 'The cat stared at me like it knew a secret',
        written: 2,
        author: 'tommaso@example.com',
        locked: true,
      ),
      (
        lastPart: 'nobody in town had ever seen rain fall upwards',
        written: 3,
        author: 'pietro@example.com',
        locked: false,
      ),
      (
        lastPart: 'and so I signed the contract with the moon',
        written: 2,
        author: StoreCopy.me,
        locked: false,
      ),
      (
        lastPart: 'the suitcase was light, but it held a whole city',
        written: 1,
        author: 'marta@example.com',
        locked: false,
      ),
    ],
    completeSamples: const [
      (
        title: 'The Watchmaker Who Stole Minutes',
        parts: [
          "On Mill Street there was a shop where every clock ran one minute "
              "slow. The watchmaker said it was on purpose, but nobody "
              "believed him.",
          "At night, in fact, he gathered those minutes in a glass jar and "
              "stored them in the cellar, each labelled with its owner's "
              "name, like jam.",
          "When Mrs Ivy's jar was full, he opened it in the square: for "
              "sixty seconds everyone saw the sea she had dreamed of as a "
              "child.",
          "Since then, nobody in town gets their watch fixed. Everyone "
              "waits, patiently, for their own minute of sea.",
        ],
      ),
      (
        title: 'The Library of Unwritten Books',
        parts: [
          "On the third floor of the library there was an empty shelf with "
              "a sign: \"Reserved for the books you didn't dare to write.\"",
          "Every time someone gave up on an idea, a new volume appeared on "
              "the shelf, bound in blue, with their name on the cover.",
          "I found mine on a rainy Tuesday: three hundred pages, all blank "
              "except the last one, which said \"Well?\"",
          "I checked it out. Two years later I still haven't returned it: "
              "every evening I fill in one more page.",
        ],
      ),
      (
        title: 'The Shadow Thief of North Gate',
        parts: [
          "At North Gate people started losing their shadows. Commuters "
              "first, then tourists, and finally even the traffic warden.",
          "The shadows reappeared all at once one morning, on the station "
              "wall: they were dancing a waltz, and none of them wanted to "
              "go home.",
          "The mayor tried to negotiate, offering new streetlights and "
              "guaranteed sunny afternoons. The shadows asked for a holiday "
              "of their own.",
          "So every December 21st, the shortest day, the people of North "
              "Gate stay indoors and the shadows go out for a stroll.",
        ],
      ),
      (
        title: 'Letters to the Building',
        parts: [
          "Someone was leaving notes in every mailbox of the building, "
              "signed \"Your Neighbour on the Fifth Floor\".",
          "The building, however, had only four floors.",
          "One night the caretaker climbed the stairs with a torch, and "
              "past the fourth floor he found twelve more steps and a green "
              "door.",
          "Behind it, a man was watering everyone's geraniums. \"Somebody "
              "had to,\" he said, and offered him a coffee.",
        ],
      ),
    ],
  ),
];
