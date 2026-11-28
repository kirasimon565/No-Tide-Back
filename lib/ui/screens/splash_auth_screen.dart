import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_store_provider.dart';
import '../widgets/common_widgets.dart';
import 'home_hub_screen.dart';

/// Screen 1 — Terminal handshake (splash, sign-in, offline entry).
///
/// Layout follows the Dreadmoor production OS: brand mark centred, one hero
/// action, console readout at the bottom, everything on slate with a single
/// cyan accent. No floating glass cards, no gradient buttons.
class SplashAuthScreen extends ConsumerStatefulWidget {
  const SplashAuthScreen({super.key});

  @override
  ConsumerState<SplashAuthScreen> createState() => _SplashAuthScreenState();
}

class _SplashAuthScreenState extends ConsumerState<SplashAuthScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  )..repeat(reverse: true);

  bool _busy = false;
  bool _autoRouted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoResumeSession());
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  Future<void> _autoResumeSession() async {
    if (_autoRouted) return;
    final bool signedIn = ref.read(economyProvider).isSignedIn;
    if (!signedIn) return;
    _autoRouted = true;
    await _enterHub();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Sign-in now succeeds even when Firestore is unreachable; the hub shows
    // CLOUD OFFLINE and the error sits in the readout.
    await ref.read(economyProvider.notifier).signIn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ref.read(economyProvider).isSignedIn) {
      await _enterHub();
    }
  }

  Future<void> _enterHub() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b) =>
            const HomeHubScreen(),
        transitionsBuilder: (
          BuildContext c,
          Animation<double> a,
          Animation<double> b,
          Widget child,
        ) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayerEconomyState economy = ref.watch(economyProvider);
    final bool signedIn = economy.isSignedIn;
    final bool reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: OceanBackdrop(
        intensity: 1,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _TopStrip(economy: economy),

              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        AnimatedBuilder(
                          animation: _breath,
                          builder: (BuildContext context, Widget? child) {
                            final double t = reduceMotion
                                ? 1
                                : 1 + math.sin(_breath.value * math.pi * 2) * 0.012;
                            return Transform.scale(scale: t, child: child);
                          },
                          child: _BrandMark(),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          AppConfig.appName.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: AppTypography.wordmark.copyWith(fontSize: 24),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Container(width: 18, height: 1, color: AppColors.divider),
                            const SizedBox(width: 10),
                            Text(
                              AppConfig.tagline,
                              style: AppTypography.labelDim.copyWith(
                                fontSize: 9,
                                color: AppColors.accentCrimson,
                                letterSpacing: 4.4,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(width: 18, height: 1, color: AppColors.divider),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Text(
                          'A friendship. A private island.\nOne message you cannot unsend.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.75,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  children: <Widget>[
                    _TerminalReadout(economy: economy),
                    const SizedBox(height: 14),
                    ConsoleButton(
                      label: signedIn ? 'SYNC MY RELAY' : 'CONTINUE WITH GOOGLE',
                      icon: Icons.login_rounded,
                      busy: _busy,
                      onPressed: _busy ? null : _signIn,
                    ),
                    const SizedBox(height: 10),
                    ConsoleButton(
                      label: 'PLAY OFFLINE',
                      icon: Icons.sensors_off_rounded,
                      height: 46,
                      onPressed: _busy ? null : _enterHub,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'BALANCES & SAVES FOLLOW YOUR GOOGLE UID',
                            style: AppTypography.labelDim.copyWith(fontSize: 7.5),
                          ),
                        ),
                        Text(
                          AppConfig.studioName.toUpperCase(),
                          style: AppTypography.labelDim.copyWith(fontSize: 7.5),
                        ),
                      ],
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

/// Relay status + version, top of screen.
class _TopStrip extends StatelessWidget {
  const _TopStrip({required this.economy});

  final PlayerEconomyState economy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        children: <Widget>[
          StatusPill(
            economy.isSignedIn ? 'SECURE RELAY' : 'UNSECURE RELAY',
            color: economy.isSignedIn ? AppColors.accentTide : AppColors.accentPremium,
            icon: economy.isSignedIn ? Icons.lock_rounded : Icons.lock_open_rounded,
          ),
          const Spacer(),
          Text('v1.0.0', style: AppTypography.labelDim.copyWith(fontSize: 8)),
        ],
      ),
    );
  }
}

