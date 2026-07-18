import 'dart:async';

typedef PlPlayerSourcePrepare<P extends Object> =
    Future<PlPlayerPreparedSource<P>?> Function(
      PlPlayerSourceAttempt<P> attempt,
    );

final class PlPlayerSourceTimeouts {
  const PlPlayerSourceTimeouts({
    this.prepare = const Duration(seconds: 30),
    this.open = const Duration(seconds: 30),
    this.initialize = const Duration(seconds: 15),
    this.refresh = const Duration(seconds: 30),
    this.retry = const Duration(seconds: 40),
    this.activeOperation = const Duration(seconds: 15),
    this.abort = const Duration(seconds: 3),
  });

  final Duration prepare;
  final Duration open;
  final Duration initialize;
  final Duration refresh;
  final Duration retry;
  final Duration activeOperation;
  final Duration abort;
}

final class _SourceAttemptSuperseded implements Exception {
  const _SourceAttemptSuperseded();
}

final class _SourceRetryRequest<P extends Object> {
  const _SourceRetryRequest({
    required this.lease,
    required this.delay,
    required this.operation,
    required this.onError,
  });

  final PlPlayerSourceLease<P> lease;
  final Duration delay;
  final FutureOr<void> Function(PlPlayerSourceLease<P> lease) operation;
  final void Function(Object error, StackTrace stackTrace)? onError;
}

/// Owns the complete lifetime of a player source: generation invalidation,
/// serialized prepare/open/initialize work, active ownership, player event
/// subscriptions, retries and source-scoped timers/subscriptions.
final class PlPlayerSourceCoordinator<P extends Object> {
  PlPlayerSourceCoordinator({
    required this._currentPlayer,
    this._onSourceInvalidated,
    this.timeouts = const PlPlayerSourceTimeouts(),
  });

  final P? Function() _currentPlayer;
  final void Function()? _onSourceInvalidated;
  final PlPlayerSourceTimeouts timeouts;

  int _generation = 0;
  int? _activeGeneration;
  P? _activePlayer;
  Object? _activeOwner;
  bool _disposed = false;
  bool _processing = false;
  Future<void> _queue = Future<void>.value();
  PlPlayerSourceAttempt<P>? _currentAttempt;

  final List<StreamSubscription<dynamic>> _listenerSubscriptions = [];
  final Set<StreamSubscription<dynamic>> _sourceSubscriptions = {};
  final Set<Timer> _sourceTimers = {};
  Timer? _retryTimer;
  int? _retryGeneration;
  bool _retryInFlight = false;
  _SourceRetryRequest<P>? _pendingRetry;

  int get currentGeneration => _generation;
  int? get activeGeneration => _activeGeneration;
  P? get activePlayer => _activePlayer;
  bool get processing => _processing;
  bool get isDisposed => _disposed;

  bool isCurrent(int generation) => !_disposed && generation == _generation;

  bool isActive(int generation) =>
      isCurrent(generation) &&
      _activeGeneration == generation &&
      identical(_activePlayer, _currentPlayer());

  bool isOwnerActive(Object owner) =>
      _activeGeneration != null &&
      identical(_activeOwner, owner) &&
      isActive(_activeGeneration!);

  bool isPlayerCurrent(
    int generation,
    P player, {
    bool requireActive = false,
  }) => PlPlayerSourceLease<P>._(
    coordinator: this,
    generation: generation,
    player: player,
    owner: null,
  ).isCurrent(_currentPlayer(), requireActive: requireActive);

  PlPlayerSourceLease<P>? activeLease({int? generation}) {
    final activeGeneration = _activeGeneration;
    final player = _activePlayer;
    if (activeGeneration == null ||
        player == null ||
        (generation != null && generation != activeGeneration)) {
      return null;
    }
    final lease = PlPlayerSourceLease<P>._(
      coordinator: this,
      generation: activeGeneration,
      player: player,
      owner: _activeOwner,
    );
    return lease.isCurrent(_currentPlayer(), requireActive: true)
        ? lease
        : null;
  }

