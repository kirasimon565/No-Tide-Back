import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/ntb_ast_node.dart';
import '../../providers/auth_store_provider.dart';

/// Bottom drawer that renders `@choice`, `@reply`, `@choice_if` and
/// `@choice_locked` options.
///
/// Premium options show either
///   ★ MULTIMEDIA PACK — FREE   (multimediaUnlocked == true)
///   🪙 {cost} COINS            (needs coins / store)
class ChoiceDrawer extends StatelessWidget {
  const ChoiceDrawer({
    required this.options,
    required this.economy,
    required this.onSelected,
    this.busyChoiceId,
    super.key,
  });

  final List<NtbNode> options;
  final PlayerEconomyState economy;
  final ValueChanged<NtbNode> onSelected;
  final String? busyChoiceId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfacePhone,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 4,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.accentTide,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CHOOSE YOUR REPLY',
                    style: AppTypography.monoLabel.copyWith(fontSize: 10.5),
                  ),
                  const Spacer(),
                  if (economy.multimediaUnlocked)
                    Text(
                      '★ PACK ACTIVE',
                      style: AppTypography.monoCaption.copyWith(
                        color: AppColors.accentPremium,
                        fontSize: 9,
                      ),
                    )
                  else
                    Text(
                      '🪙 ${economy.coins}',
                      style: AppTypography.monoCaption.copyWith(
                        color: AppColors.accentPremium,
                        fontSize: 9.5,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ...options.map(
                (NtbNode option) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ChoiceButton(
                    option: option,
                    economy: economy,
                    busy: busyChoiceId == option.param('id'),
                    onTap: () => onSelected(option),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.option,
    required this.economy,
    required this.onTap,
    this.busy = false,
  });

  final NtbNode option;
  final PlayerEconomyState economy;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool locked = option.name == 'choice_locked';
    final int cost = option.intParam('cost', 10);
    final bool freeWithPack = locked && economy.multimediaUnlocked;
    final bool affordable = locked && !economy.multimediaUnlocked && economy.coins >= cost;
    final String rawText = option.param('text');
    final String text = rawText.replaceFirst(
      RegExp(r'^\s*\[[^\]]*\]\s*'),
      '',
    );

    final Color accent = !locked
        ? AppColors.accentTide
        : freeWithPack
            ? AppColors.accentPremium
            : AppColors.accentPremium;

    return Material(
      color: locked
          ? AppColors.accentPremium.withValues(alpha: 0.07)
          : AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: locked
                  ? AppColors.accentPremium.withValues(alpha: 0.45)
                  : AppColors.divider,
              width: locked ? 1.1 : 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                locked
                    ? (freeWithPack ? Icons.star_rounded : Icons.lock_rounded)
                    : Icons.subdirectory_arrow_right_rounded,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (locked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accentPremium.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                freeWithPack
                                    ? '★ MULTIMEDIA PACK — FREE'
                                    : '🪙 $cost COINS',
                                style: AppTypography.monoCaption.copyWith(
                                  fontSize: 8.5,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accentPremium,
                                ),
                              ),
                            ),
                            if (!freeWithPack && !affordable) ...<Widget>[
                              const SizedBox(width: 6),
                              Text(
                                'SHORT ON COINS',
                                style: AppTypography.monoCaption.copyWith(
                                  fontSize: 7.5,
                                  color: AppColors.accentCrimson,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    Text(
                      text,
                      style: AppTypography.body.copyWith(
                        fontSize: 14,
                        color: locked && !freeWithPack
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
