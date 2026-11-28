import 'package:flutter/foundation.dart';

/// A parsed `.ntb` instruction, or a structural container (choice / if-block).
///
/// The parser produces a generic tree: indentation decides nesting, and the
/// interpreter gives meaning to `@choice` / `@if` children. Keeping the AST
/// generic means new directives never require parser changes.
@immutable
class NtbNode {
  const NtbNode({
    required this.name,
    required this.params,
    required this.freeArgs,
    required this.children,
    required this.lineNumber,
    required this.partNumber,
    this.indent = 0,
    this.isSceneLabel = false,
  });

  /// Directive name without the `@` (eg. `message`, `choice_locked`).
  final String name;

  /// `key="value"` attributes.
  final Map<String, String> params;

  /// Everything after the directive name that was not a quoted attribute
  /// (eg. `sister_suspicious == true && home_safe == false` for `@if`).
  final String freeArgs;

  final List<NtbNode> children;
  final int lineNumber;
  final int partNumber;

  /// Leading indentation in the source file; drives block skipping.
  final int indent;
  final bool isSceneLabel;

  /// `:: ep1_start` label text.
  String get sceneLabel => freeArgs.trim();

  String? operator [](String key) => params[key];

  bool has(String key) => params.containsKey(key);

  String param(String key, [String fallback = '']) => params[key] ?? fallback;

  int intParam(String key, [int fallback = 0]) =>
      int.tryParse(param(key)) ?? fallback;

  double doubleParam(String key, [double fallback = 0]) =>
      double.tryParse(param(key)) ?? fallback;

  bool boolParam(String key, [bool fallback = false]) {
    final String v = param(key).toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
    return fallback;
  }

  @override
  String toString() => isSceneLabel ? ':: $sceneLabel' : '@$name $params';
}

/// Thrown when a script references a label that does not exist.
class NtbParseException implements Exception {
  NtbParseException(this.message, {this.lineNumber, this.file});

  final String message;
  final int? lineNumber;
  final String? file;

  @override
  String toString() =>
      'NtbParseException: $message${lineNumber == null ? '' : ' (line $lineNumber)'}'
      '${file == null ? '' : ' [$file]'}';
}

/// A fully linked programme: every part concatenated in order, with a scene
/// label index so `@goto` can jump across part boundaries.
class NtbProgram {
  NtbProgram({
    required this.instructions,
    required this.sceneIndex,
    required this.partStartIndex,
  });

  final List<NtbNode> instructions;
  final Map<String, int> sceneIndex;

  /// partNumber -> index of its first instruction.
  final Map<int, int> partStartIndex;

  int get length => instructions.length;

  int partForIndex(int index) {
    if (instructions.isEmpty) return 1;
    final int clamped = index.clamp(0, instructions.length - 1).toInt();
    return instructions[clamped].partNumber;
  }

  int? indexOfScene(String label) => sceneIndex[label.trim()];

  /// Index just past the block that starts at [index] (exclusive).
  ///
  /// A block owns every following instruction that is indented deeper than it.
  int blockEnd(int index) {
    if (index < 0 || index >= instructions.length) return instructions.length;
    final int indent = instructions[index].indent;
    int cursor = index + 1;
    while (cursor < instructions.length &&
        instructions[cursor].indent > indent) {
      cursor++;
    }
    return cursor;
  }

  /// First sibling `@elseif` / `@else` / `@endif` of the block at [index],
  /// or -1 when the structure is malformed.
  int nextChainSibling(int index) {
    if (index < 0 || index >= instructions.length) return -1;
    final int indent = instructions[index].indent;
    int cursor = index + 1;
    while (cursor < instructions.length) {
      final NtbNode node = instructions[cursor];
      if (node.indent < indent) return -1;
      if (node.indent == indent) {
        if (node.name == 'elseif' ||
            node.name == 'else' ||
            node.name == 'endif') {
          return cursor;
        }
        // Any other statement at the same depth closes the branch.
        return -1;
      }
      cursor++;
    }
    return -1;
  }

  /// The scene label that contains [index] (nearest preceding `::`).
  String sceneForIndex(int index) {
    final int clamped = index.clamp(0, instructions.length - 1).toInt();
    for (int i = clamped; i >= 0; i--) {
      final NtbNode node = instructions[i];
      if (node.isSceneLabel) return node.sceneLabel;
    }
    return 'start';
  }
}
