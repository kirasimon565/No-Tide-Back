/// Tiny expression evaluator for `@if`, `@elseif`, `@choice_if` and `@set`.
///
/// Supports the shapes actually used by the episode scripts:
///   sister_suspicious == true && home_safe == false
///   trust_kathy >= 4
///   puzzle_result == "success"
///   hack_1_success            (bare truthiness)
/// plus `||`, `!`, parentheses and numeric comparisons.
class NtbExpression {
  NtbExpression(this.source);

  final String source;

  bool evaluate(Map<String, dynamic> variables) {
    final _ExprParser parser = _ExprParser(source, variables);
    final Object? value = parser.parseExpression();
    return _truthy(value);
  }

  static bool _truthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final String s = value.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || (s.isNotEmpty && s != 'false' && s != '0');
  }
}

class _ExprParser {
  _ExprParser(this.input, this.variables);

  final String input;
  final Map<String, dynamic> variables;
  int _pos = 0;

  Object? parseExpression() {
    final Object? value = _parseOr();
    _skipWhitespace();
    return value;
  }

  Object? _parseOr() {
    Object? left = _parseAnd();
    while (true) {
      _skipWhitespace();
      if (_match('||')) {
        final Object? right = _parseAnd();
        left = NtbExpression._truthy(left) || NtbExpression._truthy(right);
      } else {
        return left;
      }
    }
  }

  Object? _parseAnd() {
    Object? left = _parseComparison();
    while (true) {
      _skipWhitespace();
      if (_match('&&')) {
        final Object? right = _parseComparison();
        left = NtbExpression._truthy(left) && NtbExpression._truthy(right);
      } else {
        return left;
      }
    }
  }

  Object? _parseComparison() {
    final Object? left = _parseUnary();
    _skipWhitespace();
    for (final String op in <String>['==', '!=', '>=', '<=', '>', '<']) {
      if (_match(op)) {
        final Object? right = _parseUnary();
        return _compare(left, right, op);
      }
    }
    return left;
  }

  Object? _parseUnary() {
    _skipWhitespace();
    if (_match('!')) {
      final Object? value = _parseUnary();
      return !NtbExpression._truthy(value);
    }
    if (_match('(')) {
      final Object? value = _parseOr();
      _skipWhitespace();
      _match(')');
      return value;
    }
    return _parseAtom();
  }

  Object? _parseAtom() {
    _skipWhitespace();
    if (_pos >= input.length) return null;

    // Number
    final RegExp numberRe = RegExp(r'^-?\d+(\.\d+)?');
    final Match? numberMatch = numberRe.firstMatch(input.substring(_pos));
    if (numberMatch != null) {
      _pos += numberMatch.group(0)!.length;
      final String raw = numberMatch.group(0)!;
      return raw.contains('.') ? double.parse(raw) : int.parse(raw);
    }

    // Quoted string
    final String char = input[_pos];
    if (char == '"' || char == "'") {
      final int end = input.indexOf(char, _pos + 1);
      if (end == -1) {
        final String value = input.substring(_pos + 1);
        _pos = input.length;
        return value;
      }
      final String value = input.substring(_pos + 1, end);
      _pos = end + 1;
      return value;
    }

    // Identifier / keyword
    final RegExp identRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*');
    final Match? identMatch = identRe.firstMatch(input.substring(_pos));
    if (identMatch != null) {
      final String ident = identMatch.group(0)!;
      _pos += ident.length;
      switch (ident.toLowerCase()) {
        case 'true':
          return true;
        case 'false':
          return false;
        case 'null':
          return null;
        case 'not':
          return !NtbExpression._truthy(_parseUnary());
      }
      return variables[ident];
    }

    _pos++;
    return null;
  }

  Object? _compare(Object? left, Object? right, String op) {
    if (left is num || right is num) {
      final double l = _toNum(left);
      final double r = _toNum(right);
      return switch (op) {
        '==' => l == r,
        '!=' => l != r,
        '>=' => l >= r,
        '<=' => l <= r,
        '>' => l > r,
        '<' => l < r,
        _ => false,
      };
    }
    if (left is bool || right is bool) {
      final bool l = NtbExpression._truthy(left);
      final bool r = NtbExpression._truthy(right);
      return switch (op) {
        '==' => l == r,
        '!=' => l != r,
        _ => false,
      };
    }
    final String l = left?.toString() ?? '';
    final String r = right?.toString() ?? '';
    return switch (op) {
      '==' => l == r,
      '!=' => l != r,
      _ => false,
    };
  }

  static double _toNum(Object? value) {
    if (value is num) return value.toDouble();
    if (value is bool) return value ? 1 : 0;
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _skipWhitespace() {
    while (_pos < input.length && input[_pos].trim().isEmpty) {
      _pos++;
    }
  }

  bool _match(String token) {
    _skipWhitespace();
    if (input.startsWith(token, _pos)) {
      _pos += token.length;
      return true;
    }
    return false;
  }
}
