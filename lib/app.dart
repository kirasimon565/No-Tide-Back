import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_typography.dart';
import 'ui/screens/episode_end_screen.dart';
import 'ui/screens/splash_auth_screen.dart';
import 'ui/screens/studio_intro_screen.dart';
import 'ui/widgets/notification_banner.dart';
import 'ui/widgets/ntb_overlay_host.dart';

/// Root widget: studio boot → auth → hub, with a global observer that swaps to
/// the stinger screen when `@end_scene` resolves.
class NoTideBackApp extends ConsumerWidget {
  const NoTideBackApp({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'No Tide Back',
      debugShowCheckedModeBanner: false,
      theme: buildNoTideBackTheme(),
      navigatorKey: rootNavigatorKey,
      home: NtbOverlayHost(
        child: NotificationBannerHost(
          child: EpisodeEndScreenGate(
            child: _RootRouter(firebaseReady: firebaseReady),
          ),
        ),
      ),
      builder: (BuildContext context, Widget? child) {
        // Clamp text scaling so the chat layout never breaks.
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: DefaultTextStyle(
            style: AppTypography.body,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class _RootRouter extends ConsumerStatefulWidget {
  const _RootRouter({required this.firebaseReady});

  final bool firebaseReady;

  @override
  ConsumerState<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends ConsumerState<_RootRouter> {
  bool _introFinished = false;

  @override
  Widget build(BuildContext context) {
    if (!_introFinished) {
      return StudioIntroScreen(
        firebaseReady: widget.firebaseReady,
        onFinished: () => setState(() => _introFinished = true),
      );
    }
    return const SplashAuthScreen();
  }
}

ThemeData buildNoTideBackTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accentTide,
    brightness: Brightness.dark,
    surface: AppColors.surfacePhone,
    primary: AppColors.accentTide,
    error: AppColors.accentCrimson,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bgVoid,
    canvasColor: AppColors.bgVoid,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: AppTypography.inter,
    textTheme: AppTypography.textTheme(),
    dividerColor: AppColors.divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgVoid,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.sectionTitle,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfacePhone,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surfaceCard,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceCard,
      contentTextStyle: TextStyle(
        fontFamily: AppTypography.mono,
        fontSize: 12,
        color: AppColors.textPrimary,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accentTide,
      selectionColor: Color(0x3322D3EE),
      selectionHandleColor: AppColors.accentTide,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accentTide,
      linearTrackColor: AppColors.surfaceElevated,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentTide,
        foregroundColor: AppColors.bgVoid,
        textStyle: const TextStyle(
          fontFamily: AppTypography.mono,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        textStyle: const TextStyle(
          fontFamily: AppTypography.mono,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accentTide),
    ),
  );
}
