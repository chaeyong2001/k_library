import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'data4library_cache.dart';
import '../config/genre_mapping.dart';
import '../models/models.dart';

class PopularBookFilter {
  const PopularBookFilter({
    this.ageGroup,
    this.gender,
    this.genre,
    this.period = '최근 30일',
  });

  final String? ageGroup;
  final String? gender;
  final String? genre;
  final String period;
}

class Data4LibraryApiClient {
  Data4LibraryApiClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Uri _uri(String path, Map<String, String?> query) =>
      Uri.parse('${AppConfig.data4LibraryBaseUrl}/$path').replace(
        queryParameters: {
          'authKey': AppConfig.data4LibraryAuthKey,
          'format': 'json',
          for (final entry in query.entries)
            if (entry.value != null && entry.value!.trim().isNotEmpty)
              entry.key: entry.value!,
        },
      );

  Future<List<Book>> popularBooks(
    PopularBookFilter filter, {
    int page = 1,
    int pageSize = 20,
  }) async {
    _requireKey();
    final range = _dateRange(filter.period);
    final uri = _uri('loanItemSrch', {
      'startDt': range.$1,
      'endDt': range.$2,
      'age': ageCodeOf(filter.ageGroup),
      'gender': genderCodeOf(filter.gender),
      'kdc': genreCodeOf(filter.genre),
      'pageNo': '$page',
      'pageSize': '$pageSize',
    });
    final json = await _getJson(
      uri,
      endpoint: 'popular-loan',
      detail: 'page=$page size=$pageSize',
    );
    final parse = Stopwatch()..start();
    final books = _extractWrappedList(json, 'docs', 'doc')
        .map((e) => Book.fromJson(e, reason: _reason(filter), isDemo: false))
        .toList();
    parse.stop();
    _logParse(endpoint: 'popular-loan-map', parseMs: parse.elapsedMilliseconds);
    return books;
  }

  Future<List<Book>> searchBooks(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    _requireKey();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final uri = _uri('srchBooks', {
      'keyword': trimmed,
      'pageNo': '$page',
      'pageSize': '$pageSize',
    });
    final json = await _getJson(
      uri,
      endpoint: 'book-search',
      detail: 'page=$page size=$pageSize',
    );
    final parse = Stopwatch()..start();
    final books = _extractWrappedList(
      json,
      'docs',
      'doc',
    ).map((e) => Book.fromJson(e, isDemo: false)).toList();
    parse.stop();
    _logParse(endpoint: 'book-search-map', parseMs: parse.elapsedMilliseconds);
    return books;
  }

  Future<List<LibraryBranch>> librariesByBook({
    required String isbn,
    required String region,
    int pageSize = 80,
  }) async {
    _requireKey();
    final normalized = normalizeIsbn(isbn).split(',').first.trim();
    if (normalized.isEmpty) return const [];
    final uri = _uri('libSrchByBook', {
      'isbn': normalized,
      'region': regionCodeOf(region),
      'pageNo': '1',
      'pageSize': '$pageSize',
    });
    final json = await _getJson(
      uri,
      endpoint: 'libraries-by-book',
      detail: 'isbn=${_safeIsbn(normalized)} size=$pageSize',
    );
    final parse = Stopwatch()..start();
    final libraries = _extractWrappedList(
      json,
      'libs',
      'lib',
    ).map((e) => LibraryBranch.fromJson(e, isDemo: false)).toList();
    parse.stop();
    _logParse(
      endpoint: 'libraries-by-book-map',
      parseMs: parse.elapsedMilliseconds,
    );
    return libraries;
  }

