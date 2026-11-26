import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Inter for the phone UI, JetBrains Mono for anything forensic.
abstract final class AppTypography {
  /// Font family names (for ThemeData / fontFamily overrides).
  static const String inter = 'Inter';
  static const String mono = 'JetBrainsMono';

  /// Base monospace style. `AppTypography.mono` is a family name, so UI code
  /// that needs a style starts from [monoBase] (or one of the styles below).
  static const TextStyle monoBase = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    color: AppColors.textPrimary,
    letterSpacing: 0.3,
  );

  /// Chat message body.
  static const TextStyle body = TextStyle(
    fontFamily: inter,
    fontSize: 15.5,
    height: 1.34,
    color: AppColors.textPrimary,
    letterSpacing: 0.05,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: inter,
    fontSize: 13.5,
    height: 1.32,
    color: AppColors.textSecondary,
  );

  /// Sender names, thread titles.
  static const TextStyle label = TextStyle(
    fontFamily: inter,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const TextStyle title = TextStyle(
    fontFamily: inter,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: inter,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// Timestamps, status readouts, terminal logs.
  static const TextStyle monoCaption = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    color: AppColors.textMuted,
    letterSpacing: 0.8,
  );

  static const TextStyle monoBody = TextStyle(
    fontFamily: mono,
    fontSize: 12.5,
    color: AppColors.textSecondary,
    height: 1.45,
    letterSpacing: 0.4,
  );

  static const TextStyle monoLabel = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.accentTide,
    letterSpacing: 1.6,
  );

  /// "NO TIDE BACK" wordmark.
  static const TextStyle wordmark = TextStyle(
    fontFamily: mono,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 6,
    height: 1.05,
  );

  static const TextStyle systemBanner = TextStyle(
    fontFamily: mono,
    fontSize: 11.5,
    color: AppColors.textSecondary,
    letterSpacing: 0.6,
    height: 1.3,
  );

  /// Private reflection — italicised, quieter than a sent message.
  static const TextStyle thought = TextStyle(
    fontFamily: inter,
    fontSize: 14.5,
    fontStyle: FontStyle.italic,
    height: 1.4,
    color: AppColors.textSecondary,
    letterSpacing: 0.1,
  );

  static TextTheme textTheme() => const TextTheme(
        titleLarge: title,
        titleMedium: sectionTitle,
        bodyMedium: body,
        bodySmall: bodySmall,
        labelLarge: label,
      );
}
