typedef FilterPatternErrorReporter =
    void Function(
      Object error,
      StackTrace stackTrace,
    );

class FilterPatternException implements Exception {
  const FilterPatternException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CompiledFilterPattern {
  const CompiledFilterPattern({
    required this.rules,
    required this.storedValue,
    required this.regExp,
  });

  final List<String> rules;
  final String storedValue;
  final RegExp regExp;

  bool get isEnabled => rules.isNotEmpty;
}

abstract final class FilterPatternCompiler {
  static const int maxRules = 100;
  static const int maxRuleLength = 256;
  static const int maxTotalLength = 8192;

  static List<String> parseStoredRules(String stored) {
    final normalized = stored.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.trim().isEmpty) {
      return const [];
    }

    if (!normalized.contains('\n') && normalized.contains('|')) {
      final parts = normalized
          .split('|')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.length > 1 && !parts.any(_looksLikeComplexPattern)) {
        return parts;
      }
      return [normalized.trim()];
    }

    return normalized
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static CompiledFilterPattern compileStored(
    String stored, {
    bool caseSensitive = false,
  }) => compileRules(
    parseStoredRules(stored),
    caseSensitive: caseSensitive,
  );

  static CompiledFilterPattern compileStoredSafely(
    String stored, {
    bool caseSensitive = false,
    FilterPatternErrorReporter? onError,
  }) {
    try {
      return compileStored(stored, caseSensitive: caseSensitive);
    } catch (error, stackTrace) {
      try {
        onError?.call(error, stackTrace);
      } catch (_) {}
      return CompiledFilterPattern(
        rules: const [],
        storedValue: '',
        regExp: RegExp('', caseSensitive: caseSensitive),
      );
    }
  }

  static CompiledFilterPattern compileRules(
    Iterable<String> inputRules, {
    bool caseSensitive = false,
  }) {
    final rules = <String>[];
    final seen = <String>{};
    for (final inputRule in inputRules) {
      final rule = inputRule.trim();
      if (rule.isNotEmpty && seen.add(rule)) {
        rules.add(rule);
      }
    }

    if (rules.length > maxRules) {
      throw const FilterPatternException('过滤规则不能超过 100 条');
    }

    var totalLength = 0;
    for (var index = 0; index < rules.length; index++) {
      final rule = rules[index];
      if (rule.length > maxRuleLength) {
        throw FilterPatternException('第 ${index + 1} 条规则不能超过 256 个字符');
      }
      totalLength += rule.length;
      if (totalLength > maxTotalLength) {
        throw const FilterPatternException('过滤规则总长度不能超过 8192 个字符');
      }
      _validateRule(rule, index);
      try {
        RegExp(rule, caseSensitive: caseSensitive);
      } on FormatException catch (error) {
        throw FilterPatternException(
          '第 ${index + 1} 条正则语法无效：${error.message}',
        );
      }
    }

    final pattern = rules.map((rule) => '(?:$rule)').join('|');
    try {
      return CompiledFilterPattern(
        rules: List.unmodifiable(rules),
        storedValue: rules.join('\n'),
        regExp: RegExp(pattern, caseSensitive: caseSensitive),
      );
    } on FormatException catch (error) {
      throw FilterPatternException('组合后的正则语法无效：${error.message}');
    }
  }

  static void validateStoredSettings(
    Map<dynamic, dynamic> settings,
    Iterable<String> keys,
  ) {
    for (final key in keys) {
      if (!settings.containsKey(key)) {
        continue;
      }
      final stored = settings[key];
      if (stored is! String) {
        throw FilterPatternException('过滤设置 $key 必须是字符串');
      }
      try {
        compileStored(stored);
      } on FilterPatternException catch (error) {
        throw FilterPatternException('过滤设置 $key 无效：${error.message}');
      }
    }
  }

  static String? validateRule(String rule) {
    try {
      compileRules([rule]);
      return null;
    } on FilterPatternException catch (error) {
      return error.message;
    }
  }

  static void _validateRule(String rule, int index) {
    if (_containsBackreference(rule)) {
      throw FilterPatternException('第 ${index + 1} 条规则不能使用回溯引用');
    }
    if (_containsUnsafeQuantifier(rule)) {
      throw FilterPatternException('第 ${index + 1} 条规则包含嵌套或重复量词');
    }
  }

