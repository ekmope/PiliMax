import 'dart:io';

/// Detects drift between the recorded upstream snapshot and the current
/// upstream ref for every tracked path. Run after each upstream fetch/merge:
///
///   dart run tool/pilimax/check_upstream_sync.dart
///
/// The mapping lives in `tool/pilimax/fork_map.tsv`:
///   # snapshot=`<commit>`
///   fork     \t upstream-path \t fork-path
///   modified \t upstream-path \t -
///   deleted  \t upstream-path \t -
///
/// Override the compared ref with `PILIMAX_UPSTREAM=some/ref`.
Future<void> main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final upstreamRef = Platform.environment['PILIMAX_UPSTREAM'] ?? 'upstream/main';
  final mapFile = File('tool/pilimax/fork_map.tsv');
  if (!mapFile.existsSync()) {
    stderr.writeln('fork map not found: ${mapFile.path}');
    exit(1);
  }

  String? snapshot;
  final rows = <List<String>>[];
  for (final raw in mapFile.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('#')) {
      if (line.startsWith('# snapshot=')) {
        snapshot = line.substring('# snapshot='.length).trim();
      }
      continue;
    }
    final columns = line.split('\t');
    if (columns.length < 2) {
      stderr.writeln('malformed fork map line: $line');
      exit(1);
    }
    rows.add(columns);
  }
  if (snapshot == null || snapshot.isEmpty) {
    stderr.writeln('fork map is missing the # snapshot header');
    exit(1);
  }

  final changedResult = await Process.run(
    'git',
    ['diff', '--name-only', snapshot, upstreamRef],
  );
  if (changedResult.exitCode != 0) {
    if (warnOnly) {
      stdout.writeln(
        'upstream ref $upstreamRef is unavailable on this checkout; '
        'skipping the drift check.',
      );
      exit(0);
    }
    stderr.writeln(
      'cannot diff $snapshot..$upstreamRef: ${changedResult.stderr}',
    );
    exit(1);
  }
  final changed = (changedResult.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet();

  final hits = rows.where((row) => changed.contains(row[1])).toList();
  if (hits.isEmpty) {
    stdout.writeln(
      'All ${rows.length} tracked paths are in sync with $upstreamRef.',
    );
    exit(0);
  }

  for (final row in hits) {
    final kind = row[0];
    final path = row[1];
    final target = row.length > 2 ? row[2] : '-';
    switch (kind) {
      case 'fork':
        stdout.writeln(
          'FORK-DRIFT $path -> $target: upstream changed the original; '
          'port the change into the fork.',
        );
      case 'modified':
        stdout.writeln(
          'MODIFIED-DRIFT $path: upstream changed a file modified in place; '
          'merge the change manually.',
        );
      case 'deleted':
        stdout.writeln(
          'DELETED-DRIFT $path: upstream changed a file we deleted; '
          'keep the deletion with `git rm`.',
        );
      default:
        stdout.writeln('DRIFT($kind) $path -> $target');
    }
    final history = await Process.run(
      'git',
      ['log', '--oneline', '-n', '5', '$snapshot..$upstreamRef', '--', path],
    );
    final historyText = (history.stdout as String).trimRight();
    if (historyText.isNotEmpty) {
      stdout.writeln(historyText);
    }
    stdout.writeln('');
  }

  stderr.writeln(
    '${hits.length} tracked paths have drifted since $snapshot; review above.',
  );
  if (!warnOnly) {
    exit(1);
  }
  stdout.writeln('Drift reported in warn-only mode; continuing.');
}
