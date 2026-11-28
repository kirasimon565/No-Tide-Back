import 'package:flutter/foundation.dart';

import '../core/constants/asset_catalog.dart';

/// A clue from `@add_evidence` (or a Multimedia Package file note).
@immutable
class EvidenceItem {
  const EvidenceItem({
    required this.evidenceId,
    required this.episodeNumber,
    required this.title,
    required this.description,
    required this.unlockedAt,
    this.imageAsset,
    this.sourceCharacter,
    this.isMultimediaBonus = false,
    this.caseNumber = 0,
  });

  final String evidenceId;
  final int episodeNumber;
  final String title;
  final String description;
  final DateTime unlockedAt;

  /// Bare script file name; resolved through [AssetCatalog].
  final String? imageAsset;
  final String? sourceCharacter;
  final bool isMultimediaBonus;

  /// Display tag: `EVIDENCE #01`, `FILE NOTE`.
  final int caseNumber;

  String get imagePath =>
      imageAsset == null ? AssetCatalog.vhsOverlay : AssetCatalog.resolve(imageAsset!);

  String get tagLabel =>
      isMultimediaBonus ? 'FILE NOTE' : 'EVIDENCE #${caseNumber.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'evidenceId': evidenceId,
        'episodeNumber': episodeNumber,
        'title': title,
        'description': description,
        'unlockedAt': unlockedAt.toIso8601String(),
        'imageAsset': imageAsset,
        'sourceCharacter': sourceCharacter,
        'isMultimediaBonus': isMultimediaBonus,
        'caseNumber': caseNumber,
      };

  factory EvidenceItem.fromJson(Map<String, dynamic> json) => EvidenceItem(
        evidenceId: json['evidenceId'] as String,
        episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 1,
        title: (json['title'] as String?) ?? 'Untitled',
        description: (json['description'] as String?) ?? '',
        unlockedAt: DateTime.tryParse(json['unlockedAt'] as String? ?? '') ?? DateTime.now(),
        imageAsset: json['imageAsset'] as String?,
        sourceCharacter: json['sourceCharacter'] as String?,
        isMultimediaBonus: (json['isMultimediaBonus'] as bool?) ?? false,
        caseNumber: (json['caseNumber'] as num?)?.toInt() ?? 0,
      );
}
