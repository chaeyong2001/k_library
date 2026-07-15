import '../config/app_config.dart';
import '../data/data4library_cache.dart';
import '../data/data4library_api_client.dart';
import '../data/demo_data_source.dart';
import '../models/models.dart';
import '../storage/local_store.dart';

class LibraryRepository {
  LibraryRepository({
    Data4LibraryApiClient? api,
    DemoDataSource? demo,
    LocalStore? store,
  }) : _api = api ?? Data4LibraryApiClient(),
       _demo = demo ?? DemoDataSource(),
       _store = store ?? LocalStore();

  final Data4LibraryApiClient _api;
  final DemoDataSource _demo;
  final LocalStore _store;
  final Map<String, Future<Object>> _inFlight = {};
  final Data4LibraryMemoryCache _memory = Data4LibraryMemoryCache();

  void close() => _api.close();

  Future<List<Book>> recommendations(
    RecommendationPrefs prefs, {
    String period = '최근 30일',
    bool forceRefresh = false,
    int limit = 5,
  }) async {
    if (AppConfig.isDemoMode) return _demo.recommendations(prefs, limit: limit);
    final cacheKey =
        '${AppConfig.dataMode}:recommendation:age=${_keyPart(prefs.ageGroup)}:gender=${_keyPart(prefs.gender)}:genres=${prefs.genres.map(_keyPart).join('|')}:period=${_keyPart(period)}:limit=$limit';
    if (!forceRefresh) {
      final memory = _memory.fresh<List<Book>>(cacheKey);
      if (memory != null) return memory;
    } else {
      _memory.remove(cacheKey);
    }
    return _dedupe(cacheKey, () {
      if (forceRefresh) {
        return _loadRecommendationsFromSource(
          prefs,
          period: period,
          forceRefresh: true,
          limit: limit,
        );
      }
      return _store.cached<List<Book>>(
        cacheKey,
        Data4LibraryCacheTtl.recommendationFresh,
        () => _loadRecommendationsFromSource(
          prefs,
          period: period,
          forceRefresh: false,
          limit: limit,
        ),
        _booksFromJson,
        (value) => value.map((e) => e.toJson()).toList(),
        staleTtl: Data4LibraryCacheTtl.recommendationStale,
        refreshStaleInBackground: true,
      ).then((value) {
        _memory.set(
          cacheKey,
          value,
          freshTtl: Data4LibraryCacheTtl.recommendationFresh,
          staleTtl: Data4LibraryCacheTtl.recommendationStale,
        );
        return value;
      });
    });
  }

  Future<List<Book>> _loadRecommendationsFromSource(
    RecommendationPrefs prefs, {
    required String period,
    required bool forceRefresh,
    required int limit,
  }) async {
    final selectedGenres = prefs.genres.isEmpty ? const ['전체'] : prefs.genres;
    final results = <Book>[];
    for (final genre in selectedGenres) {
      final books = await popularBooks(
        ageGroup: prefs.ageGroup,
        gender: prefs.gender,
        genre: genre,
        period: period,
        forceRefresh: forceRefresh,
        pageSize: limit.clamp(20, 50).toInt(),
      );
      for (final book in books) {
        if (!results.any((e) => e.isbn == book.isbn)) {
          results.add(
            book.copyWith(
              reason:
                  '${prefs.ageGroup} ${prefs.gender == '전체' ? '' : prefs.gender} $genre 인기 대출도서 기반',
            ),
          );
        }
        if (results.length >= limit) return results;
      }
    }
    if (results.length < 3) {
      final relaxed = await popularBooks(
        ageGroup: prefs.ageGroup,
        gender: prefs.gender,
        period: period,
        forceRefresh: forceRefresh,
        pageSize: limit.clamp(20, 50).toInt(),
      );
      for (final book in relaxed) {
        if (!results.any((e) => e.isbn == book.isbn)) {
          results.add(
            book.copyWith(reason: '조건 완화: ${prefs.ageGroup} 인기 대출도서 기반'),
          );
        }
        if (results.length >= limit) break;
      }
    }
    return results.take(limit).toList();
  }

  Future<List<Book>> popularBooks({
    String? ageGroup,
    String? gender,
    String? genre,
    String period = '최근 30일',
    bool forceRefresh = false,
    int pageSize = 20,
  }) async {
    final cacheKey =
        '${AppConfig.dataMode}:popular-loan:age=${_keyPart(ageGroup)}:gender=${_keyPart(gender)}:genre=${_keyPart(genre)}:period=${_keyPart(period)}:page=1:size=$pageSize:date=${DateTime.now().toIso8601String().substring(0, 10)}';
    if (!forceRefresh) {
      final memory = _memory.fresh<List<Book>>(cacheKey);
      if (memory != null) return memory;
    } else {
      _memory.remove(cacheKey);
    }
    return _dedupe(cacheKey, () {
      if (forceRefresh) {
        return _loadPopularFromSource(
          ageGroup: ageGroup,
          gender: gender,
          genre: genre,
          period: period,
          pageSize: pageSize,
        );
      }
      return _store.cached<List<Book>>(
        cacheKey,
        Data4LibraryCacheTtl.popularFresh,
        () => _loadPopularFromSource(
          ageGroup: ageGroup,
          gender: gender,
          genre: genre,
          period: period,
          pageSize: pageSize,
        ),
        _booksFromJson,
        (value) => value.map((e) => e.toJson()).toList(),
        staleTtl: Data4LibraryCacheTtl.popularStale,
        refreshStaleInBackground: true,
      ).then((value) {
        _memory.set(
          cacheKey,
          value,
          freshTtl: Data4LibraryCacheTtl.popularFresh,
          staleTtl: Data4LibraryCacheTtl.popularStale,
        );
        return value;
      });
    });
  }

