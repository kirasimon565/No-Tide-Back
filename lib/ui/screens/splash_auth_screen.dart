import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_store_provider.dart';
import '../../providers/game_state_provider.dart';
import '../../services/game_store.dart';
import '../widgets/common_widgets.dart';
import 'home_hub_screen.dart';

/// Screen 1 — Splash & Google Sign-In.
///
/// Signs in through Firebase, creates players/{uid} when missing, restores the
/// cloud save into the local mirror and routes to the Home Hub. A returning
/// session skips the tap entirely.
class SplashAuthScreen extends ConsumerStatefulWidget {
  const SplashAuthScreen({super.key});

  @override
  ConsumerState<SplashAuthScreen> createState() => _SplashAuthScreenState();
}

class _SplashAuthScreenState extends ConsumerState<SplashAuthScreen> {
  bool _busy = false;
  bool _autoRouted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoResumeSession());
  }

  Future<void> _autoResumeSession() async {
    if (_autoRouted) return;
    final GameStore store = ref.read(gameStoreProvider);
    if (store.currentUser == null) return;
    _autoRouted = true;
    await _enterHub(silent: true);
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await ref.read(economyProvider.notifier).signIn();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = ref.read(economyProvider).lastError;
      });
      return;
    }
    await _enterHub();
  }

  /// Offline path: the game is fully playable without an account, cloud sync
  /// simply stays dark (the hub shows CLOUD OFFLINE).
  Future<void> _continueOffline() async {
    await _enterHub();
  }

  Future<void> _enterHub({bool silent = false}) async {
    if (!silent) {
      setState(() => _busy = true);
    }
    try {
      await ref.read(gameStateProvider.notifier).autosaveNow();
    } catch (_) {
      // Local-only session: nothing to sync.
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary) =>
            const HomeHubScreen(),
        transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayerEconomyState economy = ref.watch(economyProvider);

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: OceanBackdrop(
        intensity: 1.15,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    NtbTag(
                      economy.isSignedIn ? 'SECURE RELAY' : 'UNSECURE RELAY',
                      color: economy.isSignedIn ? AppColors.accentTide : AppColors.accentPremium,
                      icon: economy.isSignedIn ? Icons.lock_rounded : Icons.lock_open_rounded,
                    ),
                    const Spacer(),
                    Text('v1.0.0', style: AppTypography.monoCaption),
                  ],
                ),
                const Spacer(),
                // Title block
                Center(
                  child: Column(
                    children: <Widget>[
                      Image.asset(
                        AssetCatalog.appIcon,
                        width: 132,
                        height: 132,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'NO TIDE BACK',
                        textAlign: TextAlign.center,
                        style: AppTypography.wordmark.copyWith(
                          fontSize: 30,
                          letterSpacing: 5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        AppConfig.tagline,
                        style: AppTypography.monoCaption.copyWith(
                          letterSpacing: 6,
                          color: AppColors.accentCrimson.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'A friendship. A private island.\nOne message you cannot unsend.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Status readout
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfacePhone.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        economy.isSignedIn
                            ? '> SESSION RESTORED'
                            : '> ESTABLISHING SECURE RELAY...',
                        style: AppTypography.monoCaption.copyWith(
                          color: AppColors.accentTide,
                        ),
                      ),
                      if (economy.isSignedIn) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          economy.user?.email ?? 'player',
                          style: AppTypography.monoCaption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          '> ${_error!.toUpperCase()}',
                          style: AppTypography.monoCaption.copyWith(
                            color: AppColors.accentCrimson,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _GoogleButton(
                  busy: _busy,
                  label: economy.isSignedIn ? 'SYNC MY RELAY' : 'CONTINUE WITH GOOGLE',
                  onPressed: _busy ? null : _signIn,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _continueOffline,
                  child: Text(
                    'PLAY OFFLINE',
                    style: AppTypography.monoCaption.copyWith(
                      letterSpacing: 2.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Balances & saves are tied to your Google UID\nand restore on any device.',
                    textAlign: TextAlign.center,
                    style: AppTypography.monoCaption.copyWith(height: 1.7),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    AppConfig.studioName.toUpperCase(),
                    style: AppTypography.monoCaption.copyWith(letterSpacing: 4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White/dark-glass "Continue with Google" button with the official G mark.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.label, this.onPressed});

  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1F2937)),
                    ),
                  )
                else
                  CustomPaint(
                    size: const Size(18, 18),
                    painter: _GoogleGlyphPainter(),
                  ),
                const SizedBox(width: 12),
                Text(
                  busy ? 'CONTACTING RELAY...' : label,
                  style: const TextStyle(
                    fontFamily: AppTypography.inter,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Google "G" drawn with its four brand colours (no external asset needed).
class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = size.width * 0.26;
    final Rect rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Blue (right + top-right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.35, 1.15, false, paint);
    // Green (bottom-right)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.8, 0.95, false, paint);
    // Yellow (bottom-left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 1.75, 0.95, false, paint);
    // Red (top-left)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 2.7, 1.0, false, paint);

    // The horizontal bar of the G
    paint
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = stroke * 0.92;
    canvas.drawLine(
      Offset(size.width * 0.52, size.height * 0.52),
      Offset(size.width * 0.98, size.height * 0.52),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GoogleGlyphPainter oldDelegate) => false;
}
