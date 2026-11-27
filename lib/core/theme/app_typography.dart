import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography for the "slate terminal" redesign.
///
/// Two voices, matching the Dreadmoor production OS:
///   • **Michroma** — the console voice. Labels, buttons, headers, titles.
///     Wide, geometric, uppercase, always letter-spaced.
///   • **Inter** — the human voice. Chat bodies, prose, form input.
///
/// Both are bundled (no runtime font download): a horror game must render its
/// UI on a plane with no wifi.
abstract final class AppTypography {
  /// Console / display family.
  static const String display = 'Michroma';

  /// Prose family.
  static const String inter = 'Inter';

  /// Legacy alias — the forensic mono voice is now the console family.
  static const String mono = display;

  // ------------------------------------------------------------------- tokens
  static const double _labelSize = 11;
  static const double _microSize = 9;

  // ------------------------------------------------------------------- family
  static const TextStyle displayBase = TextStyle(
    fontFamily: display,
    fontSize: 13,
    color: AppColors.textPrimary,
    letterSpacing: 1.6,
  );

  /// Section / screen kicker: "EPISODE SELECT", "WHO ARE YOU".
  static const TextStyle kicker = TextStyle(
    fontFamily: display,
    fontSize: _labelSize,
    color: AppColors.accentTide,
    letterSpacing: 2.4,
    height: 1.2,
  );

  /// Screen title in the console voice.
  static const TextStyle displayTitle = TextStyle(
    fontFamily: display,
    fontSize: 26,
    color: AppColors.textPrimary,
    letterSpacing: 1.4,
    height: 1.25,
  );

  /// Small all-caps console label (form field labels, dock labels).
  static const TextStyle label = TextStyle(
    fontFamily: display,
    fontSize: _labelSize,
    color: AppColors.textSecondary,
    letterSpacing: 2.0,
    height: 1.2,
  );

  /// The same label, dimmed, for secondary metadata.
  static const TextStyle labelDim = TextStyle(
    fontFamily: display,
    fontSize: _microSize,
    color: AppColors.textMuted,
    letterSpacing: 1.8,
    height: 1.2,
  );

  /// Button lettering.
  static const TextStyle button = TextStyle(
    fontFamily: display,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 2.6,
    height: 1.1,
  );

  /// "NO TIDE BACK" wordmark.
  static const TextStyle wordmark = TextStyle(
    fontFamily: display,
    fontSize: 26,
    color: AppColors.textPrimary,
    letterSpacing: 4.5,
    height: 1.2,
  );

  // --------------------------------------------------------------------- body
  static const TextStyle body = TextStyle(
    fontFamily: inter,
    fontSize: 15,
    height: 1.42,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: inter,
    fontSize: 13,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  /// Chat thread titles / card headings in the human voice.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: inter,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0,
  );

  static const TextStyle title = TextStyle(
    fontFamily: display,
    fontSize: 20,
    color: AppColors.textPrimary,
    letterSpacing: 1.2,
    height: 1.3,
  );

  /// Legacy aliases kept so screens that predate the redesign still compile.
  static const TextStyle monoBase = displayBase;
  static const TextStyle monoCaption = labelDim;
  static const TextStyle monoBody = TextStyle(
    fontFamily: display,
    fontSize: 10,
    color: AppColors.textSecondary,
    letterSpacing: 1.4,
    height: 1.8,
  );
  static const TextStyle monoLabel = kicker;

  /// Terminal readout: cyan console text on the inset well.
  static const TextStyle terminal = TextStyle(
    fontFamily: display,
    fontSize: 10,
    color: AppColors.accentTide,
    letterSpacing: 1.6,
    height: 1.9,
  );

  static const TextStyle systemBanner = TextStyle(
    fontFamily: display,
    fontSize: 9,
    color: AppColors.textSecondary,
    letterSpacing: 1.6,
    height: 1.4,
  );

  /// Private reflection — italicised, quieter than a sent message.
  static const TextStyle thought = TextStyle(
    fontFamily: inter,
    fontSize: 14,
    fontStyle: FontStyle.italic,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  static TextTheme textTheme() => const TextTheme(
        headlineLarge: displayTitle,
        titleLarge: title,
        titleMedium: sectionTitle,
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: bodySmall,
        labelLarge: label,
      );
}