  PlPlayerSourceLease<P>? currentLease(P player) {
    if (!isCurrent(_generation) || !identical(player, _currentPlayer())) {
      return null;
    }
    return PlPlayerSourceLease<P>._(
      coordinator: this,
      generation: _generation,
      player: player,
      owner: _activeOwner,
    );
  }

  Future<bool> openSource({
    required Object owner,
    required PlPlayerSourcePrepare<P> prepare,
    void Function(
      Object error,
      StackTrace stackTrace,
      PlPlayerSourceAttempt<P> attempt,
    )?
    onError,
  }) {
    final attempt = _begin(owner);
    return _enqueue<bool>(() async {
      PlPlayerPreparedSource<P>? prepared;
      Future<PlPlayerPreparedSource<P>?>? prepareFuture;
      var committed = false;
      try {
        if (!attempt.isCurrent) return false;
        prepareFuture = Future<PlPlayerPreparedSource<P>?>.sync(
          () => prepare(attempt),
        );
        prepared = await _runAttemptStage<PlPlayerPreparedSource<P>?>(
          attempt: attempt,
          stage: 'prepare',
          timeout: timeouts.prepare,
          operation: () => prepareFuture!,
        );
        if (prepared == null) return false;

        final lease = attempt.bind(prepared.player);
        if (!lease.isCurrent(_currentPlayer())) {
          return false;
        }

        _replaceListenerSubscriptions(prepared.subscribe(lease));
        await _runAttemptStage<void>(
          attempt: attempt,
          stage: 'open',
          timeout: timeouts.open,
          operation: () => prepared!.open(lease),
        );
        if (!lease.isCurrent(_currentPlayer())) {
          return false;
        }

        _activeGeneration = attempt.generation;
        _activePlayer = prepared.player;
        _activeOwner = owner;
        prepared.didOpen(lease);
        if (!lease.isCurrent(_currentPlayer(), requireActive: true)) {
          return false;
        }

        await _runAttemptStage<void>(
          attempt: attempt,
          stage: 'initialize',
          timeout: timeouts.initialize,
          operation: () => prepared!.initialize(lease),
        );
        committed = lease.isCurrent(_currentPlayer(), requireActive: true);
        return committed;
      } catch (error, stackTrace) {
        if (error is! _SourceAttemptSuperseded && attempt.isCurrent) {
          try {
            onError?.call(error, stackTrace, attempt);
          } catch (_) {}
          _deactivate(attempt.generation);
        }
        return false;
      } finally {
        if (!committed) {
          if (prepared != null) {
            await _discard(attempt, prepared);
          } else {
            _discardLatePreparation(attempt, prepareFuture);
            await _abortAttempt(attempt);
          }
        }
        if (attempt.isCurrent) {
          _processing = false;
        }
      }
    });
  }

  Future<bool> refresh({
    int? generation,
    required Future<bool> Function(PlPlayerSourceLease<P> lease) open,
    required void Function(PlPlayerSourceLease<P> lease) didOpen,
  }) {
    final lease = activeLease(generation: generation);
    if (lease == null) return Future<bool>.value(false);
    final attempt = _attemptForLease(lease);
    if (attempt == null) return Future<bool>.value(false);
    return _enqueue<bool>(() async {
      try {
        if (!lease.isCurrent(_currentPlayer(), requireActive: true)) {
          return false;
        }
        final opened = await _runAttemptStage<bool>(
          attempt: attempt,
          stage: 'refresh',
          timeout: timeouts.refresh,
          operation: () => open(lease),
        );
        if (!opened ||
            !lease.isCurrent(_currentPlayer(), requireActive: true)) {
          return false;
        }
        didOpen(lease);
        return lease.isCurrent(_currentPlayer(), requireActive: true);
      } on _SourceAttemptSuperseded {
        await _abortAttempt(attempt);
        return false;
      } on TimeoutException {
        await _abortAttempt(attempt);
        _deactivate(lease.generation);
        return false;
      }
    });
  }

