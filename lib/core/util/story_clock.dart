/// The story's in-world clock.
///
/// Messages are stamped from the `@environment time="…"` blocks in the `.ntb`
/// script — five in part 1, two in each later part. That is far too coarse for
/// a messenger screen: every bubble between two anchors carried the *same*
/// timestamp, so the chat appeared frozen (a dozen messages all labelled
/// `03:15 PM`) and only jumped when the next DM or part began.
///
/// This advances the story clock between scripted anchors instead, so
/// consecutive bubbles read like a real conversation while every `@environment`
/// still resets the clock to its authored value.
abstract final class StoryClock {
  /// In-world time added per rendered message.
  ///
  /// A message is a beat of conversation, not an instant: two minutes keeps a
  /// 20-message exchange inside one hour, which matches how the anchors are
  /// spaced (07:42 → 08:55 for the first 350 lines of part 1).
  static const Duration perMessage = Duration(minutes: 2);

  /// Extra gap after a scene change or the start of a new conversation.
  static const Duration perScene = Duration(minutes: 5);

  /// Parses `07:42 AM` / `12:05 PM`. Returns null when the text is not a time,
  /// so a malformed script anchor cannot corrupt the clock.
  static DateTime? parse(String? text) {
    if (text == null) return null;
    final RegExpMatch? match =
        RegExp(r'^\s*(\d{1,2}):(\d{2})\s*([AaPp][Mm])\s*$').firstMatch(text);
    if (match == null) return null;

    int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);
    if (hour < 1 || hour > 12 || minute > 59) return null;

    final bool pm = match.group(3)!.toUpperCase() == 'PM';
    hour %= 12;
    if (pm) hour += 12;
    return DateTime(2026, 1, 1, hour, minute);
  }

  /// `03:17 PM`
  static String format(DateTime time) {
    final int hour24 = time.hour % 24;
    final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String suffix = hour24 < 12 ? 'AM' : 'PM';
    final String minute = time.minute.toString().padLeft(2, '0');
    return '${hour12.toString().padLeft(2, '0')}:$minute $suffix';
  }

  /// Advances [current] by one message. [sceneChanged] adds the scene gap.
  ///
  /// Midnight rolls over naturally; the script never states a date, so only the
  /// wall-clock reading matters.
  static String advance(
    String current, {
    Duration step = perMessage,
    bool sceneChanged = false,
  }) {
    final DateTime anchor = parse(current) ?? DateTime(2026, 1, 1, 8, 0);
    final DateTime next = anchor
        .add(step)
        .add(sceneChanged ? perScene : Duration.zero);
    return format(next);
  }
}
