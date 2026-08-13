import 'dart:io';

import 'package:path/path.dart' as p;

/// Audits fork routing: reports forks nobody imports and upstream originals
/// that are still referenced somewhere (dual-implementation risk).
///
///   dart run tool/pilimax/check_fork_references.dart
Future<void> main() async {
  final mapFile = File('tool/pilimax/fork_map.tsv');
  if (!mapFile.existsSync()) {
    stderr.writeln('fork map not found: ${mapFile.path}');
    exit(1);
  }

  final forks = <String, String>{};
  for (final raw in mapFile.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final columns = line.split('\t');
    if (columns.length >= 3 && columns[0] == 'fork') {
      forks[columns[1]] = columns[2];
    }
  }

  final forkRefs = <String, int>{for (final target in forks.values) target: 0};
  final originalRefs = <String, int>{for (final path in forks.keys) path: 0};

  final directive = RegExp(
    r'''^(?:import|export|part(?:\s+of)?)\s+['"]([^'"]+)['"]''',
  );
  for (final root in <String>['lib', 'test', 'tool']) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      continue;
    }
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final file = entity.path.replaceAll('\\', '/');
      final text = entity.readAsStringSync();
      for (final line in text.split('\n')) {
        final match = directive.firstMatch(line.trimLeft());
        if (match == null) {
          continue;
        }
        final uri = match.group(1)!;
        String resolved;
        if (uri.startsWith('package:PiliMax/')) {
          resolved = 'lib/${uri.substring('package:PiliMax/'.length)}';
        } else if (uri.startsWith('package:') || uri.startsWith('dart:')) {
          continue;
        } else {
          resolved = p.normalize(
            p.posix.join(p.dirname(file), uri),
          ).replaceAll('\\', '/');
        }
        if (forkRefs.containsKey(resolved)) {
          forkRefs[resolved] = forkRefs[resolved]! + 1;
        }
        if (originalRefs.containsKey(resolved) && !forks.containsKey(file)) {
          originalRefs[resolved] = originalRefs[resolved]! + 1;
        }
      }
    }
  }

  var issues = 0;
  for (final entry in forks.entries) {
    final original = entry.key;
    final target = entry.value;
    final refs = forkRefs[target] ?? 0;
    final originals = originalRefs[original] ?? 0;
    if (refs == 0) {
      issues++;
      stdout.writeln('UNUSED-FORK $original -> $target');
    }
    if (originals > 0) {
      issues++;
      stdout.writeln(
        'ORIGINAL-STILL-REFERENCED $original ($originals refs); '
        'dual implementation may be in use',
      );
    }
  }

  if (issues == 0) {
    stdout.writeln(
      'All ${forks.length} forks are referenced and their upstream '
      'originals are unused.',
    );
    exit(0);
  }
  stderr.writeln('$issues fork-routing issues found; review above.');
  exit(1);
}
