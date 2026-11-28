import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/player_profile.dart';
import '../../providers/app_providers.dart';
import '../../providers/game_state_provider.dart';
import '../widgets/common_widgets.dart';
import 'phone_inbox_screen.dart';

/// Screen 3 — Device registration.
///
/// Captures {player_name} and {player_gender}, then seeds the pronoun map used
/// by the script interpolation (`{they}`, `{them}`, `{their}`, `{bro_sis}`).
///
/// The boot action is guarded end-to-end: every stage reports to the console
/// plate, nothing waits on the interpreter (which parks at the first `@choice`
/// by design), and a failure surfaces a retry instead of an endless spinner.
class PlayerSetupScreen extends ConsumerStatefulWidget {
  const PlayerSetupScreen({super.key});

  @override
  ConsumerState<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends ConsumerState<PlayerSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  PlayerGender _gender = PlayerGender.neutral;
  bool _booting = false;
  String _stage = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final PlayerProfile existing = ref.read(gameStateProvider.notifier).profile;
    _nameController.text = existing.playerName == 'Player' ? '' : existing.playerName;
    _gender = existing.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    if (_booting) return;
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a first name to register this device.');
      _nameFocus.requestFocus();
      return;
    }
    if (name.length > 16) {
      setState(() => _error = 'Keep it to 16 characters or less.');
      return;
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();

    setState(() {
      _booting = true;
      _error = null;
      _stage = 'REGISTERING DEVICE...';
    });

    final GameStateNotifier notifier = ref.read(gameStateProvider.notifier);
    try {
      final PlayerProfile profile = PlayerProfile(
        playerName: name,
        gender: _gender,
      );
      await notifier.saveProfile(profile);

      setState(() => _stage = 'PARSING EPISODE...');
      // `.future` is already resolved after Screen 0's boot controller, so this
      // is instant on a warm start and ~300 ms on a cold one. The timeout makes
      // a broken asset bundle a visible error instead of a hang.
      final parsed = await ref
          .read(ntbProgramProvider.future)
          .timeout(const Duration(seconds: 20));

      setState(() => _stage = 'OPENING RELAY...');
      // Returns as soon as the first scene is on screen (it must — the
      // interpreter parks at the first @choice and awaiting it deadlocks).
      await notifier
          .startNewGame(program: parsed.program)
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() {
        _booting = false;
        _stage = '';
      });
      _goToPhone();
    } on TimeoutException {
      _fail('The relay did not answer. Check that the episode scripts are '
          'bundled, then retry.');
    } catch (error) {
      _fail('$error');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _booting = false;
      _stage = '';
      _error = message;
    });
    ref.read(gameStateProvider.notifier).clearBootError();
  }

  void _goToPhone() {
    // pushReplacement, not pushAndRemoveUntil: the hub must stay underneath so
    // leaving the phone returns to episode select instead of the splash.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b) =>
            const PhoneInboxScreen(firstLaunch: true),
        transitionsBuilder: (
          BuildContext c,
          Animation<double> a,
          Animation<double> b,
          Widget child,
        ) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String name = _nameController.text.trim();
    final String previewName = name.isEmpty ? 'YOU' : name.toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: Column(
        children: <Widget>[
          const ConsoleHeader(title: 'Device Registration', subtitle: 'Step 01 / 02'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              children: <Widget>[
                Text('WHO ARE YOU', style: AppTypography.kicker),
                const SizedBox(height: 8),
                Text(
                  'ON THE RELAY?',
                  style: AppTypography.displayTitle.copyWith(fontSize: 27),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your friends will use this name in every thread. Pronouns are '
                  'applied to every line of dialogue automatically.',
                  style: AppTypography.bodySmall.copyWith(height: 1.6),
                ),
                const SizedBox(height: 26),

                _FieldLabel('FIRST NAME'),
                const SizedBox(height: 8),
                _ConsoleField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  hint: 'Enter your first name',
                  maxLength: 16,
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 24),

                _FieldLabel('PRONOUNS'),
                const SizedBox(height: 10),
                ...PlayerGender.values.map(
                  (PlayerGender gender) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PronounRow(
                      gender: gender,
                      selected: _gender == gender,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _gender = gender);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                _FieldLabel('RELAY PREVIEW'),
                const SizedBox(height: 8),
                ConsolePreview(
                  gender: _gender,
                  playerName: previewName,
                ),
                const SizedBox(height: 22),

                if (_error != null) ...<Widget>[
                  _ErrorPlate(message: _error!),
                  const SizedBox(height: 16),
                ],

                ConsoleButton(
                  label: _booting ? (_stage.isEmpty ? 'WORKING...' : _stage) : 'BEGIN DEVICE',
                  icon: _booting ? null : Icons.power_settings_new_rounded,
                  busy: _booting,
                  onPressed: _booting ? null : _boot,
                ),
                const SizedBox(height: 12),
                Text(
                  'THIS CANNOT BE CHANGED LATER.',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelDim.copyWith(
                    fontSize: 8,
                    color: AppColors.accentCrimson.withValues(alpha: 0.75),
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.label.copyWith(
          fontSize: 10,
          color: AppColors.textMuted,
        ),
      );
}

/// Glass input: inset well, cyan focus rule, no Material fill animation.
class _ConsoleField extends StatelessWidget {
  const _ConsoleField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.maxLength,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final int maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLength: maxLength,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp('[<>]')),
      ],
      style: AppTypography.body.copyWith(fontSize: 17),
      cursorColor: AppColors.accentTide,
      cursorWidth: 1.4,
      decoration: InputDecoration(
        hintText: hint,
        counterStyle: AppTypography.labelDim.copyWith(fontSize: 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(
            color: AppColors.divider.withValues(alpha: 0.9),
            width: 0.8,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: AppColors.accentTide, width: 1),
        ),
      ),
    );
  }
}

/// One pronoun row: console title, the pronoun set, and the selection tick.
class _PronounRow extends StatelessWidget {
  const _PronounRow({
    required this.gender,
    required this.selected,
    required this.onTap,
  });

  final PlayerGender gender;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = selected ? AppColors.accentTide : AppColors.textMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentTide.withValues(alpha: 0.07)
              : AppColors.surfaceCard.withValues(alpha: 0.55),
          border: Border.all(
            color: selected ? AppColors.accentTide.withValues(alpha: 0.7) : AppColors.divider,
            width: selected ? 0.9 : 0.7,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 1),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accentTide,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 13),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  gender.label.toUpperCase(),
                  style: AppTypography.label.copyWith(
                    fontSize: 10,
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${gender.pronounSummary}   •   ${gender.broSis}'.toUpperCase(),
                  style: AppTypography.labelDim.copyWith(fontSize: 7.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Live interpolation preview — the same tokens the script will resolve.
class ConsolePreview extends StatelessWidget {
  const ConsolePreview({required this.gender, required this.playerName, super.key});

  final PlayerGender gender;
  final String playerName;

  @override
  Widget build(BuildContext context) {
    final Map<String, String> tokens = PlayerProfile(
      playerName: playerName,
      gender: gender,
    ).interpolationTokens;

    String resolve(String raw) {
      String out = raw;
      tokens.forEach((String k, String v) => out = out.replaceAll('{$k}', v));
      return out;
    }

    const String line1 = 'give {them} 5 min abi, not everyone wakes up at 6am';
    const String line2 = 'hey {player_name}! did {they} get home ok? night {bro_sis}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.slateHeader.withValues(alpha: 0.6),
        border: Border.all(color: AppColors.divider, width: 0.7),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            line1,
            style: AppTypography.labelDim.copyWith(fontSize: 8, height: 1.9),
          ),
          const SizedBox(height: 4),
          Text(
            line2,
            style: AppTypography.labelDim.copyWith(fontSize: 8, height: 1.9),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: AppColors.divider.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(
            resolve('${resolve(line1)}... ${resolve(line2)}'),
            style: AppTypography.body.copyWith(
              fontSize: 14,
              color: AppColors.accentTide,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPlate extends StatelessWidget {
  const _ErrorPlate({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.accentCrimson.withValues(alpha: 0.09),
        border: Border.all(
          color: AppColors.accentCrimson.withValues(alpha: 0.55),
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.accentCrimson),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 12,
                height: 1.5,
                color: AppColors.accentCrimson.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
