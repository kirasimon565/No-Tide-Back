import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// `@vibration` and biometric wristband feedback.
class HapticsService {
  const HapticsService();

  Future<void> vibrate(String pattern) async {
    switch (pattern.toLowerCase()) {
      case 'long':
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 140));
        await HapticFeedback.heavyImpact();
        return;
      case 'double':
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 110));
        await HapticFeedback.mediumImpact();
        return;
      case 'error' || 'alert':
        await HapticFeedback.vibrate();
        return;
      case 'light':
        await HapticFeedback.selectionClick();
        return;
      case 'short':
      default:
        try {
          await HapticFeedback.mediumImpact();
        } catch (error) {
          debugPrint('HapticsService.vibrate: $error');
        }
    }
  }

  /// Wristband red-alert pulse used by the inbox status bar.
  Future<void> wristbandAlert() async {
    for (int i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }
}
