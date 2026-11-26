import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/store_skus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_store_provider.dart';
import '../../services/game_store.dart';
import 'common_widgets.dart';

/// Screen 8 — Store & Multimedia Package sheet.
///
/// Opened from the hub, from a locked choice without enough coins, or from the
/// hacking tool's auto-decrypt. Every purchase goes through [GameStore.buy] and
/// is applied to `players/{uid}` in Cloud Firestore.
Future<void> showStoreModalSheet(
  BuildContext context, {
  bool focusMultimedia = false,
  int? missingCoins,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => StoreModalSheet(
      focusMultimedia: focusMultimedia,
      missingCoins: missingCoins,
    ),
  );
}

class StoreModalSheet extends ConsumerStatefulWidget {
  const StoreModalSheet({this.focusMultimedia = false, this.missingCoins, super.key});

  final bool focusMultimedia;
  final int? missingCoins;

  @override
  ConsumerState<StoreModalSheet> createState() => _StoreModalSheetState();
}

class _StoreModalSheetState extends ConsumerState<StoreModalSheet> {
  String? _busySku;
  String? _message;
  bool _messageIsError = false;

  Future<void> _buy(String sku) async {
    if (_busySku != null) return;
    setState(() {
      _busySku = sku;
      _message = null;
    });

    final EconomyNotifier notifier = ref.read(economyProvider.notifier);
    final PurchaseResult result = await notifier.purchase(sku);

    if (!mounted) return;
    setState(() {
      _busySku = null;
      if (result.success) {
        _messageIsError = false;
        _message = result.simulated
            ? '> SANDBOX GRANT APPLIED (no billing rail configured)'
            : '> TRANSACTION CONFIRMED • ${result.transactionId ?? ''}';
      } else if (result.cancelled) {
        _messageIsError = false;
        _message = '> PURCHASE CANCELLED';
      } else {
        _messageIsError = true;
        _message = '> ${(result.message ?? 'PURCHASE FAILED').toUpperCase()}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlayerEconomyState economy = ref.watch(economyProvider);
    final GameStore store = ref.watch(gameStoreProvider);
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: widget.focusMultimedia ? 0.86 : 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surfacePhone,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(18, 12, 18, 24 + bottomInset),
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  const SectionHeading(kicker: 'RELAY STORE', title: 'Unlock the rest of the story'),
                  const Spacer(),
                  NtbTag(
                    '🪙 ${economy.coins}',
                    color: AppColors.accentPremium,
                    filled: true,
                  ),
                ],
              ),
              if (widget.missingCoins != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accentCrimson.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.accentCrimson.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'This choice needs ${widget.missingCoins} coins. '
                    'Top up, or own the Multimedia Package to make every premium '
                    'choice and decryption boost free — forever.',
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 11.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // ---------------------------------------------- featured package
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0x1AF59E0B), Color(0x05F59E0B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accentPremium, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.workspace_premium_rounded,
                            color: AppColors.accentPremium, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'THE MULTIMEDIA PACKAGE',
                            style: AppTypography.mono.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                              color: AppColors.accentPremium,
                            ),
                          ),
                        ),
                        if (economy.multimediaUnlocked)
                          NtbTag('OWNED ✓', color: AppColors.accentSuccess, filled: true),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _Perk(
                      text: 'Unlock ALL premium dialogue choices across all episodes without spending coins.',
                    ),
                    const _Perk(
                      text: 'Unlimited auto-decrypt boosts in the Hacking Tool.',
                    ),
                    const _Perk(
                      text: '20+ bonus evidence files and 20+ exclusive private DMs per episode.',
                    ),
                    const _Perk(
                      text: 'Two-way unlock: every @choice_locked and pack-gated scene opens automatically.',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: economy.multimediaUnlocked
                          ? OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('OWNED PERMANENTLY'),
                            )
                          : FilledButton.icon(
                              onPressed: _busySku == null
                                  ? () => _buy(StoreSkus.multimediaPack)
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accentPremium,
                                foregroundColor: AppColors.bgVoid,
                                minimumSize: const Size.fromHeight(52),
                              ),
                              icon: _busySku == StoreSkus.multimediaPack
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.bgVoid,
                                      ),
                                    )
                                  : const Icon(Icons.lock_open_rounded, size: 18),
                              label: const Text('UNLOCK PERMANENTLY'),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              Text('COIN PACKS', style: AppTypography.monoLabel),
              const SizedBox(height: 10),
              ...StoreSkus.coinPacks.map(
                (CoinPack pack) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CoinPackCard(
                    pack: pack,
                    busy: _busySku == pack.sku,
                    disabled: _busySku != null,
                    onBuy: () => _buy(pack.sku),
                  ),
                ),
              ),

              if (_message != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _message!,
                  style: AppTypography.monoCaption.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 0.8,
                    color: _messageIsError
                        ? AppColors.accentCrimson
                        : AppColors.accentSuccess,
                  ),
                ),
              ],

              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final bool ok =
                            await ref.read(economyProvider.notifier).restore();
                        if (!mounted) return;
                        setState(() {
                          _messageIsError = !ok;
                          _message = ok
                              ? '> PURCHASES RESTORED'
                              : '> NOTHING TO RESTORE FOR THIS ACCOUNT';
                        });
                      },
                      icon: const Icon(Icons.restore_rounded, size: 17),
                      label: const Text('RESTORE'),
                    ),
                  ),
                ],
              ),

              if (kDebugMode) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed: () => ref.read(economyProvider.notifier).devGrant(StoreSkus.multimediaPack),
                        child: Text(
                          'DEV: GRANT PACK',
                          style: AppTypography.monoCaption.copyWith(fontSize: 9),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => ref.read(economyProvider.notifier).devGrant(StoreSkus.coins500),
                        child: Text(
                          'DEV: +500 COINS',
                          style: AppTypography.monoCaption.copyWith(fontSize: 9),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              Text(
                'All balances and entitlements are tied to your Google UID in Cloud Firestore '
                '(players/{uid}) and restore automatically after a reinstall or on a new device.\n'
                'Billing rail: ${store.storeType.label}'
                '${store.uid == null ? ' • sign in required' : ''}',
                style: AppTypography.monoCaption.copyWith(fontSize: 9, height: 1.7),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle_rounded, size: 13, color: AppColors.accentPremium),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinPackCard extends StatelessWidget {
  const _CoinPackCard({
    required this.pack,
    required this.busy,
    required this.disabled,
    required this.onBuy,
  });

  final CoinPack pack;
  final bool busy;
  final bool disabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final bool popular = pack.tag == 'MOST POPULAR';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: popular
              ? AppColors.accentTide.withValues(alpha: 0.6)
              : AppColors.divider,
          width: popular ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentPremium.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.accentPremium.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.monetization_on_rounded,
                size: 20, color: AppColors.accentPremium),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '${pack.coins} COINS',
                      style: AppTypography.mono.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    NtbTag(
                      pack.tag,
                      color: popular ? AppColors.accentTide : AppColors.textSecondary,
                      filled: popular,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  pack.blurb,
                  style: AppTypography.bodySmall.copyWith(fontSize: 10.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: disabled ? null : onBuy,
              style: FilledButton.styleFrom(
                minimumSize: const Size(74, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: AppTypography.mono.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.bgVoid,
                      ),
                    )
                  : const Text('BUY'),
            ),
          ),
        ],
      ),
    );
  }
}
