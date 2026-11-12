/// Keeps live chat bounded even when Flutter is not producing frames.
///
/// A rendered snapshot stays stable while new messages arrive. This lets a
/// reader scroll older messages without a trim changing its indices or anchor.
class LiveMessageBuffer<T> {
  LiveMessageBuffer({this.maxCount = 500, this.trimThreshold = 550})
    : assert(maxCount > 0),
      assert(trimThreshold >= maxCount);

  final int maxCount;
  final int trimThreshold;
  final List<T> _items = [];
  List<T>? _snapshot;
  int _revision = 0;

  int get revision => _revision;
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  List<T> get snapshot => _snapshot ??= List<T>.unmodifiable(_items);

  int add(T item) {
    _items.add(item);
    var removed = 0;
    if (_items.length > trimThreshold) {
      removed = _items.length - maxCount;
      _items.removeRange(0, removed);
    }
    _changed();
    return removed;
  }

  void addAll(Iterable<T> items) {
    // Enforce the limit during bulk ingestion as well as socket messages.
    for (final item in items) {
      add(item);
    }
  }

  void removeWhere(bool Function(T) test) {
    final oldLength = _items.length;
    _items.removeWhere(test);
    if (_items.length != oldLength) _changed();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _changed();
  }

  void _changed() {
    _revision++;
    _snapshot = null;
  }
}
