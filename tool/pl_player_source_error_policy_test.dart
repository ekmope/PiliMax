import 'package:PiliMax/plugin/pl_player/pl_player_source_error_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const _networkContext = PlPlayerSourceErrorContext(
  primarySource: 'https://cdn.example/video.m4s?token=primary',
  isFileSource: false,
  isLive: false,
  onlyPlayAudio: false,
);

void main() {
  test('only an explicit matching primary URI is fatal while opening', () {
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: 'Failed to open https://cdn.example/video.m4s?token=redirected',
        context: _networkContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.fatalOpen,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event:
            'Can not open external file https://cdn.example/audio.m4s?token=x',
        context: _networkContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.retryVod,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event:
            'Can not open external file https://cdn.example/audio.m4s?token=x',
        context: const PlPlayerSourceErrorContext(
          primarySource: 'https://cdn.example/audio.m4s?token=primary',
          isFileSource: false,
          isLive: false,
          onlyPlayAudio: true,
        ),
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.fatalOpen,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event:
            'Failed to open "https://cdn.example/video.m4s?token=x": HTTP 403',
        context: _networkContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.fatalOpen,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: 'tcp: ffurl_read returned 0xffffff99',
        context: _networkContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.retryVod,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: 'TLS handshake timed out',
        context: _networkContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.retryVod,
    );
  });

  test('file, codec, suppressed and reportable errors keep old semantics', () {
    const fileContext = PlPlayerSourceErrorContext(
      primarySource: r'C:\media\video.m4s',
      isFileSource: true,
      isLive: false,
      onlyPlayAudio: false,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: r'Failed to open file C:\media\video.m4s',
        context: fileContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.fatalOpen,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: r'Failed to open file C:\media\video.m4s: No such file',
        context: fileContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.fatalOpen,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: r'Failed to open file C:\media\subtitle.ass',
        context: fileContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.ignore,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: 'Failed to open file /home/user/Video.m4s',
        context: const PlPlayerSourceErrorContext(
          primarySource: '/home/user/video.m4s',
          isFileSource: true,
          isLive: false,
          onlyPlayAudio: false,
        ),
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.ignore,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: 'Could not open codec h264_mediacodec',
        context: _networkContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.codecFallback,
    );
    expect(
      PlPlayerSourceErrorPolicy.classify(
        event: 'unknown mpv command error',
        context: _networkContext,
        phase: PlPlayerSourceErrorPhase.opening,
      ),
      PlPlayerSourceErrorAction.report,
    );
  });

  test('opening accumulator keeps fatal priority and bounded reports', () {
    final accumulator =
        PlPlayerOpeningErrorAccumulator(
            maxReportableErrors: 4,
          )
          ..add(
            PlPlayerSourceErrorAction.codecFallback,
            'Could not open codec h264',
          )
          ..add(
            PlPlayerSourceErrorAction.codecFallback,
            'Could not open codec duplicate',
          );
    for (var i = 0; i < 1000; i++) {
      accumulator.add(
        PlPlayerSourceErrorAction.report,
        'noise $i https://cdn.example/video.m4s?token=$i',
      );
    }
    accumulator.add(
      PlPlayerSourceErrorAction.fatalOpen,
      'Failed to open primary',
    );

    expect(accumulator.hasFatalPrimaryError, isTrue);
    expect(accumulator.deferredErrors, hasLength(5));
    expect(
      accumulator.deferredErrors.where(
        (error) => error.action == PlPlayerSourceErrorAction.codecFallback,
      ),
      hasLength(1),
    );
    expect(
      accumulator.deferredErrors.every(
        (error) => !error.event.contains('token='),
      ),
      isTrue,
    );
  });

  test('sanitizer removes credentials, local paths and control characters', () {
    final sanitized = PlPlayerSourceErrorPolicy.sanitize(
      'open https://cdn.example/video.m4s?token=secret#part '
      r'from C:\Users\alice\private.m4s'
      '\u0000\r\n\tforged-prefix',
    );

    expect(sanitized, contains('https://cdn.example/video.m4s'));
    expect(sanitized, isNot(contains('token=')));
    expect(sanitized, contains('<local-media>'));
    expect(sanitized, isNot(contains('\u0000')));
    expect(sanitized, isNot(contains('\r')));
    expect(sanitized, isNot(contains('\n')));
    expect(sanitized, isNot(contains('\t')));
  });

  test('opening VOD retry does not depend on an active buffering event', () {
    expect(
      PlPlayerSourceErrorPolicy.shouldRunVodRetry(
        phase: PlPlayerSourceErrorPhase.opening,
        isBuffering: false,
        bufferedSeconds: 0,
      ),
      isTrue,
    );
    expect(
      PlPlayerSourceErrorPolicy.shouldRunVodRetry(
        phase: PlPlayerSourceErrorPhase.active,
        isBuffering: false,
        bufferedSeconds: 0,
      ),
      isFalse,
    );
  });
}
