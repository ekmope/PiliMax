import 'package:PiliMax/pilimax/utils/filter_pattern_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FilterPatternCompiler', () {
    test('preserves regex support and compiles case-insensitively', () {
      final compiled = FilterPatternCompiler.compileRules([
        r'^news\d+$',
        '动画|番剧',
      ]);

      expect(compiled.isEnabled, isTrue);
      expect(compiled.regExp.hasMatch('NEWS42'), isTrue);
      expect(compiled.regExp.hasMatch('本季番剧'), isTrue);
      expect(compiled.storedValue, '^news\\d+\$\n动画|番剧');
    });

    test('parses legacy pipe-separated and newline storage', () {
      expect(
        FilterPatternCompiler.parseStoredRules('广告|推广|营销'),
        ['广告', '推广', '营销'],
      );
      expect(
        FilterPatternCompiler.parseStoredRules('foo\\|bar'),
        [r'foo\|bar'],
      );
      expect(
        FilterPatternCompiler.parseStoredRules('第一条\r\n第二条'),
        ['第一条', '第二条'],
      );
    });

    test('rejects invalid syntax', () {
      expect(
        () => FilterPatternCompiler.compileRules(['[unterminated']),
        throwsA(isA<FilterPatternException>()),
      );
    });

    test('rejects backreferences', () {
      for (final rule in [r'(foo)\1', r'(?<name>foo)\k<name>', '(?P=name)']) {
        expect(
          () => FilterPatternCompiler.compileRules([rule]),
          throwsA(isA<FilterPatternException>()),
          reason: rule,
        );
      }
    });

    test('rejects nested, repeated, and quantified alternation patterns', () {
      for (final rule in [r'(a+)+', r'a++', r'(a|aa)+', r'(ab?){2}']) {
        expect(
          () => FilterPatternCompiler.compileRules([rule]),
          throwsA(isA<FilterPatternException>()),
          reason: rule,
        );
      }
    });

    test('allows lazy quantifiers without nested repetition', () {
      final compiled = FilterPatternCompiler.compileRules([r'a+?b']);
      expect(compiled.regExp.hasMatch('aaab'), isTrue);
    });

    test('enforces rule count, per-rule, and total length limits', () {
      expect(
        () => FilterPatternCompiler.compileRules(
          List.generate(101, (index) => 'rule$index'),
        ),
        throwsA(isA<FilterPatternException>()),
      );
      expect(
        () => FilterPatternCompiler.compileRules([_repeat('x', 257)]),
        throwsA(isA<FilterPatternException>()),
      );
      expect(
        () => FilterPatternCompiler.compileRules(
          List.generate(
            33,
            (index) => '$index-${_repeat('x', 252)}',
          ),
        ),
        throwsA(isA<FilterPatternException>()),
      );
    });

    test('disables only an invalid stored filter and reports it', () {
      Object? reportedError;
      final compiled = FilterPatternCompiler.compileStoredSafely(
        r'(a+)+',
        onError: (error, _) => reportedError = error,
      );

      expect(compiled.isEnabled, isFalse);
      expect(compiled.regExp.pattern, isEmpty);
      expect(reportedError, isA<FilterPatternException>());
    });

    test('stays disabled when the error reporter throws', () {
      final compiled = FilterPatternCompiler.compileStoredSafely(
        r'(a+)+',
        onError: (_, _) => throw StateError('reporting unavailable'),
      );

      expect(compiled.isEnabled, isFalse);
      expect(compiled.regExp.pattern, isEmpty);
    });

    test('validates imported setting values with the same compiler', () {
      expect(
        () => FilterPatternCompiler.validateStoredSettings(
          {'recommend': r'(a+)+'},
          const ['recommend'],
        ),
        throwsA(isA<FilterPatternException>()),
      );
      expect(
        () => FilterPatternCompiler.validateStoredSettings(
          {'recommend': 42},
          const ['recommend'],
        ),
        throwsA(isA<FilterPatternException>()),
      );
      expect(
        () => FilterPatternCompiler.validateStoredSettings(
          {'recommend': '科技\n动画'},
          const ['recommend'],
        ),
        returnsNormally,
      );
    });
  });
}

String _repeat(String value, int count) => List.filled(count, value).join();
