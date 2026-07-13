import '../config/app_config.dart';
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

  Future<List<Book>> recommendations(
    RecommendationPrefs prefs, {
    String period = '최근 30일',
    bool forceRefresh = false,
  }) async {
    if (AppConfig.isDemoMode) return _demo.recommendations(prefs);
    final selectedGenres = prefs.genres.isEmpty ? const ['전체'] : prefs.genres;
    final results = <Book>[];
    for (final genre in selectedGenres) {
      final books = await popularBooks(
        ageGroup: prefs.ageGroup,
        gender: prefs.gender,
        genre: genre,
        period: period,
        forceRefresh: forceRefresh,
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
        if (results.length >= 5) return results;
      }
    }
    if (results.length < 3) {
      final relaxed = await popularBooks(
        ageGroup: prefs.ageGroup,
        gender: prefs.gender,
        period: period,
        forceRefresh: forceRefresh,
      );
      for (final book in relaxed) {
        if (!results.any((e) => e.isbn == book.isbn)) {
          results.add(
            book.copyWith(reason: '조건 완화: ${prefs.ageGroup} 인기 대출도서 기반'),
          );
        }
        if (results.length >= 5) break;
      }
    }
    return results.take(5).toList();
  }

  Future<List<Book>> popularBooks({
    String? ageGroup,
    String? gender,
    String? genre,
    String period = '최근 30일',
    bool forceRefresh = false,
  }) async {
    final cacheKey =
        '${AppConfig.dataMode}:popular:$ageGroup:$gender:$genre:$period:${DateTime.now().toIso8601String().substring(0, 10)}';
    return _dedupe(cacheKey, () {
      if (forceRefresh) {
        return _loadPopularFromSource(
          ageGroup: ageGroup,
          gender: gender,
          genre: genre,
          period: period,
        );
      }
      return _store.cached<List<Book>>(
        cacheKey,
        const Duration(hours: 6),
        () => _loadPopularFromSource(
          ageGroup: ageGroup,
          gender: gender,
          genre: genre,
          period: period,
        ),
        (json) => (json as List)
            .whereType<Map>()
            .map(
              (e) => Book.fromJson(
                Map<String, dynamic>.from(e),
                isDemo: AppConfig.isDemoMode,
              ),
            )
            .toList(),
        (value) => value.map((e) => e.toJson()).toList(),
      );
    });
  }

  Future<List<Book>> _loadPopularFromSource({
    String? ageGroup,
    String? gender,
    String? genre,
    required String period,
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
    );
  }

  Future<List<Book>> searchBooks(String query) async {
    final normalized = normalizeIsbn(query).isNotEmpty
        ? normalizeIsbn(query)
        : query.trim();
    final cacheKey = '${AppConfig.dataMode}:search:$normalized';
    return _dedupe(
      cacheKey,
      () => _store.cached<List<Book>>(
        cacheKey,
        const Duration(minutes: 20),
        () async {
          if (AppConfig.isDemoMode) return _demo.searchBooks(normalized);
          return _api.searchBooks(normalized);
        },
        (json) => (json as List)
            .whereType<Map>()
            .map(
              (e) => Book.fromJson(
                Map<String, dynamic>.from(e),
                isDemo: AppConfig.isDemoMode,
              ),
            )
            .toList(),
        (value) => value.map((e) => e.toJson()).toList(),
      ),
    );
  }

  Future<List<LibraryHolding>> holdings(
    String isbn, {
    required String region,
  }) async {
    final normalized = normalizeIsbn(isbn);
    if (AppConfig.isDemoMode) return _demo.holdings(normalized);
    return _dedupe(
      '${AppConfig.dataMode}:holdings:$normalized:$region',
      () => _api.holdings(isbn: normalized, region: region),
    );
  }

  Future<List<LibraryBranch>> libraries({String? region, String? query}) async {
    final cacheKey = '${AppConfig.dataMode}:libraries:$region:$query';
    return _dedupe(
      cacheKey,
      () => _store.cached<List<LibraryBranch>>(
        cacheKey,
        const Duration(days: 7),
        () async {
          if (AppConfig.isDemoMode) {
            return _demo.libraryList(region: region, query: query);
          }
          return _api.libraries(region: region, query: query);
        },
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
      ),
    );
  }

  Future<T> _dedupe<T extends Object>(
    String key,
    Future<T> Function() loader,
  ) async {
    final existing = _inFlight[key];
    if (existing != null) return existing as Future<T>;
    final future = loader();
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }
}