  Future<List<Book>> _loadPopularFromSource({
    String? ageGroup,
    String? gender,
    String? genre,
    required String period,
    int pageSize = 20,
  }) async {
    if (AppConfig.isDemoMode) {
      return _demo.popular(ageGroup: ageGroup, gender: gender, genre: genre);
    }
    return _api.popularBooks(
      PopularBookFilter(
        ageGroup: ageGroup,
        gender: gender,
        genre: genre,
        period: period,
      ),
      pageSize: pageSize,
    );
  }

  Future<List<Book>> searchBooks(String query) async {
    final normalized = normalizeIsbn(query).isNotEmpty
        ? normalizeIsbn(query)
        : query.trim();
    final cacheKey = '${AppConfig.dataMode}:book-search:query=${_keyPart(normalized)}:page=1:size=20';
    final memory = _memory.fresh<List<Book>>(cacheKey);
    if (memory != null) return memory;
    return _dedupe(
      cacheKey,
      () => _store.cached<List<Book>>(
        cacheKey,
        Data4LibraryCacheTtl.searchFresh,
        () async {
          if (AppConfig.isDemoMode) return _demo.searchBooks(normalized);
          return _api.searchBooks(normalized);
        },
        _booksFromJson,
        (value) => value.map((e) => e.toJson()).toList(),
      ).then((value) {
        _memory.set(cacheKey, value, freshTtl: Data4LibraryCacheTtl.searchFresh);
        return value;
      }),
    );
  }

  Future<List<LibraryHolding>> holdings(
    String isbn, {
    required String region,
  }) async {
    final normalized = normalizeIsbn(isbn);
    if (AppConfig.isDemoMode) return _demo.holdings(normalized);
    final cacheKey =
        '${AppConfig.dataMode}:holdings:isbn=${_keyPart(normalized)}:region=${_keyPart(region)}';
    final memory = _memory.fresh<List<LibraryHolding>>(cacheKey);
    if (memory != null) return memory;
    return _dedupe(
      cacheKey,
      () => _api.holdings(isbn: normalized, region: region).then((value) {
        _memory.set(
          cacheKey,
          value,
          freshTtl: Data4LibraryCacheTtl.loanAvailabilityFresh,
        );
        return value;
      }),
    );
  }

  Future<List<LibraryBranch>> libraries({
    String? region,
    String? query,
    bool forceRefresh = false,
  }) async {
    final cacheKey =
        '${AppConfig.dataMode}:library-search:region=${_keyPart(region)}:query=${_keyPart(query)}:page=1:size=60';
    if (!forceRefresh) {
      final memory = _memory.fresh<List<LibraryBranch>>(cacheKey);
      if (memory != null) return memory;
    } else {
      _memory.remove(cacheKey);
    }
    return _dedupe(
      cacheKey,
      () {
        Future<List<LibraryBranch>> loadFromSource() async {
          if (AppConfig.isDemoMode) {
            return _demo.libraryList(region: region, query: query);
          }
          return _api.libraries(region: region, query: query);
        }

        final future = forceRefresh
            ? loadFromSource()
            : _store.cached<List<LibraryBranch>>(
                cacheKey,
                Data4LibraryCacheTtl.librariesFresh,
                loadFromSource,
                (json) => (json as List)
                    .whereType<Map>()
                    .map(
                      (e) => LibraryBranch.fromJson(
                        Map<String, dynamic>.from(e),
                        isDemo: AppConfig.isDemoMode,
                      ),
                    )
                    .toList(),
                (value) => value.map((e) => e.toJson()).toList(),
              );
        return future.then((value) {
          _memory.set(
            cacheKey,
            value,
            freshTtl: Data4LibraryCacheTtl.librariesFresh,
          );
          return value;
        });
      },
    );
  }

  Future<T> _dedupe<T extends Object>(
    String key,
    Future<T> Function() loader,
  ) async {
    final existing = _inFlight[key];
    if (existing != null) {
      Data4LibraryPerfLog.inFlight(key: key);
      return existing as Future<T>;
    }
    final future = loader();
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  List<Book> _booksFromJson(Object json) => (json as List)
      .whereType<Map>()
      .map(
        (e) => Book.fromJson(
          Map<String, dynamic>.from(e),
          isDemo: AppConfig.isDemoMode,
        ),
      )
      .toList();

  String _keyPart(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? 'all' : Uri.encodeComponent(text);
  }
}
