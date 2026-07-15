import 'package:flutter/foundation.dart';

class Data4LibraryCacheTtl {
  static const popularFresh = Duration(hours: 2);
  static const popularStale = Duration(hours: 12);
  static const recommendationFresh = Duration(hours: 1);
  static const recommendationStale = Duration(hours: 6);
  static const searchFresh = Duration(minutes: 10);
  static const bookDetailFresh = Duration(hours: 24);
  static const librariesFresh = Duration(hours: 24);
  static const holdingsFresh = Duration(minutes: 10);
  static const loanAvailabilityFresh = Duration(minutes: 1);
  static const staticCodeFresh = Duration(hours: 24);
}

class Data4LibraryCacheEntry<T extends Object> {
  const Data4LibraryCacheEntry({
    required this.value,
    required this.savedAt,
    required this.freshTtl,
    required this.staleTtl,
  });

  final T value;
  final DateTime savedAt;
  final Duration freshTtl;
  final Duration staleTtl;

  bool get isFresh => DateTime.now().difference(savedAt) < freshTtl;
  bool get isStaleUsable => DateTime.now().difference(savedAt) < staleTtl;
}

class Data4LibraryMemoryCache {
  Data4LibraryMemoryCache({this.maxEntries = 80});

  final int maxEntries;
  final Map<String, Data4LibraryCacheEntry<Object>> _entries = {};

  T? fresh<T extends Object>(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!entry.isStaleUsable) {
      _entries.remove(key);
      return null;
    }
    if (!entry.isFresh) return null;
    Data4LibraryPerfLog.cache(key: key, status: 'memory-hit');
    return entry.value as T;
  }

  T? stale<T extends Object>(String key) {
    final entry = _entries[key];
    if (entry == null || !entry.isStaleUsable) return null;
    Data4LibraryPerfLog.cache(key: key, status: 'memory-stale');
    return entry.value as T;
  }

  void set<T extends Object>(
    String key,
    T value, {
    required Duration freshTtl,
    Duration? staleTtl,
  }) {
    _entries[key] = Data4LibraryCacheEntry<Object>(
      value: value,
      savedAt: DateTime.now(),
      freshTtl: freshTtl,
      staleTtl: staleTtl ?? freshTtl,
    );
    _trim();
  }

  void remove(String key) => _entries.remove(key);

  void _trim() {
    if (_entries.length <= maxEntries) return;
    final keys = _entries.keys.toList();
    for (final key in keys.take(_entries.length - maxEntries)) {
      _entries.remove(key);
    }
  }
}

class Data4LibraryPerfLog {
  static void request({
    required String endpoint,
    required int httpMs,
    required int parseMs,
    required int totalMs,
    String cache = 'miss',
    String detail = '',
  }) {
    if (!kDebugMode) return;
    final suffix = detail.trim().isEmpty ? '' : ' $detail';
    debugPrint(
      '[PERF][Data4Library][$endpoint] '
      'http=${httpMs}ms parse=${parseMs}ms total=${totalMs}ms cache=$cache$suffix',
    );
  }

  static void cache({required String key, required String status}) {
    if (!kDebugMode) return;
    debugPrint('[PERF][Data4Library][cache] $status key=${_safeKey(key)}');
  }

  static void inFlight({required String key}) {
    if (!kDebugMode) return;
    debugPrint(
      '[PERF][Data4Library][in-flight] shared key=${_safeKey(key)}',
    );
  }

  static String _safeKey(String key) {
    final redacted = key
        .replaceAll(RegExp(r'authKey=[^:&]+'), 'authKey=***')
        .replaceAll(RegExp(r'query=[^:&]+'), 'query=***');
    return redacted.length > 160 ? '${redacted.substring(0, 160)}...' : redacted;
  }
}
