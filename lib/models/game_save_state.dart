import 'package:flutter/foundation.dart';

/// Local snapshot mirroring Firestore `players/{uid}/activeSave`.
///
/// The same object is serialised into Firestore, so the JSON keys must stay in
/// sync with the cloud schema in the design document.
@immutable
class GameSaveState {
  const GameSaveState({
    this.slotId = 'active',
    this.episodeNumber = 1,
    this.partNumber = 1,
    this.currentSceneLabel = 'ep1_start',
    this.instructionPointerIndex = 0,
    this.environmentTime = '07:42 AM',
    this.environmentLocation = 'Home - Bedroom',
    this.environmentWeather = 'Clear',
    this.variables = const <String, dynamic>{},
    this.unlockedEvidenceIds = const <String>[],
    this.readMessageIds = const <String>[],
    this.lastMessageId,
    this.updatedAt,
    this.lastSyncedAt,
    this.achievements = const <String>[],
  });

  final String slotId;
  final int episodeNumber;
  final int partNumber;
  final String currentSceneLabel;
  final int instructionPointerIndex;
  final String environmentTime;
  final String environmentLocation;
  final String environmentWeather;

  /// trust_*, suspicion, stress and every boolean flag set by the script.
  final Map<String, dynamic> variables;
  final List<String> unlockedEvidenceIds;
  final List<String> readMessageIds;
  final String? lastMessageId;
  final DateTime? updatedAt;
  final DateTime? lastSyncedAt;
  final List<String> achievements;

  int get evidenceCount => unlockedEvidenceIds.length;

  int trust(String character) {
    final Object? value = variables['trust_$character'];
    return value is num ? value.toInt() : 0;
  }

  /// Human readable resume label used on the Home Hub resume card.
  String get label => 'Ep $episodeNumber • Part $partNumber • $environmentTime';

  GameSaveState copyWith({
    String? slotId,
    int? episodeNumber,
    int? partNumber,
    String? currentSceneLabel,
    int? instructionPointerIndex,
    String? environmentTime,
    String? environmentLocation,
    String? environmentWeather,
    Map<String, dynamic>? variables,
    List<String>? unlockedEvidenceIds,
    List<String>? readMessageIds,
    String? lastMessageId,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
    List<String>? achievements,
  }) =>
      GameSaveState(
        slotId: slotId ?? this.slotId,
        episodeNumber: episodeNumber ?? this.episodeNumber,
        partNumber: partNumber ?? this.partNumber,
        currentSceneLabel: currentSceneLabel ?? this.currentSceneLabel,
        instructionPointerIndex: instructionPointerIndex ?? this.instructionPointerIndex,
        environmentTime: environmentTime ?? this.environmentTime,
        environmentLocation: environmentLocation ?? this.environmentLocation,
        environmentWeather: environmentWeather ?? this.environmentWeather,
        variables: variables ?? this.variables,
        unlockedEvidenceIds: unlockedEvidenceIds ?? this.unlockedEvidenceIds,
        readMessageIds: readMessageIds ?? this.readMessageIds,
        lastMessageId: lastMessageId ?? this.lastMessageId,
        updatedAt: updatedAt ?? this.updatedAt,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        achievements: achievements ?? this.achievements,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'slotId': slotId,
        'episode': episodeNumber,
        'part': partNumber,
        'currentLabel': currentSceneLabel,
        'instructionPointerIndex': instructionPointerIndex,
        'environmentTime': environmentTime,
        'environmentLocation': environmentLocation,
        'environmentWeather': environmentWeather,
        'variables': variables,
        'unlockedEvidenceIds': unlockedEvidenceIds,
        'readMessageIds': readMessageIds,
        'lastMessageId': lastMessageId,
        'updatedAt': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'achievements': achievements,
      };

  factory GameSaveState.fromJson(Map<String, dynamic> json) => GameSaveState(
        slotId: (json['slotId'] as String?) ?? 'active',
        episodeNumber: (json['episode'] as num?)?.toInt() ?? 1,
        partNumber: (json['part'] as num?)?.toInt() ?? 1,
        currentSceneLabel: (json['currentLabel'] as String?) ?? 'ep1_start',
        instructionPointerIndex:
            (json['instructionPointerIndex'] as num?)?.toInt() ?? 0,
        environmentTime: (json['environmentTime'] as String?) ?? '07:42 AM',
        environmentLocation:
            (json['environmentLocation'] as String?) ?? 'Home - Bedroom',
        environmentWeather: (json['environmentWeather'] as String?) ?? 'Clear',
        variables: Map<String, dynamic>.from(
          (json['variables'] as Map?) ?? const <String, dynamic>{},
        ),
        unlockedEvidenceIds: List<String>.from(
          (json['unlockedEvidenceIds'] as List?) ?? const <String>[],
        ),
        readMessageIds: List<String>.from(
          (json['readMessageIds'] as List?) ?? const <String>[],
        ),
        lastMessageId: json['lastMessageId'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        achievements: List<String>.from(
          (json['achievements'] as List?) ?? const <String>[],
        ),
      );

  static const GameSaveState fresh = GameSaveState(
    variables: <String, dynamic>{
      'trust_jessica': 5,
      'trust_abigail': 7,
      'trust_beatrice': 6,
      'trust_maya': 7,
      'trust_kathy': 3,
      'trust_kai': 4,
      'home_safe': true,
      'evidence_count': 0,
      'maya_photo_clue': false,
      'sister_suspicious': false,
      'suspicion': 0,
      'stress': 0,
      'multimedia_package_owned': false,
      'kathy_trust_up': false,
      'kai_trust_up': false,
    },
  );
}

/// A named slot shown in the Saves & Chapters modal.
@immutable
class SaveSlotInfo {
  const SaveSlotInfo({
    required this.slotId,
    required this.title,
    required this.subtitle,
    this.save,
  });

  final String slotId;
  final String title;
  final String subtitle;
  final GameSaveState? save;

  bool get isUsed => save != null;
}
