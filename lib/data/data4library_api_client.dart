import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
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
    final json = await _getJson(uri);
    return _extractWrappedList(json, 'docs', 'doc')
        .map((e) => Book.fromJson(e, reason: _reason(filter), isDemo: false))
        .toList();
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
    final json = await _getJson(uri);
    return _extractWrappedList(
      json,
      'docs',
      'doc',
    ).map((e) => Book.fromJson(e, isDemo: false)).toList();
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
    final json = await _getJson(uri);
    return _extractWrappedList(
      json,
      'libs',
      'lib',
    ).map((e) => LibraryBranch.fromJson(e, isDemo: false)).toList();
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
    final json = await _getJson(uri);
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
    final libs = await librariesByBook(isbn: isbn, region: region);
    final limited = libs.take(24).toList();
    final checked = <LibraryHolding>[];
    for (final lib in limited) {
      LoanStatus status;
      try {
        status = await bookExist(isbn: isbn, libCode: lib.id);
      } catch (_) {
        status = LoanStatus.checkRequired;
      }
      checked.add(
        LibraryHolding(library: lib, status: status, checkedAt: DateTime.now()),
      );
    }
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
    final json = await _getJson(uri);
    final q = query?.trim() ?? '';
    final libs = _extractWrappedList(
      json,
      'libs',
      'lib',
    ).map((e) => LibraryBranch.fromJson(e, isDemo: false)).toList();
    if (q.isEmpty) return libs;
    return libs
        .where((lib) => lib.name.contains(q) || lib.address.contains(q))
        .toList();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
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