  Future<bool> runActive({
    int? generation,
    required Future<bool> Function(PlPlayerSourceLease<P> lease) operation,
  }) {
    final lease = activeLease(generation: generation);
    if (lease == null) return Future<bool>.value(false);
    final attempt = _attemptForLease(lease);
    if (attempt == null) return Future<bool>.value(false);
    return _enqueue<bool>(() async {
      try {
        if (!lease.isCurrent(_currentPlayer(), requireActive: true)) {
          return false;
        }
        final result = await _runAttemptStage<bool>(
          attempt: attempt,
          stage: 'active operation',
          timeout: timeouts.activeOperation,
          operation: () => operation(lease),
        );
        return result && lease.isCurrent(_currentPlayer(), requireActive: true);
      } on _SourceAttemptSuperseded {
        await _abortAttempt(attempt);
        return false;
      } on TimeoutException {
        await _abortAttempt(attempt);
        _deactivate(lease.generation);
        return false;
      }
    });
  }

  void scheduleRetry(
    PlPlayerSourceLease<P> lease,
    Duration delay,
    FutureOr<void> Function(PlPlayerSourceLease<P> lease) operation, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    if (!lease.isCurrent(_currentPlayer(), requireActive: true)) return;
    final request = _SourceRetryRequest<P>(
      lease: lease,
      delay: delay,
      operation: operation,
      onError: onError,
    );
    if (_retryGeneration != null) {
      if (_retryInFlight && _retryGeneration == lease.generation) {
        _pendingRetry = request;
      }
      return;
    }
    _scheduleRetryRequest(request);
  }

  void _scheduleRetryRequest(_SourceRetryRequest<P> request) {
    final lease = request.lease;
    if (!lease.isCurrent(_currentPlayer(), requireActive: true)) return;
    _retryGeneration = lease.generation;
    _retryTimer = Timer(request.delay, () async {
      _retryTimer = null;
      if (_retryGeneration != lease.generation) return;
      _retryInFlight = true;
      if (lease.isCurrent(_currentPlayer(), requireActive: true)) {
        final minimumRetryTimeout = timeouts.refresh + timeouts.abort;
        final retryTimeout = timeouts.retry < minimumRetryTimeout
            ? minimumRetryTimeout
            : timeouts.retry;
        try {
          await Future<void>.sync(
            () => request.operation(lease),
          ).timeout(retryTimeout);
        } catch (error, stackTrace) {
          if (request.onError case final handler?) {
            try {
              handler(error, stackTrace);
            } catch (handlerError, handlerStackTrace) {
              Zone.current.handleUncaughtError(
                handlerError,
                handlerStackTrace,
              );
            }
          } else {
            Zone.current.handleUncaughtError(error, stackTrace);
          }
        } finally {
          if (_retryGeneration == lease.generation) {
            _retryGeneration = null;
            _retryInFlight = false;
            final pending = _pendingRetry;
            _pendingRetry = null;
            if (pending != null) {
              _scheduleRetryRequest(pending);
            }
          }
        }
      } else if (_retryGeneration == lease.generation) {
        _retryGeneration = null;
        _retryInFlight = false;
        _pendingRetry = null;
      }
    });
  }

  T trackSourceTimer<T extends Timer>(T timer) {
    if (_disposed) {
      timer.cancel();
    } else {
      _sourceTimers.add(timer);
    }
    return timer;
  }

  void releaseSourceTimer(Timer? timer, {bool cancel = false}) {
    if (timer == null) return;
    _sourceTimers.remove(timer);
    if (cancel) timer.cancel();
  }

  T trackSourceSubscription<T extends StreamSubscription<dynamic>>(
    T subscription,
  ) {
    if (_disposed) {
      _ignoreFuture(subscription.cancel());
    } else {
      _sourceSubscriptions.add(subscription);
    }
    return subscription;
  }

  void releaseSourceSubscription(
    StreamSubscription<dynamic>? subscription, {
    bool cancel = false,
  }) {
    if (subscription == null) return;
    _sourceSubscriptions.remove(subscription);
    if (cancel) _ignoreFuture(subscription.cancel());
  }

