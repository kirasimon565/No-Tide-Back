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

/// Screen 3 — Player Identity Setup.
///
/// Captures {player_name} and {player_gender}, then seeds the pronoun map used
/// by the script interpolation (`{they}`, `{them}`, `{their}`, `{bro_sis}`).
class PlayerSetupScreen extends ConsumerStatefulWidget {
  const PlayerSetupScreen({super.key});

  @override
  ConsumerState<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends ConsumerState<PlayerSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  PlayerGender _gender = PlayerGender.neutral;
  int _avatarIndex = 0;
  bool _booting = false;
  String? _error;

  static const List<IconData> _avatarGlyphs = <IconData>[
    Icons.person_rounded,
    Icons.face_4_rounded,
    Icons.face_6_rounded,
    Icons.psychology_alt_rounded,
  ];

  @override
  void initState() {
    super.initState();
    final PlayerProfile existing = ref.read(gameStateProvider.notifier).profile;
    _nameController.text = existing.playerName == 'Player' ? '' : existing.playerName;
    _gender = existing.gender;
    _avatarIndex = existing.avatarIndex;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a first name to boot the device.');
      return;
    }
    if (name.length > 16) {
      setState(() => _error = 'Keep it to 16 characters or less.');
      return;
    }

    setState(() {
      _booting = true;
      _error = null;
    });

    final PlayerProfile profile = PlayerProfile(
      playerName: name,
      gender: _gender,
      avatarIndex: _avatarIndex,
    );

    final GameStateNotifier notifier = ref.read(gameStateProvider.notifier);
    await notifier.saveProfile(profile);

    final program = (await ref.read(ntbProgramProvider.future)).program;
    await notifier.startNewGame(program: program);

    if (!mounted) return;
    setState(() => _booting = false);
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (BuildContext _) => const PhoneInboxScreen()),
      (Route<void> route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayerProfile preview = PlayerProfile(
      playerName: _nameController.text.trim().isEmpty ? 'You' : _nameController.text.trim(),
      gender: _gender,
      avatarIndex: _avatarIndex,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'DEVICE REGISTRATION',
          style: AppTypography.monoLabel.copyWith(fontSize: 11),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
          children: <Widget>[
            Text(
              'Who is holding\nthe phone?',
              style: AppTypography.title.copyWith(fontSize: 26, height: 1.25),
            ),
            const SizedBox(height: 8),
            Text(
              'Your friends will use this name in every thread. '
              'Pronouns are applied to every line of dialogue automatically.',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: 26),

            // Avatar picker
            Text('AVATAR', style: AppTypography.monoLabel),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                for (int i = 0; i < _avatarGlyphs.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == _avatarGlyphs.length - 1 ? 0 : 8),
                      child: _AvatarOption(
                        glyph: _avatarGlyphs[i],
                        selected: _avatarIndex == i,
                        onTap: () => setState(() => _avatarIndex = i),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),

            // Name
            Text('FIRST NAME', style: AppTypography.monoLabel),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              maxLength: 16,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.words,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.deny(RegExp('[<>]')),
              ],
              onChanged: (_) => setState(() => _error = null),
              style: AppTypography.body.copyWith(fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Enter your first name',
                hintStyle: AppTypography.body.copyWith(color: AppColors.textMuted),
                counterStyle: AppTypography.monoCaption.copyWith(fontSize: 9),
                filled: true,
                fillColor: AppColors.surfaceCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accentTide, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Pronouns
            Text('PRONOUNS', style: AppTypography.monoLabel),
            const SizedBox(height: 10),
            ...PlayerGender.values.map(
              (PlayerGender gender) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _GenderCard(
                  gender: gender,
                  selected: _gender == gender,
                  onTap: () => setState(() => _gender = gender),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Live preview of the interpolation result
            NtbCard(
              color: AppColors.surfacePhone,
              borderColor: AppColors.accentTide.withValues(alpha: 0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('RELAY PREVIEW', style: AppTypography.monoCaption.copyWith(letterSpacing: 1.6)),
                  const SizedBox(height: 10),
                  Text(
                    '"give {them} 5 min abi, not everyone wakes up at 6am"\n'
                    '"hey {player_name}! did {they} get home ok? night {bro_sis}"',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ref.read(gameStateProvider.notifier).interpolate(
                          'give {them} 5 min abi... hey {player_name}! did {they} get home ok? night {bro_sis}',
                        ).replaceAll('You', preview.playerName),
                    style: AppTypography.body.copyWith(color: AppColors.accentTide),
                  ),
                ],
              ),
            ),

            if (_error != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                '> ${_error!.toUpperCase()}',
                style: AppTypography.monoCaption.copyWith(color: AppColors.accentCrimson),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _booting ? null : _boot,
              icon: _booting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bgVoid),
                    )
                  : const Icon(Icons.smartphone_rounded, size: 18),
              label: Text(_booting ? 'BOOTING DEVICE...' : 'BOOT DEVICE'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarOption extends StatelessWidget {
  const _AvatarOption({
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  final IconData glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 66,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentTide.withValues(alpha: 0.12)
              : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.accentTide : AppColors.divider,
            width: selected ? 1.4 : 0.8,
          ),
        ),
        child: Icon(
          glyph,
          size: 28,
          color: selected ? AppColors.accentTide : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _GenderCard extends StatelessWidget {
  const _GenderCard({
    required this.gender,
    required this.selected,
    required this.onTap,
  });

  final PlayerGender gender;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.bubbleOutgoing.withValues(alpha: 0.35) : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accentTide : AppColors.divider,
            width: selected ? 1.3 : 0.8,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: selected ? AppColors.accentTide : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    gender.label,
                    style: AppTypography.sectionTitle.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${gender.pronounSummary}  •  ${gender.broSis}',
                    style: AppTypography.monoCaption.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
