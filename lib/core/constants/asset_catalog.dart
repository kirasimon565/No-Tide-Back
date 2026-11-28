/// Maps the bare file names used inside the `.ntb` scripts to their real
/// location inside the Flutter asset bundle.
///
/// The scripts were authored before the assets were organised, so every
/// reference is a bare name (`img_maya_pier_selfie.jpg`, `hack_success.mp3`,
/// ...). Resolution is by prefix so new files of the same family work without
/// touching this table.
abstract final class AssetCatalog {
  static const String characterDir = 'assets/images/characters';
  static const String evidenceDir = 'assets/images/evidence';
  static const String documentDir = 'assets/images/documents';
  static const String videoDir = 'assets/video';
  static const String bgmDir = 'assets/audio/bgm';
  static const String sfxDir = 'assets/audio/sfx';
  static const String voiceDir = 'assets/audio/voice';

  static const String studioLogo = 'assets/images/branding/studio_logo.png';
  static const String appIcon = 'assets/images/branding/app_icon.png';
  static const String titleBackground = 'assets/images/title/bg_title_screen.png';
  static const String chatBackground = 'assets/images/chat/bg_chat_dark.png';
  static const String hackingBackground = 'assets/images/hacking/bg_hacking_grid.png';
  static const String redAlertOverlay = 'assets/images/overlays/overlay_red_alert.png';
  static const String vhsOverlay = 'assets/images/overlays/overlay_vhs_static.png';

  /// Resolve a script file reference to a bundled asset path.
  static String resolve(String file) {
    if (file.isEmpty) return '';
    if (file.startsWith('assets/')) return file;

    final String name = file.split('/').last;
    final String lower = name.toLowerCase();

    if (lower.startsWith('avatar_')) return '$characterDir/$name';
    if (lower.startsWith('doc_')) return '$documentDir/$name';
    if (lower.startsWith('img_')) return '$evidenceDir/$name';
    if (lower.startsWith('bgm_')) return '$bgmDir/$name';

    if (lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv')) {
      return '$videoDir/$name';
    }
    if (lower.startsWith('aud_') || lower.endsWith('.ogg') || lower.endsWith('.m4a')) {
      return '$voiceDir/$name';
    }
    if (lower.startsWith('bg_gi') || lower.startsWith('bg_chat')) return chatBackground;
    if (lower.startsWith('bg_hacking')) return hackingBackground;
    if (lower.startsWith('overlay_')) return 'assets/images/overlays/$name';
    if (lower.endsWith('.mp3') || lower.endsWith('.wav')) return '$sfxDir/$name';

    return 'assets/images/$name';
  }

  /// Audio helper used by the sound service (@sound / @music).
  static String audio(String file) => resolve(file);

  static String avatar(String characterId) {
    final String id = characterId.toLowerCase();
    const List<String> known = <String>[
      'abigail',
      'beatrice',
      'jessica',
      'kai',
      'kathy',
      'maya',
      'mom',
      'sister',
    ];
    return known.contains(id) ? '$characterDir/avatar_$id.png' : appIcon;
  }
}
