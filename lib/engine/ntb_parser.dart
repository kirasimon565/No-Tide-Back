import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/ntb_ast_node.dart';

/// Parses `.ntb` episode scripts into a single linked [NtbProgram].
///
/// Responsibilities
///  * concatenate `episode_01_part_1.ntb` … `part_4.ntb` into one instruction
///    stream while remembering which part each instruction came from;
///  * index every `:: scene_label` so `@goto` can jump across part boundaries;
///  * resolve indentation into a tree so `@choice` options and `@if` branches
///    keep their nested `@set` / `@goto` / `@message` bodies;
///  * strip `@comment` lines and keep `@metadata` for the hub/episode cards.
class NtbParser {
  NtbParser({this.assetLoader});

  /// Injectable loader so the parser can run in unit tests without Flutter.
  final Future<String> Function(String assetPath)? assetLoader;

  final List<String> warnings = <String>[];
  Map<String, String> metadata = <String, String>{};

  /// Episode 1 ships as four linked parts.
  static const List<String> defaultEpisodeFiles = <String>[
    'assets/scripts/episode_01_part_1.ntb',
    'assets/scripts/episode_01_part_2.ntb',
    'assets/scripts/episode_01_part_3.ntb',
    'assets/scripts/episode_01_part_4.ntb',
  ];

  Future<NtbProgram> parseEpisode({
    List<String> files = defaultEpisodeFiles,
  }) async {
    final List<NtbNode> flat = <NtbNode>[];
    final Map<String, int> sceneIndex = <String, int>{};
    final Map<int, int> partStart = <int, int>{};

    for (int index = 0; index < files.length; index++) {
      final int partNumber = index + 1;
      final String raw = await _load(files[index]);
      partStart[partNumber] = flat.length;
      _parseInto(raw, partNumber, flat, sceneIndex, files[index]);
    }

    _validateJumpTargets(flat, sceneIndex);

    return NtbProgram(
      instructions: flat,
      sceneIndex: sceneIndex,
      partStartIndex: partStart,
    );
  }

  /// Parses raw script text (used by tests and the script debug screen).
  NtbProgram parseSource(String source, {int partNumber = 1}) {
    final List<NtbNode> flat = <NtbNode>[];
    final Map<String, int> sceneIndex = <String, int>{};
    _parseInto(source, partNumber, flat, sceneIndex, '<memory>');
    _validateJumpTargets(flat, sceneIndex);
    return NtbProgram(
      instructions: flat,
      sceneIndex: sceneIndex,
      partStartIndex: <int, int>{partNumber: 0},
    );
  }

  Future<String> _load(String path) async {
    final Future<String> Function(String)? loader = assetLoader;
    if (loader != null) return loader(path);
    return rootBundle.loadString(path);
  }

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  /// Matches `key="value"` / `key=value` attribute pairs. Episode scripts only
  /// ever use double quotes, which keeps this a plain raw string.
  static final RegExp _attrPattern = RegExp(
    r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("[^"]*"|[^\s]+)',
  );

