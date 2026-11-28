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

/// Screen 8 — the relay store.
///
/// Opened from the hub, from a locked choice without enough coins, or from the
/// hacking tool's auto-decrypt.
///
/// Purchase pipeline (same for every rail):
///   1. `GameStore.buy(sku)` opens the store's own sheet (Xsolla Pay Station /
///      RevenueCat / Play). It returns only once that window is closed.
///   2. On success the entitlement is written to `players/{uid}` in Firestore
///      by `EconomyNotifier.purchase` → `applyPurchase` → `grantCoins` /
///      `grantMultimediaPackage`, which are transactional and idempotent on the
///      order id.
///   3. The panel then reports *where* the entitlement landed, so the player is
///      never left guessing whether it "saved".
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

enum _Phase { idle, opening, done, failed }

class _StoreModalSheetState extends ConsumerState<StoreModalSheet> {
  String? _busySku;
  _Phase _phase = _Phase.idle;
  String _status = '';
  String? _diagnostics;
  String? _message;
  bool _messageIsError = false;

  Future<void> _buy(String sku) async {
    if (_busySku != null) return;
    final EconomyNotifier notifier = ref.read(economyProvider.notifier);

    // Purchases are tied to the Google UID, because that is the document the
    // entitlement is written to. Say so before opening a payment window.
    if (!ref.read(economyProvider).isSignedIn) {
      setState(() {
        _busySku = null;
        _phase = _Phase.failed;
        _messageIsError = true;
        _message = 'Sign in with Google first — coins and the package are stored '
            'on your uid so they survive a reinstall.';
      });
      return;
    }

    setState(() {
      _busySku = sku;
      _phase = _Phase.opening;
      _message = null;
      _status = 'OPENING PAY STATION...';
    });

    final PurchaseResult result = await notifier.purchase(sku);

    if (!mounted) return;
    if (result.success) {
      setState(() {
        _phase = result.cloudSynced ? _Phase.done : _Phase.failed;
        _status = result.cloudSynced ? 'SAVED TO YOUR RELAY' : 'GRANTED LOCALLY';
        _messageIsError = !result.cloudSynced;
        _message = !result.cloudSynced
            // Payment cleared, cloud write did not. Say exactly that.
            ? (result.message ??
                'Payment cleared, but the cloud save failed. Use RESTORE to sync it.')
            : result.simulated
                ? 'Sandbox purchase applied (no live billing rail in this build).'
                : 'Payment confirmed — coins and entitlements are on players/{uid}.';
      });
      await notifier.refresh();
      if (mounted) setState(() => _busySku = null);
      return;
    }

    setState(() {
      _busySku = null;
      if (result.cancelled) {
        _phase = _Phase.idle;
        _messageIsError = false;
        _message = 'Payment window closed — nothing was charged.';
      } else {
        _phase = _Phase.failed;
        _messageIsError = true;
        _message = result.message ?? 'The payment did not complete.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlayerEconomyState economy = ref.watch(economyProvider);
    // Purchases are written to the signed-in uid, so the sheet blocks them
    // before a payment window opens, not after a charge.
    final bool signedIn = economy.isSignedIn;
    final GameStore store = ref.watch(gameStoreProvider);
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: widget.focusMultimedia ? 0.88 : 0.8,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfacePhone,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            border: Border(
              top: BorderSide(color: AppColors.divider.withValues(alpha: 0.9), width: 0.8),
            ),
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(18, 10, 18, 26 + bottomInset),
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color: AppColors.divider,
                ),
              ),

              // ------------------------------------------------------- header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('RELAY STORE', style: AppTypography.kicker),
                        const SizedBox(height: 8),
                        Text(
                          'SPEND ONCE.\nKEEP IT FOREVER.',
                          style: AppTypography.displayTitle.copyWith(fontSize: 20, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _BalanceStrip(
                coins: economy.coins,
                signedIn: signedIn,
                syncing: economy.isSyncing,
              ),
              if (!signedIn) ...<Widget>[
                const SizedBox(height: 10),
                const _Notice(
                  tone: _Tone.danger,
                  text: 'Not signed in. Coins and the package are stored on your Google '
                      'uid so they survive a reinstall — sign in from the hub first.',
                ),
              ],
              if (widget.missingCoins != null) ...<Widget>[
                const SizedBox(height: 12),
                _Notice(
                  tone: _Tone.danger,
                  text: 'This choice needs ${widget.missingCoins} more coins. Owning the '
                      'Multimedia Package makes every premium choice free instead.',
                ),
              ],
              const SizedBox(height: 20),

              // --------------------------------------------- featured package
              _PackagePanel(
                owned: economy.multimediaUnlocked,
                busy: _busySku == StoreSkus.multimediaPack,
                disabled: _busySku != null || !signedIn,
                onBuy: () => _buy(StoreSkus.multimediaPack),
              ),
              const SizedBox(height: 24),

              RuleLabel('COIN PACKS'),
              ...StoreSkus.coinPacks.map(
                (CoinPack pack) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CoinPackCard(
                    pack: pack,
                    busy: _busySku == pack.sku,
                    disabled: _busySku != null || !signedIn,
                    onBuy: () => _buy(pack.sku),
                  ),
                ),
              ),

              if (_busySku != null) ...<Widget>[
                const SizedBox(height: 14),
                _PaymentProgress(status: _status),
              ],
              if (_message != null && _busySku == null) ...<Widget>[
                const SizedBox(height: 14),
                _PurchaseResult(
                  phase: _phase,
                  message: _message!,
                  isError: _messageIsError,
                  storeLabel: store.storeType.label,
                ),
              ],

              const SizedBox(height: 10),
              // Diagnostic: asks the native bridge what Xsolla actually returns
              // for each catalogue type. The answer is what a bug report needs.
              ConsoleButton(
                label: 'Check Xsolla catalogue',
                icon: Icons.bug_report_outlined,
                height: 42,
                onPressed: () async {
                  setState(() => _diagnostics = 'QUERYING...');
                  final Map<String, dynamic>? report =
                      await store.probeXsollaCatalogue(StoreSkus.coins100);
                  if (!mounted) return;
                  if (report == null) {
                    setState(() => _diagnostics =
                        'No Xsolla bridge in this build (or it refused to answer).');
                    return;
                  }
                  final Map<String, dynamic> skus =
                      (report['skus'] as Map?)?.cast<String, dynamic>() ??
                          <String, dynamic>{};
                  final String? hint = report['hint'] as String?;
                  final int? loginStatus = report['loginStatus'] as int?;
                  setState(() {
                    _diagnostics = <String>[
                      if (hint != null) '>>> $hint',
                      'PROJECT ${report['projectId']} • SDK ${report['sdkBundled']} '
                          '• CONNECTED ${report['connected']}',
                      'LOGIN ${report['loginId']}',
                      for (final MapEntry<String, dynamic> e in skus.entries)
                        '${e.key}: ${e.value}',
                      if (loginStatus != null) ...<String>[
                        'DEVICE SIGN-IN ${loginStatus < 0 ? 'FAILED' : 'HTTP $loginStatus'}',
                        'DEVICE ${report['device']}',
                        'DEVICE ID ${report['deviceId']}',
                        'BODY ${report['loginBody']}',
                      ],
                    ].join('\n');
                  });
                },
              ),

              const SizedBox(height: 10),
              ConsoleButton(
                label: 'Restore purchases',
                icon: Icons.restore_rounded,
                height: 46,
                onPressed: () async {
                  final bool ok = await ref.read(economyProvider.notifier).restore();
                  if (!mounted) return;
                  setState(() {
                    _messageIsError = !ok;
                    _phase = ok ? _Phase.done : _Phase.failed;
                    _message = ok
                        ? 'Entitlements restored from your account.'
                        : 'Nothing to restore on this account yet.';
                  });
                },
              ),

              if (_diagnostics != null) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    border: Border.all(color: AppColors.divider, width: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: SelectableText(
                    _diagnostics!,
                    style: AppTypography.monoCaption.copyWith(
                      fontSize: 8.5,
                      height: 1.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],

              if (kDebugMode) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed: () => ref
                            .read(economyProvider.notifier)
                            .devGrant(StoreSkus.multimediaPack),
                        child: Text(
                          'DEV: GRANT PACK',
                          style: AppTypography.labelDim.copyWith(fontSize: 8),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () =>
                            ref.read(economyProvider.notifier).devGrant(StoreSkus.coins500),
                        child: Text(
                          'DEV: +500 COINS',
                          style: AppTypography.labelDim.copyWith(fontSize: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 18),
              Container(height: 1, color: AppColors.divider.withValues(alpha: 0.7)),
              const SizedBox(height: 14),
              Text(
                economy.isSignedIn
                    ? 'BALANCES LIVE ON YOUR GOOGLE UID IN CLOUD FIRESTORE\n'
                        'PLAYERS/{UID} • RESTORES AUTOMATICALLY ON ANY DEVICE'
                    : 'NOT SIGNED IN • COINS STAY ON THIS DEVICE ONLY',
                style: AppTypography.labelDim.copyWith(fontSize: 7, height: 2.1),
              ),
              const SizedBox(height: 8),
              // The rail comes from the install source, so this line tells the
              // player (and support) which project a payment would bill through.
              Text(
                'RAIL: ${store.storeType.label.toUpperCase()}',
                style: AppTypography.labelDim.copyWith(
                  fontSize: 7,
                  color: store.hasConfiguredRail
                      ? AppColors.textMuted
                      : AppColors.accentPremium,
                ),
              ),
              if (!store.hasConfiguredRail) ...<Widget>[
                const SizedBox(height: 6),
                const _Notice(
                  tone: _Tone.danger,
                  text: 'No payment method is configured for this store build. '
                      'Install from Google Play, the Galaxy Store or the Amazon '
                      'Appstore to buy coins.',
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

enum _Tone { info, danger, success }

/// Coin balance + account state, top of the sheet.
class _BalanceStrip extends StatelessWidget {
  const _BalanceStrip({
    required this.coins,
    required this.signedIn,
    this.syncing = false,
  });

  final int coins;
  final bool signedIn;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: 0.55),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.9), width: 0.7),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.monetization_on_outlined,
            size: 15,
            color: AppColors.accentPremium,
          ),
          const SizedBox(width: 8),
          Text(
            '$coins',
            style: AppTypography.label.copyWith(
              fontSize: 13,
              color: AppColors.accentPremium,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 6),
          Text('COINS', style: AppTypography.labelDim.copyWith(fontSize: 7)),
          const Spacer(),
          if (syncing) ...<Widget>[
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.4),
            ),
            const SizedBox(width: 8),
          ],
          StatusPill(
            signedIn ? 'CLOUD LINKED' : 'OFFLINE',
            color: signedIn ? AppColors.accentTide : AppColors.accentPremium,
            icon: signedIn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (tone) {
      _Tone.danger => AppColors.accentCrimson,
      _Tone.success => AppColors.accentSuccess,
      _Tone.info => AppColors.accentTide,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.7),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            tone == _Tone.success ? Icons.check_circle_outline : Icons.info_outline_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 12,
                height: 1.5,
                color: tone == _Tone.danger ? color : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Multimedia Package panel — the only "featured" surface in the app.
class _PackagePanel extends StatelessWidget {
  const _PackagePanel({
    required this.owned,
    required this.busy,
    required this.disabled,
    required this.onBuy,
  });

  final bool owned;
  final bool busy;
  final bool disabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final Color accent = owned ? AppColors.accentSuccess : AppColors.accentPremium;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 0.9),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(height: 2, color: accent.withValues(alpha: 0.8)),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 4),
            child: Row(
              children: <Widget>[
                Icon(Icons.workspace_premium_outlined, color: accent, size: 17),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'THE MULTIMEDIA PACKAGE',
                    style: AppTypography.label.copyWith(fontSize: 10, color: accent),
                  ),
                ),
                if (owned)
                  StatusPill('OWNED', color: AppColors.accentSuccess, filled: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 6, 15, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _Perk('Every premium dialogue choice, in every episode, free.'),
                const _Perk('Unlimited auto-decrypt boosts in the Hacking Tool.'),
                const _Perk('20+ bonus evidence files and 20+ private DMs per episode.'),
                const _Perk('Two-way unlock: gated scenes open automatically.'),
                const SizedBox(height: 12),
                ConsoleButton(
                  label: owned ? 'Owned permanently' : 'Unlock permanently',
                  icon: owned ? Icons.check_rounded : Icons.lock_open_rounded,
                  busy: busy,
                  height: 50,
                  danger: false,
                  onPressed: owned || disabled ? null : onBuy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentPremium,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 12.5,
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

/// One coin pack row.
///
/// The tag sits with the headline instead of taking its own column: three
/// columns in a 390 dp sheet squeezed the blurb into "Unlock / every /
/// premium / choice / across / a full / episode." over six lines.
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
    final bool featured = pack.tag == 'MOST POPULAR';
    final Color accent = featured ? AppColors.accentTide : AppColors.divider;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: featured ? 1 : 0.6),
        border: Border.all(
          color: featured ? accent.withValues(alpha: 0.6) : accent,
          width: featured ? 0.9 : 0.7,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        '${pack.coins} COINS',
                        style: AppTypography.label.copyWith(
                          fontSize: 12.5,
                          color: AppColors.accentPremium,
                          letterSpacing: 1.1,
                        ),
                      ),
                      if (pack.tag.isNotEmpty)
                        StatusPill(
                          pack.tag,
                          color: featured ? AppColors.accentTide : AppColors.textMuted,
                          filled: featured,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pack.blurb,
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 11.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 84,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ConsoleButton(
                label: 'BUY',
                busy: busy,
                height: 40,
                onPressed: disabled ? null : onBuy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while the payment window is open: tells the player what is happening
/// instead of leaving a dead button.
class _PaymentProgress extends StatelessWidget {
  const _PaymentProgress({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.accentTide.withValues(alpha: 0.07),
        border: Border.all(color: AppColors.accentTide.withValues(alpha: 0.4), width: 0.7),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              status.isEmpty ? 'OPENING PAY STATION...' : status,
              style: AppTypography.labelDim.copyWith(
                fontSize: 8,
                color: AppColors.accentTide,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Terminal-style outcome panel: what happened and where it landed.
class _PurchaseResult extends StatelessWidget {
  const _PurchaseResult({
    required this.phase,
    required this.message,
    required this.isError,
    required this.storeLabel,
  });

  final _Phase phase;
  final String message;
  final bool isError;
  final String storeLabel;

  @override
  Widget build(BuildContext context) {
    final bool success = phase == _Phase.done && !isError;
    final bool cancelled = phase == _Phase.idle && !isError;
    final Color color = success
        ? AppColors.accentSuccess
        : (isError ? AppColors.accentCrimson : AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.7),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                success
                    ? Icons.check_circle_outline
                    : cancelled
                        ? Icons.remove_circle_outline
                        : Icons.error_outline_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success
                      ? 'SAVED TO YOUR RELAY'
                      : cancelled
                          ? 'CANCELLED'
                          : 'NOT SAVED TO THE CLOUD',
                  style: AppTypography.label.copyWith(fontSize: 9, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.bodySmall.copyWith(
              fontSize: 12,
              height: 1.5,
              color: success ? AppColors.textPrimary : color,
            ),
          ),
          if (success) ...<Widget>[
            const SizedBox(height: 8),
            Container(height: 1, color: color.withValues(alpha: 0.25)),
            const SizedBox(height: 8),
            Text(
              'CLOUD FIRESTORE • PLAYERS/{UID} • VIA $storeLabel'.toUpperCase(),
              style: AppTypography.labelDim.copyWith(fontSize: 7, color: color),
            ),
          ],
        ],
      ),
    );
  }
}