  Future<LoanStatus> bookExist({
    required String isbn,
    required String libCode,
  }) async {
    _requireKey();
    final normalized = normalizeIsbn(isbn).split(',').first.trim();
    if (normalized.length != 13 || libCode.isEmpty) {
      return LoanStatus.checkRequired;
    }
    final uri = _uri('bookExist', {'isbn13': normalized, 'libCode': libCode});
    final json = await _getJson(
      uri,
      endpoint: 'loan-availability',
      detail: 'isbn=${_safeIsbn(normalized)} lib=$libCode',
    );
    final result =
        (((json['response'] as Map?)?['result']) as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final hasBook = '${result['hasBook'] ?? ''}'.toUpperCase();
    final loanAvailable = '${result['loanAvailable'] ?? ''}'.toUpperCase();
    if (hasBook == 'N') return LoanStatus.unavailable;
    if (loanAvailable == 'Y') return LoanStatus.available;
    if (loanAvailable == 'N') return LoanStatus.loaned;
    return LoanStatus.checkRequired;
  }

  Future<List<LibraryHolding>> holdings({
    required String isbn,
    required String region,
  }) async {
    final total = Stopwatch()..start();
    final libs = await librariesByBook(isbn: isbn, region: region);
    final limited = libs.take(24).toList();
    final checked = <LibraryHolding>[];
    for (var index = 0; index < limited.length; index += 4) {
      final batch = limited.skip(index).take(4).toList();
      final results = await Future.wait(
        batch.map((lib) async {
          LoanStatus status;
          try {
            status = await bookExist(isbn: isbn, libCode: lib.id);
          } catch (_) {
            status = LoanStatus.checkRequired;
          }
          return LibraryHolding(
            library: lib,
            status: status,
            checkedAt: DateTime.now(),
          );
        }),
      );
      checked.addAll(results);
    }
    total.stop();
    Data4LibraryPerfLog.request(
      endpoint: 'book-detail-holdings',
      httpMs: total.elapsedMilliseconds,
      parseMs: 0,
      totalMs: total.elapsedMilliseconds,
      detail: 'libraries=${limited.length}',
    );
    return checked;
  }

  Future<List<LibraryBranch>> libraries({
    String? region,
    String? query,
    int page = 1,
    int pageSize = 60,
  }) async {
    _requireKey();
    final uri = _uri('libSrch', {
      'region': regionCodeOf(region),
      'pageNo': '$page',
      'pageSize': '$pageSize',
    });
    final json = await _getJson(
      uri,
      endpoint: 'library-search',
      detail: 'page=$page size=$pageSize',
    );
    final parse = Stopwatch()..start();
    final q = query?.trim() ?? '';
    final libs = _extractWrappedList(
      json,
      'libs',
      'lib',
    ).map((e) => LibraryBranch.fromJson(e, isDemo: false)).toList();
    final filtered = q.isEmpty
        ? libs
        : libs
        .where((lib) => lib.name.contains(q) || lib.address.contains(q))
        .toList();
    parse.stop();
    _logParse(endpoint: 'library-search-map', parseMs: parse.elapsedMilliseconds);
    return filtered;
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    required String endpoint,
    String detail = '',
  }) async {
    final total = Stopwatch()..start();
    final httpWatch = Stopwatch()..start();
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    httpWatch.stop();
    final parseWatch = Stopwatch()..start();
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    parseWatch.stop();
    total.stop();
    Data4LibraryPerfLog.request(
      endpoint: endpoint,
      httpMs: httpWatch.elapsedMilliseconds,
      parseMs: parseWatch.elapsedMilliseconds,
      totalMs: total.elapsedMilliseconds,
      detail: detail,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('API 응답 오류: ${response.statusCode}');
    }
    if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
    final responseBody = decoded['response'];
    if (responseBody is Map && responseBody['errCode'] != null) {
      throw ApiException('${responseBody['error'] ?? responseBody['errCode']}');
    }
    return decoded;
  }

  void _logParse({required String endpoint, required int parseMs}) {
    Data4LibraryPerfLog.request(
      endpoint: endpoint,
      httpMs: 0,
      parseMs: parseMs,
      totalMs: parseMs,
    );
  }

  String _safeIsbn(String value) {
    if (value.length <= 4) return value;
    return '...${value.substring(value.length - 4)}';
  }

  List<Map<String, dynamic>> _extractWrappedList(
    Map<String, dynamic> source,
    String listKey,
    String itemKey,
  ) {
    final response = source['response'];
    if (response is! Map) return const [];
    final list = response[listKey];
    if (list is! List) return const [];
    return list
        .map((item) {
          if (item is Map && item[itemKey] is Map) {
            return Map<String, dynamic>.from(item[itemKey] as Map);
          }
          if (item is Map) return Map<String, dynamic>.from(item);
          return <String, dynamic>{};
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  (String, String) _dateRange(String period) {
    final now = DateTime.now();
    final days = switch (period) {
      '최근 7일' => 7,
      '최근 90일' => 90,
      _ => 30,
    };
    final start = now.subtract(Duration(days: days));
    return (_date(start), _date(now));
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _reason(PopularBookFilter filter) {
    final parts = [
      filter.ageGroup,
      filter.gender,
      filter.genre,
    ].where((e) => e != null && e != '전체').join(' ');
    return parts.isEmpty
        ? '${filter.period} 인기 대출도서'
        : '${filter.period} $parts 인기 대출도서';
  }

  void _requireKey() {
    if (!AppConfig.hasApiKey) throw ApiException('도서관 정보나루 API 키가 설정되지 않았습니다.');
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