  static bool _looksLikeComplexPattern(String pattern) =>
      pattern.contains('(') ||
      pattern.contains('[') ||
      pattern.contains('{') ||
      pattern.contains('\\') ||
      pattern.contains('^') ||
      pattern.contains(r'$');

  static bool _containsBackreference(String pattern) {
    for (var index = 0; index < pattern.length - 1; index++) {
      if (pattern.codeUnitAt(index) != 0x5c) {
        continue;
      }
      final next = pattern[index + 1];
      if (RegExp(r'[1-9]').hasMatch(next)) {
        return true;
      }
      if ((next == 'k' || next == 'g') &&
          index + 2 < pattern.length &&
          (pattern[index + 2] == '<' || pattern[index + 2] == "'")) {
        return true;
      }
      index++;
    }
    return pattern.contains('(?P=');
  }

  static bool _containsUnsafeQuantifier(String pattern) {
    final groups = <_GroupComplexity>[_GroupComplexity()];
    var inCharacterClass = false;
    var canQuantify = false;
    var previousWasQuantifier = false;
    var previousWasLazyModifier = false;
    var lastAtomWasGroup = false;
    var lastGroupWasComplex = false;

    for (var index = 0; index < pattern.length; index++) {
      final char = pattern[index];
      if (char == r'\') {
        if (index + 1 < pattern.length) {
          index++;
        }
        canQuantify = true;
        previousWasQuantifier = false;
        previousWasLazyModifier = false;
        lastAtomWasGroup = false;
        continue;
      }
      if (inCharacterClass) {
        if (char == ']') {
          inCharacterClass = false;
          canQuantify = true;
        }
        continue;
      }
      if (char == '[') {
        inCharacterClass = true;
        canQuantify = false;
        previousWasQuantifier = false;
        previousWasLazyModifier = false;
        lastAtomWasGroup = false;
        continue;
      }
      if (char == '(') {
        groups.add(_GroupComplexity());
        canQuantify = false;
        previousWasQuantifier = false;
        previousWasLazyModifier = false;
        lastAtomWasGroup = false;
        continue;
      }
      if (char == ')' && groups.length > 1) {
        final group = groups.removeLast();
        groups.last
          ..hasQuantifier |= group.hasQuantifier
          ..hasAlternation |= group.hasAlternation;
        canQuantify = true;
        previousWasQuantifier = false;
        previousWasLazyModifier = false;
        lastAtomWasGroup = true;
        lastGroupWasComplex = group.hasQuantifier || group.hasAlternation;
        continue;
      }
      if (char == '|') {
        groups.last.hasAlternation = true;
        canQuantify = false;
        previousWasQuantifier = false;
        previousWasLazyModifier = false;
        lastAtomWasGroup = false;
        continue;
      }

      final quantifierEnd = canQuantify ? _quantifierEnd(pattern, index) : null;
      if (quantifierEnd != null) {
        if (previousWasQuantifier) {
          if (char == '?' && !previousWasLazyModifier) {
            previousWasLazyModifier = true;
            continue;
          }
          return true;
        }
        if (lastAtomWasGroup && lastGroupWasComplex) {
          return true;
        }
        groups.last.hasQuantifier = true;
        previousWasQuantifier = true;
        previousWasLazyModifier = false;
        lastAtomWasGroup = false;
        index = quantifierEnd;
        continue;
      }

      canQuantify = char != '^' && char != r'$';
      previousWasQuantifier = false;
      previousWasLazyModifier = false;
      lastAtomWasGroup = false;
    }
    return false;
  }

  static int? _quantifierEnd(String pattern, int index) {
    final char = pattern[index];
    if (char == '*' || char == '+' || char == '?') {
      return index;
    }
    if (char != '{') {
      return null;
    }
    final closing = pattern.indexOf('}', index + 1);
    if (closing == -1) {
      return null;
    }
    final range = pattern.substring(index + 1, closing);
    return RegExp(r'^\d+(?:,\d*)?$').hasMatch(range) ? closing : null;
  }
}

class _GroupComplexity {
  bool hasQuantifier = false;
  bool hasAlternation = false;
}