  void invalidate() {
    if (_disposed) return;
    _currentAttempt?._invalidate();
    _currentAttempt = null;
    _generation++;
    _activeGeneration = null;
    _activePlayer = null;
    _activeOwner = null;
    _processing = false;
    _cancelRetry();
    _cancelListenerSubscriptions();
    _cancelSourceResources();
    _notifyInvalidated();
  }

  void dispose() {
    if (_disposed) return;
    invalidate();
    _disposed = true;
  }

  PlPlayerSourceAttempt<P> _begin(Object owner) {
    if (_disposed) {
      throw StateError('PlPlayer source coordinator is disposed');
    }
    _currentAttempt?._invalidate();
    _generation++;
    _activeGeneration = null;
    _activePlayer = null;
    _activeOwner = null;
    _processing = true;
    _cancelRetry();
    _cancelListenerSubscriptions();
    _cancelSourceResources();
    _notifyInvalidated();
    return _currentAttempt = PlPlayerSourceAttempt<P>._(
      coordinator: this,
      generation: _generation,
      owner: owner,
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final run = _queue
        .catchError((Object _, StackTrace _) {})
        .then<T>(
          (_) => operation(),
        );
    _queue = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return run;
  }

  PlPlayerSourceAttempt<P>? _attemptForLease(
    PlPlayerSourceLease<P> lease,
  ) {
    final attempt = _currentAttempt;
    return attempt != null && attempt.generation == lease.generation
        ? attempt
        : null;
  }

  Future<T> _runAttemptStage<T>({
    required PlPlayerSourceAttempt<P> attempt,
    required String stage,
    required Duration timeout,
    required Future<T> Function() operation,
  }) {
    if (!attempt.isCurrent) {
      return Future<T>.error(const _SourceAttemptSuperseded());
    }
    final stageFuture = Future<T>.sync(operation).timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'PlPlayer source $stage timed out after $timeout',
        timeout,
      ),
    );
    final invalidatedFuture = attempt.invalidated.then<T>(
      (_) => throw const _SourceAttemptSuperseded(),
    );
    return Future.any<T>([stageFuture, invalidatedFuture]);
  }

  void _replaceListenerSubscriptions(
    Iterable<StreamSubscription<dynamic>> subscriptions,
  ) {
    _cancelListenerSubscriptions();
    _listenerSubscriptions.addAll(subscriptions);
  }

  void _deactivate(int generation) {
    if (!isCurrent(generation)) return;
    _currentAttempt?._invalidate();
    _currentAttempt = null;
    _generation++;
    _activeGeneration = null;
    _activePlayer = null;
    _activeOwner = null;
    _processing = false;
    _cancelRetry();
    _cancelListenerSubscriptions();
    _cancelSourceResources();
    _notifyInvalidated();
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryGeneration = null;
    _retryInFlight = false;
    _pendingRetry = null;
  }

  void _cancelListenerSubscriptions() {
    for (final subscription in _listenerSubscriptions) {
      _ignoreFuture(subscription.cancel());
    }
    _listenerSubscriptions.clear();
  }

  void _cancelSourceResources() {
    for (final timer in _sourceTimers) {
      timer.cancel();
    }
    _sourceTimers.clear();
    for (final subscription in _sourceSubscriptions) {
      _ignoreFuture(subscription.cancel());
    }
    _sourceSubscriptions.clear();
  }

  Future<void> _discard(
    PlPlayerSourceAttempt<P> attempt,
    PlPlayerPreparedSource<P> prepared,
  ) async {
    final discard = prepared.discard;
    if (discard == null) {
      await _abortAttempt(attempt);
      return;
    }
    try {
      await Future<void>.sync(discard).timeout(timeouts.abort);
    } catch (_) {}
  }

  Future<void> _abortAttempt(PlPlayerSourceAttempt<P> attempt) async {
    try {
      await attempt.abort().timeout(timeouts.abort);
    } catch (_) {}
  }

  void _discardLatePreparation(
    PlPlayerSourceAttempt<P> attempt,
    Future<PlPlayerPreparedSource<P>?>? prepareFuture,
  ) {
    if (prepareFuture == null) return;
    _ignoreFuture(
      prepareFuture.then<void>(
        (latePrepared) async {
          if (latePrepared != null) {
            await _discard(attempt, latePrepared);
          }
        },
        onError: (Object _, StackTrace _) {},
      ),
    );
  }

  void _notifyInvalidated() {
    try {
      _onSourceInvalidated?.call();
    } catch (_) {}
  }

  void _ignoreFuture(Future<dynamic>? future) {
    if (future == null) return;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
  }
}

