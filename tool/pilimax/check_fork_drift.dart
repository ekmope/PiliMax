import 'dart:io';

/// Checks whether upstream moved any file that PiliMax forked into
/// `lib/pilimax/forks/`. Run this after every upstream merge/fetch:
///
///   dart run tool/pilimax/check_fork_drift.dart
///
/// The mapping is stored in `tool/pilimax/fork_map.tsv` as:
///   upstream-path \t fork-path \t upstream-blob-sha-at-fork-time
Future<void> main() async {
  final mapFile = File('tool/pilimax/fork_map.tsv');
  if (!mapFile.existsSync()) {
    stderr.writeln('fork map not found: ${mapFile.path}');
    exit(1);
  }

  final lines = mapFile
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  var drift = 0;
  for (final line in lines) {
    final columns = line.split('\t');
    if (columns.length != 3) {
      stderr.writeln('malformed fork map line: $line');
      exit(1);
    }
    final upstreamPath = columns[0];
    final forkPath = columns[1];
    final snapshotSha = columns[2];

    final resolved = await Process.run(
      'git',
      ['rev-parse', 'upstream/main:$upstreamPath'],
    );
    final currentSha = (resolved.stdout as String).trim();
    if (resolved.exitCode != 0 || currentSha.isEmpty) {
      stderr.writeln('cannot resolve upstream/main:$upstreamPath');
      continue;
    }

    if (currentSha == snapshotSha) {
      continue;
    }
    drift++;
    stdout.writeln('DRIFT $upstreamPath -> $forkPath');

    final history = await Process.run(
      'git',
      ['log', '--oneline', '-n', '10', 'upstream/main', '--', upstreamPath],
    );
    final historyLines = (history.stdout as String).trimRight();
    if (historyLines.isNotEmpty) {
      stdout.writeln(historyLines);
    }
    stdout.writeln('');
  }

  if (drift > 0) {
    stderr.writeln(
      '$drift fork originals have moved on upstream/main; '
      'port the upstream changes into lib/pilimax/forks/.',
    );
    exit(1);
  }
  stdout.writeln(
    'All ${lines.length} fork originals are in sync with upstream/main.',
  );
}
