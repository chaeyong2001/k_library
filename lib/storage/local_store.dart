import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/data4library_cache.dart';
import '../models/models.dart';

class LocalStore {
  static const _prefsKey = 'recommendation_prefs';
  static const _favoriteBooksKey = 'favorite_books';
  static const _favoriteLibrariesKey = 'favorite_libraries';
  static const _recentBooksKey = 'recent_books';
  static const _recentSearchesKey = 'recent_searches';
  static const _regionKey = 'default_region';
  static const _cachePrefix = 'cache:';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<RecommendationPrefs> loadRecommendationPrefs() async {
    final raw = (await _prefs).getString(_prefsKey);
    if (raw == null) return const RecommendationPrefs();
    return RecommendationPrefs.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> saveRecommendationPrefs(RecommendationPrefs value) async {
    await (await _prefs).setString(_prefsKey, jsonEncode(value.toJson()));
  }

  Future<String> loadRegion() async =>
      (await _prefs).getString(_regionKey) ?? '서울특별시';
  Future<void> saveRegion(String region) async =>
      (await _prefs).setString(_regionKey, region);

  Future<List<Book>> loadBooks(String key) async =>
      ((await _prefs).getStringList(key) ?? const [])
          .map(Book.fromEncoded)
          .toList();
  Future<List<LibraryBranch>> loadLibraries(String key) async =>
      ((await _prefs).getStringList(key) ?? const [])
          .map(LibraryBranch.fromEncoded)
          .toList();
  Future<List<String>> loadRecentSearches() async =>
      (await _prefs).getStringList(_recentSearchesKey) ?? const [];

  Future<List<Book>> favoriteBooks() => loadBooks(_favoriteBooksKey);
  Future<List<LibraryBranch>> favoriteLibraries() =>
      loadLibraries(_favoriteLibrariesKey);
  Future<List<Book>> recentBooks() => loadBooks(_recentBooksKey);

  Future<void> toggleFavoriteBook(Book book) async {
    final list = await favoriteBooks();
    final exists = list.any((e) => e.id == book.id);
    final next = exists
        ? list.where((e) => e.id != book.id).toList()
        : [book, ...list];
    await (await _prefs).setStringList(
      _favoriteBooksKey,
      next.map((e) => e.encode()).toList(),
    );
  }

  Future<void> toggleFavoriteLibrary(LibraryBranch library) async {
    final list = await favoriteLibraries();
    final exists = list.any((e) => e.id == library.id);
    final next = exists
        ? list.where((e) => e.id != library.id).toList()
        : [library, ...list];
    await (await _prefs).setStringList(
      _favoriteLibrariesKey,
      next.map((e) => e.encode()).toList(),
    );
  }

  Future<void> addRecentBook(Book book) async {
    final list = await recentBooks();
    final next = [
      book,
      ...list.where((e) => e.id != book.id),
    ].take(20).toList();
    await (await _prefs).setStringList(
      _recentBooksKey,
      next.map((e) => e.encode()).toList(),
    );
  }

  Future<void> addRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final list = await loadRecentSearches();
    await (await _prefs).setStringList(
      _recentSearchesKey,
      [trimmed, ...list.where((e) => e != trimmed)].take(10).toList(),
    );
  }

  Future<void> removeRecentSearch(String query) async {
    final list = await loadRecentSearches();
    await (await _prefs).setStringList(
      _recentSearchesKey,
      list.where((e) => e != query).toList(),
    );
  }

  Future<void> clearKey(String key) async => (await _prefs).remove(key);
  Future<void> clearRecentSearches() => clearKey(_recentSearchesKey);
  Future<void> clearRecentBooks() => clearKey(_recentBooksKey);
  Future<void> clearFavoriteBooks() => clearKey(_favoriteBooksKey);
  Future<void> clearFavoriteLibraries() => clearKey(_favoriteLibrariesKey);

  Future<T> cached<T>(
    String key,
    Duration ttl,
    Future<T> Function() loader,
    T Function(Object json) fromJson,
    Object Function(T value) toJson,
    {
    Duration? staleTtl,
    bool refreshStaleInBackground = false,
  }
  ) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_cachePrefix$key');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final savedAt = DateTime.tryParse(decoded['savedAt']?.toString() ?? '');
        if (savedAt != null) {
          final age = DateTime.now().difference(savedAt);
          if (age < ttl) {
            Data4LibraryPerfLog.cache(key: key, status: 'persistent-hit');
            return fromJson(decoded['value'] as Object);
          }
          if (staleTtl != null && age < staleTtl) {
            Data4LibraryPerfLog.cache(key: key, status: 'persistent-stale');
            final stale = fromJson(decoded['value'] as Object);
            if (refreshStaleInBackground) {
              unawaited(
                loader().then((value) {
                  return prefs.setString(
                    '$_cachePrefix$key',
                    jsonEncode({
                      'savedAt': DateTime.now().toIso8601String(),
                      'value': toJson(value),
                    }),
                  );
                }).catchError((_) => false),
              );
            }
            return stale;
          }
        }
      } catch (_) {
        await prefs.remove('$_cachePrefix$key');
      }
    }
    Data4LibraryPerfLog.cache(key: key, status: 'miss');
    final value = await loader();
    await prefs.setString(
      '$_cachePrefix$key',
      jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'value': toJson(value),
      }),
    );
    return value;
  }

  Future<void> clearCaches() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys().where(
      (e) => e.startsWith(_cachePrefix),
    )) {
      await prefs.remove(key);
    }
  }
}
