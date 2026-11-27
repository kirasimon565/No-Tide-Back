/// App-wide identity + episode metadata.
abstract final class AppConfig {
  static const String appName = 'No Tide Back';
  static const String studioName = 'EyesWatching Games';
  static const String packageName = 'com.eyeswatchinggames.no_tide_back';
  static const String tagline = 'HORROR STORY';

  static const String episodeTitle = 'Episode 1: The Contract';
  static const String nextEpisodeTitle = 'Episode 2: Side Effects';

  static const int totalEpisodes = 5;
  static const int evidenceGoal = 5;

  /// Character trust bars shown on the episode end screen.
  static const List<String> trustCharacters = <String>[
    'jessica',
    'beatrice',
    'abigail',
    'maya',
    'kathy',
    'kai',
  ];

  static const Map<String, String> characterNames = <String, String>{
    'jessica': 'Jessica',
    'beatrice': 'Beatrice',
    'abigail': 'Abigail',
    'maya': 'Maya',
    'kathy': 'Kathy',
    'kai': 'Captain Kai',
  };

  /// Trust scale for the end-of-episode bars.
  static const int maxTrust = 12;
}

/// Firestore field names — single source of truth for the cloud schema.
abstract final class FirestoreFields {
  static const String coins = 'coins';
  static const String multimediaUnlocked = 'multimediaUnlocked';
  static const String profile = 'profile';
  static const String activeSave = 'activeSave';
  static const String saves = 'saves';
  static const String achievements = 'achievements';
  static const String updatedAt = 'updatedAt';
  static const String createdAt = 'createdAt';
  static const String hasSeenIntro = 'hasSeenIntro';
}

/// Screen 9 (waiting hub) content: where each character was left at the end of
/// Episode 1, and which thread their last conversation lives in.
///
/// Kept in one place so Episode 2 can replace it without touching the UI.
class CharacterStatus {
  const CharacterStatus({
    required this.characterId,
    required this.names,
    required this.location,
    required this.condition,
    required this.signal,
    this.threadId,
    this.isLocked = true,
  });

  /// Matches the `character=` ids in the scripts (`kai`, `mom`, ...).
  final String characterId;

  /// Grouped cast that shares a location (e.g. the three locked in Suite A-2).
  final String names;

  /// Where they were left.
  final String location;

  /// One short line of state, e.g. `SIGNAL LOST`.
  final String condition;

  /// Signal glyph shown on the card: `lost`, `severed`, `unreachable`,
  /// `standing_by`, `safe`.
  final String signal;

  /// Thread that still holds their Episode 1 conversation, if any.
  final String? threadId;

  /// True when the player cannot reach them (drives the crimson treatment).
  final bool isLocked;

  String get initial => names.substring(0, 1).toUpperCase();
}

abstract final class EpisodeWaitConfig {
  /// In-story time the episode ended on.
  static const String lastKnownTime = '01:03 AM';
  static const String lastKnownCoordinates = '50 MILES OFFSHORE';

  static const String relayBanner = 'SECTOR FOUR RELAY: OFFLINE';
  static const String relayBannerDetail = 'AWAITING SIGNAL RESTORATION';

  /// Studio follow link used by the waiting hub.
  static const String studioFollowUrl = 'https://linktr.ee/eyeswatchinggames';

  static const List<CharacterStatus> lastKnownStatus = <CharacterStatus>[
    CharacterStatus(
      characterId: 'beatrice',
      names: 'Beatrice · Abigail · Maya',
      location: 'LOCKED IN SUITE A-2',
      condition: 'SIGNAL LOST',
      signal: 'lost',
      threadId: 'group_island',
    ),
    CharacterStatus(
      characterId: 'jessica',
      names: 'Jessica',
      location: 'SUB-LEVEL B',
      condition: 'CONNECTION SEVERED',
      signal: 'severed',
      threadId: 'dm_jessica',
    ),
    CharacterStatus(
      characterId: 'kathy',
      names: 'Kathy',
      location: 'SUB-LEVEL B ELEVATOR',
      condition: 'UNREACHABLE',
      signal: 'unreachable',
      threadId: 'dm_kathy',
    ),
    CharacterStatus(
      characterId: 'kai',
      names: 'Captain Kai',
      location: 'ANCHORED OFF SOUTH COVE',
      condition: 'STANDING BY',
      signal: 'standing_by',
      threadId: 'dm_kai',
      isLocked: false,
    ),
    CharacterStatus(
      characterId: 'mom',
      names: 'Mom & Chloe',
      location: 'SAFE AT HOME',
      condition: 'UNAWARE',
      signal: 'safe',
      threadId: 'dm_mom',
      isLocked: false,
    ),
  ];
}
