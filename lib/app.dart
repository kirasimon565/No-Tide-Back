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
  ).copyWith(
    primary: AppColors.accentTide,
    onPrimary: AppColors.slateHeader,
    secondary: AppColors.accentTide,
    surface: AppColors.surfaceCard,
    onSurface: AppColors.textPrimary,
    error: AppColors.accentCrimson,
  );

  // Flat, square, hairline. One accent. No ripples, no elevation, no rounded
  // "app card" language — the UI is a terminal, not a dashboard.
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bgVoid,
    canvasColor: AppColors.bgVoid,
    fontFamily: AppTypography.inter,
    textTheme: AppTypography.textTheme(),
    dividerColor: AppColors.divider,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _FadeThroughBuilder(),
        TargetPlatform.iOS: _FadeThroughBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgVoid,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.label,
      iconTheme: IconThemeData(color: AppColors.textSecondary),
    ),
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfacePhone,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surfaceCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.divider, width: 0.8),
      ),
      titleTextStyle: AppTypography.label,
      contentTextStyle: AppTypography.bodySmall,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceCard,
      contentTextStyle: AppTypography.systemBanner,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.divider, width: 0.8),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accentTide,
      selectionColor: Color(0x3300ACC1),
      selectionHandleColor: AppColors.accentTide,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accentTide,
      linearTrackColor: AppColors.divider,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceCard.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      hintStyle: AppTypography.body.copyWith(color: AppColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: const BorderSide(color: AppColors.divider, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: const BorderSide(color: AppColors.divider, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: const BorderSide(color: AppColors.accentTide, width: 1),
      ),
    ),
  );
}

/// Hard cut between screens — an OS, not a slideshow.
class _FadeThroughBuilder extends PageTransitionsBuilder {
  const _FadeThroughBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
