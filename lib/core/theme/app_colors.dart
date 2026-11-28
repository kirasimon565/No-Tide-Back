import 'package:flutter/material.dart';

/// NO TIDE BACK — "SLATE TERMINAL" palette.
///
/// Matches the Dreadmoor production OS language: a muted slate blue-grey base
/// (never pure black), steel panels instead of glassy cards, a single cyan
/// accent for anything interactive, and crimson reserved for danger / the
/// horror beats. Nothing is rounded to 16px — surfaces are cut, not inflated.
///
///   slateBackground  #1E252B   app canvas
///   slateSurface     #2A3239   panel / card
///   slateHeader      #161C21   chrome, headers, dock
///   investigatorCyan #00ACC1   interactive + selected
///   evidenceRed      #B71C1C   danger, horror, "media" tags
///   cautionYellow    #FBC02D   warnings, coins, unlock nags
abstract final class AppColors {
  // ---------------------------------------------------------------- surfaces
  /// App canvas. Deep slate, not black — the whole point of the redesign.
  static const Color bgVoid = slateBackground;

  /// Boot screen: near-black so the studio logo dissolves cleanly.
  static const Color bootBlack = Color(0xFF12171B);

  /// Phone chrome / status bar / dock.
  static const Color surfacePhone = slateHeader;

  /// Cards, panels, rows.
  static const Color surfaceCard = slateSurface;

  /// Pressed / elevated panel.
  static const Color surfaceElevated = Color(0xFF333D46);

  /// Inset well (log output, disabled fields).
  static const Color surfaceInset = Color(0xFF232B32);

  // ------------------------------------------------------------------- slate
  static const Color slateBackground = Color(0xFF1E252B);
  static const Color slateSurface = Color(0xFF2A3239);
  static const Color slateHeader = Color(0xFF161C21);
  static const Color slateBorder = Color(0xFF38434D);
  static const Color slateText = Color(0xFFE1E4E7);
  static const Color slateTextDim = Color(0xFF8F9BA3);

  // ----------------------------------------------------------------- accents
  /// Interactive accent: rules, borders, selected states, primary buttons.
  static const Color accentTide = Color(0xFF00ACC1);

  /// Danger: biometric alerts, signal lost, redacted tags, horror beats.
  static const Color accentCrimson = Color(0xFFB71C1C);

  /// Coins, locked premium content, caution tape.
  static const Color accentPremium = Color(0xFFFBC02D);

  /// Success / decryption confirmed.
  static const Color accentSuccess = Color(0xFF43A047);

  // -------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFFE1E4E7);
  static const Color textSecondary = Color(0xFFB3BCC3);
  static const Color textMuted = Color(0xFF7A868F);

  /// Hairline rules and borders. Panels use one-pixel steel edges, not shadows.
  static const Color divider = Color(0xFF38434D);

  /// Slightly brighter border for focused / selected panels.
  static const Color borderActive = Color(0xFF00ACC1);

  // --------------------------------------------------------------- chat tint
  static const Color bubbleIncoming = Color(0xFF262F36);
  static const Color bubbleOutgoing = Color(0xFF123C46);

  /// Per-character name tag colours used in group chats.
  static const Map<String, Color> characterAccents = <String, Color>{
    'abigail': Color(0xFFD98BA6),
    'beatrice': Color(0xFF9C8FD6),
    'jessica': Color(0xFF64B5D9),
    'maya': Color(0xFF7FA9D8),
    'kathy': Color(0xFFD9B36B),
    'kai': Color(0xFF6FBBAE),
    'mom': Color(0xFFC9969F),
    'sister': Color(0xFFD9C27A),
    'system': accentTide,
    'player': accentTide,
  };

  static Color forCharacter(String id) =>
      characterAccents[id.toLowerCase()] ?? textSecondary;
}
