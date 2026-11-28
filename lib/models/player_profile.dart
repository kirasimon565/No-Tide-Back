import 'package:flutter/foundation.dart';

/// Pronouns resolved from the player's chosen gender.
enum PlayerGender {
  male,
  female,
  neutral;

  static PlayerGender fromId(String? id) => switch ((id ?? '').toLowerCase()) {
        'male' || 'm' || 'he' => PlayerGender.male,
        'female' || 'f' || 'she' => PlayerGender.female,
        _ => PlayerGender.neutral,
      };

  String get pronounThey => switch (this) {
        PlayerGender.male => 'he',
        PlayerGender.female => 'she',
        PlayerGender.neutral => 'they',
      };

  String get pronounThem => switch (this) {
        PlayerGender.male => 'him',
        PlayerGender.female => 'her',
        PlayerGender.neutral => 'them',
      };

  String get pronounTheir => switch (this) {
        PlayerGender.male => 'his',
        PlayerGender.female => 'hers',
        PlayerGender.neutral => 'their',
      };

  /// {bro_sis} — the affectionate tag the island crew uses.
  String get broSis => switch (this) {
        PlayerGender.male => 'bro',
        PlayerGender.female => 'sis',
        PlayerGender.neutral => 'sib',
      };

  String get label => switch (this) {
        PlayerGender.male => 'Male',
        PlayerGender.female => 'Female',
        PlayerGender.neutral => 'Neutral',
      };

  String get pronounSummary => '$pronounThey / $pronounThem / $pronounTheir';
}

@immutable
class PlayerProfile {
  const PlayerProfile({
    this.playerName = 'Player',
    this.gender = PlayerGender.neutral,
    this.avatarIndex = 0,
  });

  final String playerName;
  final PlayerGender gender;
  final int avatarIndex;

  /// Map injected into the .ntb interpreter for `{token}` interpolation.
  Map<String, String> get interpolationTokens => <String, String>{
        'player_name': playerName,
        'player_gender': gender.name,
        'they': gender.pronounThey,
        'them': gender.pronounThem,
        'their': gender.pronounTheir,
        'bro_sis': gender.broSis,
      };

  PlayerProfile copyWith({
    String? playerName,
    PlayerGender? gender,
    int? avatarIndex,
  }) =>
      PlayerProfile(
        playerName: playerName ?? this.playerName,
        gender: gender ?? this.gender,
        avatarIndex: avatarIndex ?? this.avatarIndex,
      );

  /// Firestore shape: players/{uid}/profile (also mirrored on the parent doc).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'playerName': playerName,
        'playerGender': gender.name,
        'they': gender.pronounThey,
        'them': gender.pronounThem,
        'their': gender.pronounTheir,
        'broSis': gender.broSis,
        'avatarIndex': avatarIndex,
      };

  factory PlayerProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PlayerProfile();
    return PlayerProfile(
      playerName: (json['playerName'] as String?) ?? 'Player',
      gender: PlayerGender.fromId(json['playerGender'] as String?),
      avatarIndex: (json['avatarIndex'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerProfile &&
      other.playerName == playerName &&
      other.gender == gender &&
      other.avatarIndex == avatarIndex;

  @override
  int get hashCode => Object.hash(playerName, gender, avatarIndex);
}
