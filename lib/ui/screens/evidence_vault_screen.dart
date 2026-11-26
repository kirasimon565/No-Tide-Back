import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/evidence_item.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/chat_threads_provider.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_viewer_overlay.dart';
import '../widgets/store_modal_sheet.dart';

/// Screen 7 — Evidence Vault & Case Board.
class EvidenceVaultScreen extends ConsumerStatefulWidget {
  const EvidenceVaultScreen({super.key});

  @override
  ConsumerState<EvidenceVaultScreen> createState() => _EvidenceVaultScreenState();
}

class _EvidenceVaultScreenState extends ConsumerState<EvidenceVaultScreen> {
  bool _bonusOnly = false;

  @override
  Widget build(BuildContext context) {
    final List<EvidenceItem> items = ref.watch(evidenceProvider(_bonusOnly));
    final PlayerEconomyState economy = ref.watch(economyProvider);
    final List<EvidenceItem> all = ref.watch(evidenceProvider(false));

    return Scaffold(
      appBar: AppBar(
        title: Text('EVIDENCE VAULT', style: AppTypography.monoLabel.copyWith(fontSize: 12)),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: NtbTag(
                '${all.length} / ${AppConfig.evidenceGoal}',
                color: all.length >= AppConfig.evidenceGoal
                    ? AppColors.accentSuccess
                    : AppColors.accentTide,
                filled: true,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(
                children: <Widget>[
                  _FilterChip(
                    label: 'CASE BOARD',
                    selected: !_bonusOnly,
                    onTap: () => setState(() => _bonusOnly = false),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'MULTIMEDIA FILES',
                    selected: _bonusOnly,
                    accent: AppColors.accentPremium,
                    onTap: () => setState(() => _bonusOnly = true),
                  ),
                  const Spacer(),
                  if (!economy.multimediaUnlocked && _bonusOnly)
                    TextButton(
                      onPressed: () => showStoreModalSheet(context, focusMultimedia: true),
                      child: Text(
                        'UNLOCK',
                        style: AppTypography.monoCaption.copyWith(
                          fontSize: 9,
                          color: AppColors.accentPremium,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.folder_open_rounded,
                              size: 34,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _bonusOnly
                                  ? '> NO MULTIMEDIA FILES YET\nUnlock the package in the store, then play through each part.'
                                  : '> VAULT EMPTY\nClues appear here the moment you @add_evidence in a thread.',
                              textAlign: TextAlign.center,
                              style: AppTypography.monoCaption.copyWith(
                                height: 1.8,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: items.length,
                      itemBuilder: (BuildContext context, int index) => _EvidenceCard(
                        item: items[index],
                        onTap: () => showMediaViewer(
                          context,
                          imagePath: items[index].imagePath,
                          title: items[index].title,
                          description: items[index].description,
                          tag: items[index].tagLabel,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = AppColors.accentTide,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.13) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? accent : AppColors.divider),
        ),
        child: Text(
          label,
          style: AppTypography.monoCaption.copyWith(
            fontSize: 9,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: selected ? accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.item, required this.onTap});

  final EvidenceItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isMultimediaBonus
                  ? AppColors.accentPremium.withValues(alpha: 0.4)
                  : AppColors.divider,
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.asset(
                      item.imagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                          const ColoredBox(color: AppColors.surfaceElevated),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: NtbTag(
                        item.tagLabel,
                        color: item.isMultimediaBonus
                            ? AppColors.accentPremium
                            : AppColors.accentTide,
                        filled: true,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.monoBase.copyWith(
                        fontSize: 10.5,
                        height: 1.35,
                        letterSpacing: 0.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: 10.5,
                        height: 1.35,
                        color: AppColors.textMuted,
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
