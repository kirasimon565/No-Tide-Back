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