  void _parseInto(
    String source,
    int partNumber,
    List<NtbNode> flat,
    Map<String, int> sceneIndex,
    String fileLabel,
  ) {
    final List<String> lines = const LineSplitter().convert(source);

    // Children are attached by walking a stack of open indentation levels.
    final List<_OpenBlock> stack = <_OpenBlock>[];
    final List<NtbNode> roots = <NtbNode>[];

    for (int i = 0; i < lines.length; i++) {
      final String rawLine = lines[i];
      if (rawLine.trim().isEmpty) continue;

      final int indent = _indentOf(rawLine);
      final String content = rawLine.trim();

      if (content.startsWith('//') || content.startsWith('#')) continue;
      if (content.startsWith('@comment')) continue;

      if (content.startsWith('::')) {
        final String label = content.substring(2).trim();
        final NtbNode sceneNode = NtbNode(
          name: 'scene',
          params: const <String, String>{},
          freeArgs: label,
          children: const <NtbNode>[],
          lineNumber: i + 1,
          partNumber: partNumber,
          indent: indent,
          isSceneLabel: true,
        );
        _attach(stack, roots, sceneNode, indent);
        flat.add(sceneNode);
        sceneIndex.putIfAbsent(label, () => flat.length - 1);
        continue;
      }

      if (!content.startsWith('@')) {
        // Free prose is not part of the grammar; keep a warning instead of
        // silently dropping content.
        warnings.add('$fileLabel:${i + 1} ignored non-directive line');
        continue;
      }

      final int space = content.indexOf(' ');
      final String name =
          (space == -1 ? content.substring(1) : content.substring(1, space)).trim();
      final String rest = space == -1 ? '' : content.substring(space + 1).trim();

      if (name == 'version') continue;

      final _AttrSplit split = _splitAttributes(rest);

      if (name == 'metadata') {
        metadata.addAll(split.params);
        continue;
      }

      final NtbNode node = NtbNode(
        name: name,
        params: split.params,
        freeArgs: split.free,
        children: <NtbNode>[],
        lineNumber: i + 1,
        partNumber: partNumber,
        indent: indent,
      );

      flat.add(node);
      _attach(stack, roots, node, indent);
    }

    // Roots are only used to keep the tree alive; the flat stream is what the
    // interpreter runs. Children were attached in place (same instances).
  }

  void _attach(
    List<_OpenBlock> stack,
    List<NtbNode> roots,
    NtbNode node,
    int indent,
  ) {
    while (stack.isNotEmpty && indent <= stack.last.indent) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.node.children.add(node);
    }
    // Blocks that can own children.
    if (_canNest(node.name)) {
      stack.add(_OpenBlock(node, indent));
    }
  }

  static bool _canNest(String name) => switch (name) {
        'choice' ||
        'reply' ||
        'choice_locked' ||
        'choice_if' ||
        'if' ||
        'elseif' ||
        'else' =>
          true,
        _ => false,
      };

  static int _indentOf(String line) {
    int count = 0;
    for (int i = 0; i < line.length; i++) {
      final String ch = line[i];
      if (ch == ' ') {
        count++;
      } else if (ch == '\t') {
        count += 2;
      } else {
        break;
      }
    }
    return count;
  }

  static _AttrSplit _splitAttributes(String rest) {
    if (rest.isEmpty) return const _AttrSplit(<String, String>{}, '');
    final Map<String, String> params = <String, String>{};
    final StringBuffer free = StringBuffer();
    int cursor = 0;

    for (final RegExpMatch match in _attrPattern.allMatches(rest)) {
      final String key = match.group(1)!;
      String value = match.group(2)!;
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      params[key] = value;
      free.write(rest.substring(cursor, match.start));
      free.write(' ');
      cursor = match.end;
    }
    free.write(rest.substring(cursor));

    return _AttrSplit(params, free.toString().trim());
  }

  void _validateJumpTargets(List<NtbNode> flat, Map<String, int> sceneIndex) {
    for (final NtbNode node in flat) {
      if (node.name != 'goto') continue;
      final String target = node.param('label', node.freeArgs).trim();
      if (target.isEmpty) {
        warnings.add('@goto without a target at part ${node.partNumber}:${node.lineNumber}');
        continue;
      }
      if (!sceneIndex.containsKey(target)) {
        warnings.add(
          '@goto target "$target" not found (part ${node.partNumber}:${node.lineNumber})',
        );
      }
    }
  }
}

class _OpenBlock {
  _OpenBlock(this.node, this.indent);
  final NtbNode node;
  final int indent;
}

class _AttrSplit {
  const _AttrSplit(this.params, this.free);
  final Map<String, String> params;
  final String free;
}

/// Debug helper: counts directives per script (used by the tooling screen).
@visibleForTesting
Map<String, int> countDirectives(NtbProgram program) {
  final Map<String, int> counts = <String, int>{};
  for (final NtbNode node in program.instructions) {
    counts.update(node.name, (int v) => v + 1, ifAbsent: () => 1);
  }
  return counts;
}