/// The fingerprint disc. Drawn, not an asset — keeps the palette exact and the
/// APK small.
class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      height: 148,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.slateHeader,
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: const Size(148, 148),
            painter: _PrintPainter(),
          ),
          ClipOval(
            child: Image.asset(
              AssetCatalog.appIcon,
              width: 108,
              height: 108,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext c, Object e, StackTrace? s) => Icon(
                Icons.fingerprint_rounded,
                size: 56,
                color: AppColors.accentTide.withValues(alpha: 0.55),
              ),
            ),
          ),
          // Corner ticks — a HUD frame, not a stack of rounded icons.
          Positioned(top: 6, left: 6, child: _Tick(alignment: Alignment.topLeft)),
          Positioned(top: 6, right: 6, child: _Tick(alignment: Alignment.topRight)),
          Positioned(bottom: 6, left: 6, child: _Tick(alignment: Alignment.bottomLeft)),
          Positioned(bottom: 6, right: 6, child: _Tick(alignment: Alignment.bottomRight)),
        ],
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.alignment});
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final bool right = alignment.x > 0;
    final bool bottom = alignment.y > 0;
    return SizedBox(
      width: 12,
      height: 12,
      child: CustomPaint(
        painter: _CornerPainter(right: right, bottom: bottom),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.right, required this.bottom});
  final bool right;
  final bool bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = AppColors.accentTide.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final double x = right ? size.width : 0;
    final double y = bottom ? size.height : 0;
    canvas.drawLine(Offset(right ? 0 : size.width, y), Offset(x, y), p);
    canvas.drawLine(Offset(x, bottom ? 0 : size.height), Offset(x, y), p);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

/// Concentric print rings behind the icon disc.
class _PrintPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = AppColors.accentTide.withValues(alpha: 0.16);
    for (final double r in <double>[52, 62, 71]) {
      canvas.drawCircle(c, r, p);
    }
    // Dashed outer ring, drawn manually: no dashPathEffect in Flutter core.
    final Paint dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.accentCrimson.withValues(alpha: 0.28);
    for (int i = 0; i < 36; i += 2) {
      final double a0 = (i / 36) * math.pi * 2;
      final double a1 = ((i + 1) / 36) * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 72),
        a0,
        a1 - a0,
        false,
        dash,
      );
    }
  }

  @override
  bool shouldRepaint(_PrintPainter old) => false;
}

/// The bottom console plate: session state, identity, and the failure reason
/// in plain language.
class _TerminalReadout extends StatelessWidget {
  const _TerminalReadout({required this.economy});

  final PlayerEconomyState economy;

  @override
  Widget build(BuildContext context) {
    final bool signedIn = economy.isSignedIn;
    final String? error = economy.lastError;

    final String status = signedIn
        ? '> SESSION ACTIVE'
        : '> AWAITING HANDSHAKE';

    return SlatePanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      color: AppColors.slateHeader.withValues(alpha: 0.72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: signedIn
                      ? AppColors.accentTide
                      : (error != null ? AppColors.accentCrimson : AppColors.accentPremium),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: AppTypography.terminal.copyWith(
                  color: signedIn ? AppColors.accentTide : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (economy.isLoading)
                Text('LINKING…', style: AppTypography.labelDim.copyWith(fontSize: 8)),
            ],
          ),
          if (signedIn && economy.user?.email != null) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              economy.user!.email!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (error != null) ...<Widget>[
            const SizedBox(height: 9),
            Container(height: 1, color: AppColors.divider.withValues(alpha: 0.7)),
            const SizedBox(height: 9),
            Text(
              error,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 12,
                height: 1.5,
                color: AppColors.accentCrimson.withValues(alpha: 0.92),
              ),
            ),
          ],
          if (!signedIn && error == null) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              'Sign in to keep coins, purchases and saves on every device.\n'
              'Offline progress stays on this phone only.',
              style: AppTypography.bodySmall.copyWith(
                fontSize: 12,
                height: 1.55,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
