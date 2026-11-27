import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ntb_interpreter.dart';
import '../models/evidence_item.dart';
import '../models/game_save_state.dart';
import '../services/isar_service.dart';
import 'game_state_provider.dart';

/// Everything Screen 9's waiting hub needs to render, resolved once.
class EpisodeWaitState {
  const EpisodeWaitState({
    required this.episodeCompleted,
    this.nextEpisodeNumber = 2,
    this.completedAt,
    this.evidenceCount = 0,
    this.evidenceGoal = 5,
    this.trust = const <String, int>{},
    this.variables = const <String, dynamic>{},
    this.achievements = const <String>[],
  });

  /// True once the Episode 1 stinger has been reached — either in this session
  /// (the `ending` from `@end_scene`) or from the stored `ep1_complete` save.
  final bool episodeCompleted;
  final int nextEpisodeNumber;
  final DateTime? completedAt;
  final int evidenceCount;
  final int evidenceGoal;
  final Map<String, int> trust;
  final Map<String, dynamic> variables;
  final List<String> achievements;

  int get evidencePercent {
    if (evidenceGoal <= 0) return 0;
    return ((evidenceCount / evidenceGoal) * 100).round().clamp(0, 100);
  }

  double get evidenceRatio {
    if (evidenceGoal <= 0) return 0;
    return (evidenceCount / evidenceGoal).clamp(0.0, 1.0);
  }

  /// 100% once every case-file slot is filled; otherwise the real percentage.
  int get completionPercent => episodeCompleted ? 100 : evidencePercent;

  bool get multimediaOwned => variables['multimedia_package_owned'] == true;

  String get evidenceLabel => '$evidenceCount/$evidenceGoal COLLECTED';

  /// Where the player left off, for the character cards ("at 01:03 AM").
  String get lastKnownTime =>
      variables['last_known_time']?.toString() ?? '01:03 AM';

  EpisodeWaitState copyWith({
    bool? episodeCompleted,
    int? nextEpisodeNumber,
    DateTime? completedAt,
    int? evidenceCount,
    int? evidenceGoal,
    Map<String, int>? trust,
    Map<String, dynamic>? variables,
    List<String>? achievements,
  }) {
    return EpisodeWaitState(
      episodeCompleted: episodeCompleted ?? this.episodeCompleted,
      nextEpisodeNumber: nextEpisodeNumber ?? this.nextEpisodeNumber,
      completedAt: completedAt ?? this.completedAt,
      evidenceCount: evidenceCount ?? this.evidenceCount,
      evidenceGoal: evidenceGoal ?? this.evidenceGoal,
      trust: trust ?? this.trust,
      variables: variables ?? this.variables,
      achievements: achievements ?? this.achievements,
    );
  }
}

/// Reads the completion state from (in order) the live `@end_scene` ending, the
/// in-memory save, then the persisted `ep1_complete` slot.
///
/// Deliberately synchronous: Screen 9 must paint its first frame immediately
/// after the stinger, and the mirror is already open by then.
class EpisodeWaitNotifier extends Notifier<EpisodeWaitState> {
  @override
  EpisodeWaitState build() {
    final GameScreenState game = ref.watch(gameStateProvider);
    final IsarService? db = IsarService.available;
    final GameSaveState? stored = db?.activeSave;

    final EpisodeEnding? ending = game.ending;
    final GameSaveState? live = game.save ?? stored;
    final GameSaveState? finished = db?.loadSave('ep1_complete');

    final bool completed = ending != null ||
        live?.achievements.contains('ach_ep1_clear') == true ||
        finished?.achievements.contains('ach_ep1_clear') == true;

    final Map<String, dynamic> variables = <String, dynamic>{
      ...?finished?.variables,
      ...?live?.variables,
    };

    final List<EvidenceItem> evidence =
        game.evidence.isNotEmpty ? game.evidence : (db?.loadEvidence() ?? const <EvidenceItem>[]);

    final Map<String, int> trust = <String, int>{
      for (final String character in <String>[
        'jessica',
        'beatrice',
        'abigail',
        'maya',
        'kathy',
        'kai',
      ])
        character: (ending?.trust[character]) ??
            (variables['trust_$character'] is num
                ? (variables['trust_$character'] as num).toInt()
                : 0),
    };

    return EpisodeWaitState(
      episodeCompleted: completed,
      nextEpisodeNumber: 2,
      completedAt: finished?.updatedAt ?? live?.updatedAt,
      evidenceCount: ending?.evidenceCount ?? evidence.length,
      evidenceGoal: 5,
      trust: trust,
      variables: variables,
      achievements: <String>{
        ...?finished?.achievements,
        ...?live?.achievements,
        ...?game.achievements,
      }.toList(growable: false),
    );
  }
}

final episodeWaitProvider =
    NotifierProvider<EpisodeWaitNotifier, EpisodeWaitState>(EpisodeWaitNotifier.new);

/// Read-only helper for the hub's Resume Relay card: true when the player has
/// finished Episode 1, so Resume Relay routes to the waiting hub instead of
/// dropping them back into the last scene.
final episodeCompletedProvider = Provider<bool>((Ref ref) {
  final GameScreenState game = ref.watch(gameStateProvider);
  if (game.ending != null) return true;
  if (game.save?.achievements.contains('ach_ep1_clear') == true) return true;
  final GameSaveState? finished = IsarService.available?.loadSave('ep1_complete');
  return finished?.achievements.contains('ach_ep1_clear') == true;
});
