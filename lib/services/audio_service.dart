import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/asset_catalog.dart';

/// Music bed + one-shot SFX. Asset paths come from [AssetCatalog] so script
/// references (`hack_success.mp3`) resolve to their bundled location.
class AudioService {
  AudioService();

  final AudioPlayer _music = AudioPlayer(playerId: 'ntb.music')
    ..setReleaseMode(ReleaseMode.loop);

  final List<AudioPlayer> _sfxPool = <AudioPlayer>[
    AudioPlayer(playerId: 'ntb.sfx.0'),
    AudioPlayer(playerId: 'ntb.sfx.1'),
    AudioPlayer(playerId: 'ntb.sfx.2'),
  ];
  int _sfxCursor = 0;

  String? _currentMusicFile;
  bool _muted = false;

  bool get isMuted => _muted;
  String? get currentMusicFile => _currentMusicFile;

  static const double _musicVolume = 0.42;

  Future<void> init() async {
    await _music.setVolume(_musicVolume);
  }

  void setMuted(bool value) {
    _muted = value;
    if (value) {
      _music.pause();
    } else if (_currentMusicFile != null) {
      _music.resume();
    }
  }

  Future<void> playMusic(String file, {bool loop = true, double volume = 0.5}) async {
    if (_muted || file.isEmpty) return;
    final String asset = AssetCatalog.audio(file);
    if (_currentMusicFile == file && _music.state == PlayerState.playing) return;

    _currentMusicFile = file;
    try {
      await _music.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await _music.setVolume((volume * _musicVolume).clamp(0.0, 1.0));
      await _music.play(AssetSource(asset));
    } catch (error) {
      debugPrint('AudioService.playMusic($file): $error');
    }
  }

  Future<void> stopMusic({double fadeOut = 1}) async {
    _currentMusicFile = null;
    try {
      if (fadeOut > 0) {
        // Simple fade via volume steps — audioplayers' native fade support
        // differs per platform.
        const int steps = 6;
        for (int i = steps; i >= 0; i--) {
          await _music.setVolume(_musicVolume * (i / steps));
          await Future<void>.delayed(
            Duration(milliseconds: (fadeOut * 1000 / steps).round()),
          );
        }
      }
      await _music.stop();
    } catch (error) {
      debugPrint('AudioService.stopMusic: $error');
    }
  }

  Future<void> playSfx(String file) async {
    if (_muted || file.isEmpty) return;
    final String asset = AssetCatalog.audio(file);
    final AudioPlayer player = _sfxPool[_sfxCursor % _sfxPool.length];
    _sfxCursor++;
    try {
      await player.stop();
      await player.setReleaseMode(ReleaseMode.release);
      await player.play(AssetSource(asset), volume: 1.0);
    } catch (error) {
      debugPrint('AudioService.playSfx($file): $error');
    }
  }

  Future<void> dispose() async {
    await _music.dispose();
    for (final AudioPlayer player in _sfxPool) {
      await player.dispose();
    }
  }
}