final class PlPlayerSourceAttempt<P extends Object> {
  PlPlayerSourceAttempt._({
    required this._coordinator,
    required this.generation,
    required this.owner,
  });

  final PlPlayerSourceCoordinator<P> _coordinator;
  final int generation;
  final Object owner;
  final Completer<void> _invalidation = Completer<void>();
  FutureOr<void> Function()? _abortCallback;
  Future<void>? _abortFuture;
  bool _abortRequested = false;

  bool get isCurrent =>
      !_invalidation.isCompleted && _coordinator.isCurrent(generation);

  Future<void> get invalidated => _invalidation.future;

  /// Registers attempt-scoped cancellation cleanup before the first await.
  ///
  /// The callback must be idempotent. A timed-out prepare can be aborted
  /// before it later returns a [PlPlayerPreparedSource]; that late source's
  /// [PlPlayerPreparedSource.discard] is then also invoked for resources
  /// created after cancellation was requested.
  void registerAbort(FutureOr<void> Function() callback) {
    if (_abortCallback != null) {
      throw StateError('Source attempt abort callback is already registered');
    }
    _abortCallback = callback;
    if (_abortRequested) {
      final future = _startAbort();
      unawaited(
        future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
  }

  Future<void> abort() {
    _abortRequested = true;
    return _startAbort();
  }

  Future<void> _startAbort() {
    final callback = _abortCallback;
    if (callback == null) return Future<void>.value();
    final existing = _abortFuture;
    if (existing != null) return existing;

    final completer = Completer<void>();
    _abortFuture = completer.future;
    Future<void>.sync(callback).then<void>(
      completer.complete,
      onError: completer.completeError,
    );
    return completer.future;
  }

  void _invalidate() {
    if (!_invalidation.isCompleted) {
      _invalidation.complete();
    }
  }

  PlPlayerSourceLease<P> bind(P player) => PlPlayerSourceLease<P>._(
    coordinator: _coordinator,
    generation: generation,
    player: player,
    owner: owner,
  );
}

final class PlPlayerSourceLease<P extends Object> {
  const PlPlayerSourceLease._({
    required this._coordinator,
    required this.generation,
    required this.player,
    required this.owner,
  });

  final PlPlayerSourceCoordinator<P> _coordinator;
  final int generation;
  final P player;
  final Object? owner;

  bool isCurrent(P? currentPlayer, {bool requireActive = false}) {
    if (!identical(player, currentPlayer)) return false;
    return requireActive
        ? _coordinator.isActive(generation)
        : _coordinator.isCurrent(generation);
  }
}

final class PlPlayerPreparedSource<P extends Object> {
  const PlPlayerPreparedSource({
    required this.player,
    required this.subscribe,
    required this.open,
    required this.didOpen,
    required this.initialize,
    this.discard,
  });

  final P player;
  final Iterable<StreamSubscription<dynamic>> Function(
    PlPlayerSourceLease<P> lease,
  )
  subscribe;
  final Future<void> Function(PlPlayerSourceLease<P> lease) open;
  final void Function(PlPlayerSourceLease<P> lease) didOpen;
  final Future<void> Function(PlPlayerSourceLease<P> lease) initialize;

  /// Releases resources owned by this prepared value. It may run after the
  /// attempt abort callback when prepare completes after cancellation, so
  /// shared native resources must use the same idempotent cleanup gate.
  final FutureOr<void> Function()? discard;
}
