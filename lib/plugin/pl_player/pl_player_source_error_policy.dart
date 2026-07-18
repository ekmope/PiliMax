enum PlPlayerSourceErrorPhase { opening, active }

enum PlPlayerSourceErrorAction {
  ignore,
  fatalOpen,
  retryLive,
  retryVod,
  codecFallback,
  report,
}

final class PlPlayerSourceErrorContext {
  const PlPlayerSourceErrorContext({
    required this.primarySource,
    required this.isFileSource,
    required this.isLive,
    required this.onlyPlayAudio,
  });

  final String primarySource;
  final bool isFileSource;
  final bool isLive;
  final bool onlyPlayAudio;
}

typedef PlPlayerDeferredSourceError = ({
  PlPlayerSourceErrorAction action,
  String event,
});

final class PlPlayerOpeningErrorAccumulator {
  PlPlayerOpeningErrorAccumulator({this.maxReportableErrors = 4})
    : assert(maxReportableErrors >= 0);

  final int maxReportableErrors;
  final List<PlPlayerDeferredSourceError> _deferredErrors = [];
  final Set<PlPlayerSourceErrorAction> _singleActions = {};
  final Set<String> _reportableErrors = {};
  bool _hasFatalPrimaryError = false;

  bool get hasFatalPrimaryError => _hasFatalPrimaryError;

  List<PlPlayerDeferredSourceError> get deferredErrors =>
      List<PlPlayerDeferredSourceError>.unmodifiable(_deferredErrors);

  void add(PlPlayerSourceErrorAction action, String event) {
    if (action == PlPlayerSourceErrorAction.fatalOpen) {
      _hasFatalPrimaryError = true;
      return;
    }
    if (action == PlPlayerSourceErrorAction.ignore) return;

    final sanitized = PlPlayerSourceErrorPolicy.sanitize(event);
    if (action == PlPlayerSourceErrorAction.report) {
      if (_reportableErrors.length >= maxReportableErrors ||
          !_reportableErrors.add(sanitized)) {
        return;
      }
    } else if (!_singleActions.add(action)) {
      return;
    }
    _deferredErrors.add((action: action, event: sanitized));
  }
}

abstract final class PlPlayerSourceErrorPolicy {
  static final RegExp _urlPattern = RegExp(
    r'https?://[^\s"<>]+',
    caseSensitive: false,
  );
  static final RegExp _fileUriPattern = RegExp(
    r'file:///[^\s"<>]+',
    caseSensitive: false,
  );
  static final RegExp _windowsPathPattern = RegExp(
    r'(^|[\s"(])([A-Za-z]:[\\/][^\s"<>]+)',
    multiLine: true,
  );
  static final RegExp _posixUserPathPattern = RegExp(
    r'(^|\s)/(?:home|Users|private|var|tmp|storage|data)/[^\s"<>]+',
    multiLine: true,
  );
  static final RegExp _controlCharacterPattern = RegExp(
    r'[\x00-\x1F\x7F]',
  );

  static PlPlayerSourceErrorAction classify({
    required String event,
    required PlPlayerSourceErrorContext context,
    required PlPlayerSourceErrorPhase phase,
    bool silenceRecoverable = false,
    bool hasPlaybackProgress = false,
  }) {
    if (phase == PlPlayerSourceErrorPhase.opening &&
        _isExplicitPrimaryOpenFailure(event, context.primarySource)) {
      return PlPlayerSourceErrorAction.fatalOpen;
    }
    if (context.isFileSource && event.startsWith('Failed to open file')) {
      return PlPlayerSourceErrorAction.ignore;
    }
    if (phase == PlPlayerSourceErrorPhase.opening &&
        isTransientNetworkError(event)) {
      return context.isLive
          ? PlPlayerSourceErrorAction.retryLive
          : PlPlayerSourceErrorAction.retryVod;
    }
    if (phase == PlPlayerSourceErrorPhase.active && silenceRecoverable) {
      return PlPlayerSourceErrorAction.ignore;
    }

    final retryableOpenError = isSourceOpenRetryError(event);
    if (context.isLive) {
      return retryableOpenError
          ? PlPlayerSourceErrorAction.retryLive
          : PlPlayerSourceErrorAction.ignore;
    }
    if (retryableOpenError) {
      return PlPlayerSourceErrorAction.retryVod;
    }
    if (event.startsWith('Could not open codec')) {
      return PlPlayerSourceErrorAction.codecFallback;
    }
    if (context.onlyPlayAudio) {
      return PlPlayerSourceErrorAction.ignore;
    }
    if (event.startsWith('error running') ||
        event.startsWith('Failed to open .') ||
        event.startsWith('Cannot open') ||
        event.startsWith('Can not open')) {
      return PlPlayerSourceErrorAction.ignore;
    }
    if (phase == PlPlayerSourceErrorPhase.active &&
        hasPlaybackProgress &&
        isTransientNetworkError(event)) {
      return PlPlayerSourceErrorAction.ignore;
    }
    return PlPlayerSourceErrorAction.report;
  }

