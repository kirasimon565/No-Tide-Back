import 'package:flutter/material.dart';

/// Dark maritime psychological-thriller palette.
///
/// Everything in the game sits on OLED black so the simulated phone screen
/// reads as a slab of glass floating in the dark.
abstract final class AppColors {
  /// Deep ocean night — app background.
  static const Color bgVoid = Color(0xFF070B0E);

  /// Root boot screen (Screen 0). Pure black so the studio logo blends in.
  static const Color bootBlack = Color(0xFF000000);

  /// Main phone screen container.
  static const Color surfacePhone = Color(0xFF0D1318);

  /// Chat list cards, evidence cards, modals, drawers.
  static const Color surfaceCard = Color(0xFF141D24);

  /// Elevated card / pressed state.
  static const Color surfaceElevated = Color(0xFF1B2731);

  /// Incoming character messages.
  static const Color bubbleIncoming = Color(0xFF18232C);

  /// Player outgoing messages — deep sea cyan.
  static const Color bubbleOutgoing = Color(0xFF0F3D4C);

  /// Active signal, links, hacking grid highlights.
  static const Color accentTide = Color(0xFF22D3EE);

  /// Biometric wristband alerts, danger banners, signal lost.
  static const Color accentCrimson = Color(0xFFEF4444);

  /// Gold badge for the Multimedia Package / coin choices.
  static const Color accentPremium = Color(0xFFF59E0B);

  /// Success / decryption confirmed.
  static const Color accentSuccess = Color(0xFF34D399);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);

  static const Color divider = Color(0xFF1E2A33);

  /// Per-character name tag colours used in group chats.
  static const Map<String, Color> characterAccents = <String, Color>{
    'abigail': Color(0xFFF472B6),
    'beatrice': Color(0xFFA78BFA),
    'jessica': Color(0xFF38BDF8),
    'maya': Color(0xFF60A5FA),
    'kathy': Color(0xFFFBBF24),
    'kai': Color(0xFF2DD4BF),
    'mom': Color(0xFFFDA4AF),
    'sister': Color(0xFFFCD34D),
    'system': accentTide,
    'player': accentTide,
  };

  static Color forCharacter(String id) =>
      characterAccents[id.toLowerCase()] ?? textSecondary;
}
