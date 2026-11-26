import 'package:flutter_test/flutter_test.dart';
import 'package:no_tide_back/engine/ntb_expression.dart';
import 'package:no_tide_back/engine/ntb_parser.dart';
import 'package:no_tide_back/models/chat_thread.dart';
import 'package:no_tide_back/models/ntb_ast_node.dart';
import 'package:no_tide_back/models/player_profile.dart';

void main() {
  group('pronoun interpolation', () {
    test('maps genders to pronoun tokens', () {
      expect(PlayerGender.male.pronounThey, 'he');
      expect(PlayerGender.female.pronounThem, 'her');
      expect(PlayerGender.neutral.pronounTheir, 'their');
      expect(PlayerGender.male.broSis, 'bro');
      expect(PlayerGender.female.broSis, 'sis');
      expect(PlayerGender.neutral.broSis, 'sib');
    });

    test('profile exposes every script token', () {
      const PlayerProfile profile = PlayerProfile(
        playerName: 'Alex',
        gender: PlayerGender.female,
      );
      expect(
        profile.interpolationTokens.keys,
        containsAll(<String>['player_name', 'they', 'them', 'their', 'bro_sis']),
      );
      expect(profile.interpolationTokens['player_name'], 'Alex');
    });
  });

  group('NtbExpression', () {
    test('evaluates comparisons and booleans', () {
      final Map<String, dynamic> vars = <String, dynamic>{
        'sister_suspicious': true,
        'home_safe': false,
        'trust_kathy': 5,
        'puzzle_result': 'success',
      };
      expect(NtbExpression('sister_suspicious == true').evaluate(vars), isTrue);
      expect(
        NtbExpression('sister_suspicious == true && home_safe == false').evaluate(vars),
        isTrue,
      );
      expect(NtbExpression('trust_kathy >= 4').evaluate(vars), isTrue);
      expect(NtbExpression('trust_kathy > 6').evaluate(vars), isFalse);
      expect(NtbExpression('puzzle_result == "success"').evaluate(vars), isTrue);
      expect(NtbExpression('!home_safe').evaluate(vars), isTrue);
    });
  });

  group('NtbParser', () {
    const String source = '''
@version 1.0
@metadata title="Test Episode" episode="1"

:: start
@set trust_abigail = 7
@typing character="abigail" duration="2"
@message id="m001" chat="group_island" sender="abigail" text="hey {player_name}"

@choice id="c001"
  @reply text="hello"
    @set trust_abigail +1
    @goto next_scene
  @choice_locked id="c_prem" cost="15" text="[PREMIUM - 15 Coins] extra"
    @goto next_scene

:: next_scene
@if trust_abigail >= 8
  @message id="m002" chat="group_island" sender="abigail" text="high trust"
@else
  @message id="m003" chat="group_island" sender="abigail" text="low trust"
@endif
@delay seconds="1"
@add_evidence id="ev_test" title="Test" description="A test clue."
@end_scene title="END OF EPISODE 1"
''';

    test('builds a flat stream with scene indexing', () {
      final NtbProgram program = NtbParser().parseSource(source);
      expect(program.indexOfScene('start'), isNotNull);
      expect(program.indexOfScene('next_scene'), isNotNull);

      final Iterable<NtbNode> messages =
          program.instructions.where((NtbNode n) => n.name == 'message');
      expect(messages.length, 3);
      expect(
        program.instructions.where((NtbNode n) => n.name == 'choice').length,
        1,
      );
    });

    test('nests reply bodies under the choice', () {
      final NtbProgram program = NtbParser().parseSource(source);
      final NtbNode choice =
          program.instructions.firstWhere((NtbNode n) => n.name == 'choice');

      expect(choice.children.length, 2);
      final NtbNode reply = choice.children.first;
      expect(reply.name, 'reply');
      expect(reply.param('text'), 'hello');
      expect(reply.children.any((NtbNode c) => c.name == 'goto'), isTrue);

      final NtbNode locked = choice.children.last;
      expect(locked.name, 'choice_locked');
      expect(locked.intParam('cost'), 15);
    });

    test('indent based block skips are correct for @if', () {
      final NtbProgram program = NtbParser().parseSource(source);
      final int ifIndex =
          program.instructions.indexWhere((NtbNode n) => n.name == 'if');
      final int end = program.blockEnd(ifIndex);

      final NtbNode afterIf = program.instructions[end];
      expect(afterIf.name, 'else');
    });

    test('captures metadata and ignores comments', () {
      final NtbParser parser = NtbParser();
      parser.parseSource('${source}\n@comment ignored line\n');
      expect(parser.metadata['title'], 'Test Episode');
      expect(
        parser.metadata.containsKey('comment'),
        isFalse,
      );
    });
  });

  group('chat thread seed', () {
    test('has the nine documented threads', () {
      expect(ChatThreads.seed.length, 9);
      expect(
        ChatThreads.seed.map((ChatThread t) => t.threadId).toList(),
        <String>[
          'group_island',
          'dm_abigail',
          'dm_beatrice',
          'dm_jessica',
          'dm_maya',
          'dm_kathy',
          'dm_kai',
          'dm_mom',
          'dm_sister',
        ],
      );
    });
  });
}