  static bool isSourceOpenRetryError(String event) =>
      event.startsWith('tcp: ffurl_read returned ') ||
      event.startsWith('Failed to open https://') ||
      event.startsWith('Failed to open http://') ||
      event.startsWith('Can not open external file https://') ||
      event.startsWith('Can not open external file http://');

  static bool isTransientNetworkError(String event) {
    final lowerEvent = event.toLowerCase();
    return lowerEvent.contains('tls') ||
        lowerEvent.contains('ssl') ||
        lowerEvent.contains('handshake') ||
        lowerEvent.contains('stream ends prematurely') ||
        lowerEvent.contains('unexpected end of file') ||
        lowerEvent.contains('ffurl_read returned') ||
        lowerEvent.contains('failed to open https://') ||
        lowerEvent.contains('failed to open http://') ||
        lowerEvent.contains('can not open external file https://') ||
        lowerEvent.contains('can not open external file http://') ||
        lowerEvent.contains('connection reset') ||
        lowerEvent.contains('connection aborted') ||
        lowerEvent.contains('network is unreachable') ||
        lowerEvent.contains('timed out');
  }

  static bool shouldRunVodRetry({
    required PlPlayerSourceErrorPhase phase,
    required bool isBuffering,
    required int bufferedSeconds,
  }) =>
      phase == PlPlayerSourceErrorPhase.opening ||
      (isBuffering && bufferedSeconds == 0);

  static String sanitize(String event) {
    var sanitized = event.replaceAll(_controlCharacterPattern, ' ');
    sanitized = sanitized.replaceAll(_fileUriPattern, '<local-media>');
    sanitized = sanitized.replaceAllMapped(_windowsPathPattern, (match) {
      return '${match.group(1) ?? ''}<local-media>';
    });
    sanitized = sanitized.replaceAllMapped(_posixUserPathPattern, (match) {
      return '${match.group(1) ?? ''}<local-media>';
    });
    sanitized = sanitized.replaceAllMapped(_urlPattern, (match) {
      final value = match.group(0)!;
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasAuthority) return '<redacted-url>';
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
          '$port${uri.path}';
    });
    if (sanitized.length > 512) {
      return '${sanitized.substring(0, 511)}…';
    }
    return sanitized;
  }

  static bool _isExplicitPrimaryOpenFailure(
    String event,
    String primarySource,
  ) {
    final target = _extractOpenTarget(event);
    if (target == null) return false;
    final targetIdentity = _sourceIdentity(target);
    final primaryIdentity = _sourceIdentity(primarySource);
    if (targetIdentity == primaryIdentity) return true;
    if (!targetIdentity.startsWith(primaryIdentity)) return false;
    final suffix = targetIdentity.substring(primaryIdentity.length);
    return RegExp(r'^\s*[:,;]\s*').hasMatch(suffix);
  }

  static String? _extractOpenTarget(String event) {
    const prefixes = ['Failed to open ', 'Cannot open ', 'Can not open '];
    for (final prefix in prefixes) {
      if (!event.startsWith(prefix)) continue;
      var target = event.substring(prefix.length).trim();
      if (target.startsWith('external file ')) {
        target = target.substring('external file '.length).trim();
      }
      if (target.startsWith('file ')) {
        target = target.substring('file '.length).trim();
      }
      if (target.startsWith('"') || target.startsWith("'")) {
        final quote = target[0];
        final closingQuote = target.indexOf(quote, 1);
        if (closingQuote > 1) {
          return target.substring(1, closingQuote);
        }
      }
      final networkTarget = RegExp(
        r'^https?://[^\s"<>]+',
        caseSensitive: false,
      ).firstMatch(target);
      if (networkTarget != null) {
        return networkTarget.group(0);
      }
      return target;
    }
    return null;
  }

  static String _sourceIdentity(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.hasAuthority) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
          '$port${uri.path}';
    }

    var normalized = trimmed;
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      normalized = Uri.decodeFull(uri.path);
    }
    normalized = normalized.replaceAll('\\', '/');
    if (normalized.length > 3 &&
        normalized.startsWith('/') &&
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized.substring(1))) {
      normalized = normalized.substring(1);
    }
    return RegExp(r'^[A-Za-z]:/').hasMatch(normalized)
        ? normalized.toLowerCase()
        : normalized;
  }
}
