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
      expect(compiled.hasMatch('NEWS42'), isTrue);
      expect(compiled.hasMatch('本季番剧'), isTrue);
      expect(compiled.storedValue, '^news\\d+\$\n动画|番剧');
    });

    test('empty filters never match any input', () {
      for (final compiled in [
        const CompiledFilterPattern.empty(),
        FilterPatternCompiler.compileRules(['', '  ']),
        FilterPatternCompiler.compileStoredSafely(''),
      ]) {
        expect(compiled.isEnabled, isFalse);
        expect(compiled.hasMatch(''), isFalse);
        expect(compiled.hasMatch('anything'), isFalse);
      }
    });

    test('keeps independent named groups and respects explicit case mode', () {
      final compiled = FilterPatternCompiler.compileRules([
        r'^(?<word>foo)$',
        r'^(?<word>bar)$',
      ]);
      expect(compiled.hasMatch('FOO'), isTrue);
      expect(compiled.hasMatch('bar'), isTrue);
      expect(compiled.hasMatch('none'), isFalse);
      final sensitive = FilterPatternCompiler.compileStored(
        'FOO\nbar',
        caseSensitive: true,
      );
      expect(sensitive.hasMatch('foo'), isFalse);
      expect(sensitive.hasMatch('FOO'), isTrue);
    });

    test('normalizes CRLF, trims and deduplicates without rewriting rules', () {
      final compiled = FilterPatternCompiler.compileStored(
        '  foo  \r\nbar\rfoo\r\n  \r\n',
      );
      expect(compiled.rules, ['foo', 'bar']);
      expect(compiled.storedValue, 'foo\nbar');
      expect(() => compiled.rules.add('baz'), throwsUnsupportedError);
      expect(compiled.invalidRuleCount, 0);
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
      expect(compiled.hasMatch('aaab'), isTrue);
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

    test('disables an entirely invalid stored filter and reports it', () {
      Object? reportedError;
      final compiled = FilterPatternCompiler.compileStoredSafely(
        r'(a+)+',
        onError: (error, _) => reportedError = error,
      );

      expect(compiled.isEnabled, isFalse);
      expect(compiled.hasMatch('anything'), isFalse);
      expect(compiled.invalidRuleCount, 1);
      expect(reportedError, isA<FilterPatternException>());
    });

    test('isolates invalid stored rules and reports only safe diagnostics', () {
      final errors = <Object>[];
      const stored = 'good\n[private-pattern\n(a+)+\nother';
      final compiled = FilterPatternCompiler.compileStoredSafely(
        stored,
        onError: (error, _) => errors.add(error),
      );
      expect(compiled.isEnabled, isTrue);
      expect(compiled.rules, ['good', 'other']);
      expect(compiled.storedValue, 'good\nother');
      expect(compiled.invalidRuleCount, 2);
      expect(compiled.hasMatch('GOOD'), isTrue);
      expect(compiled.hasMatch('other'), isTrue);
      expect(compiled.hasMatch('unmatched'), isFalse);
      expect(errors, hasLength(2));
      expect(errors.every((error) => error is FilterPatternException), isTrue);
      expect(errors.join(), isNot(contains('private-pattern')));
      expect(errors.join(), isNot(contains('(a+)+')));
      // The compiler returns an in-memory view; it never rewrites the input.
      expect(stored, 'good\n[private-pattern\n(a+)+\nother');
    });

    test('safe loading never truncates or bypasses global budgets', () {
      for (final rules in [
        List.generate(101, (index) => 'rule$index'),
        ['good', _repeat('x', 257)],
        List.generate(33, (index) => '$index-${_repeat('x', 252)}'),
      ]) {
        final errors = <Object>[];
        final compiled = FilterPatternCompiler.compileStoredSafely(
          rules.join('\n'),
          onError: (error, _) => errors.add(error),
        );
        expect(compiled.isEnabled, isFalse);
        expect(compiled.hasMatch('good'), isFalse);
        expect(compiled.rules, isEmpty);
        expect(compiled.invalidRuleCount, rules.length);
        expect(errors, hasLength(1));
      }
    });

    test('stays disabled when the error reporter throws', () {
      final compiled = FilterPatternCompiler.compileStoredSafely(
        r'(a+)+',
        onError: (_, _) => throw StateError('reporting unavailable'),
      );

      expect(compiled.isEnabled, isFalse);
      expect(compiled.hasMatch('anything'), isFalse);
    });

    test('reporter failures do not discard valid neighboring rules', () {
      final compiled = FilterPatternCompiler.compileStoredSafely(
        'good\n[broken\nother',
        onError: (_, _) => throw StateError('reporting unavailable'),
      );
      expect(compiled.isEnabled, isTrue);
      expect(compiled.hasMatch('good'), isTrue);
      expect(compiled.hasMatch('other'), isTrue);
      expect(compiled.invalidRuleCount, 1);
    });

    test('validates imported setting values with the same compiler', () {
      expect(
        () => FilterPatternCompiler.validateStoredSettings(
          {'recommend': 'good\n[broken\nother'},
          const ['recommend'],
        ),
        throwsA(isA<FilterPatternException>()),
      );
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
