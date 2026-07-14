import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/purchase_models.dart';

class PurchaseApiClient {
  PurchaseApiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  bool get isConfigured =>
      AppConfig.purchaseEnabled && AppConfig.purchaseApiBaseUrl.isNotEmpty;

  Uri _uri(String path, [Map<String, String> query = const {}]) => Uri.parse(
    '${AppConfig.purchaseApiBaseUrl}$path',
  ).replace(queryParameters: query..removeWhere((_, v) => v.trim().isEmpty));

  Future<List<BestsellerSource>> sources({
    String contentType = 'physical_book',
  }) async {
    if (!isConfigured) {
      return const [];
    }
    final data = await _get('/api/v1/bestsellers/sources', {
      'content_type': contentType,
    });
    return (data as List)
        .whereType<Map>()
        .map((e) => BestsellerSource.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.enabled)
        .toList();
  }

  Future<List<String>> categories({
    String source = '',
    String contentType = 'physical_book',
  }) async {
    if (!isConfigured) {
      return const ['종합'];
    }
    final data = await _get('/api/v1/bestsellers/categories', {
      'source': source,
      'content_type': contentType,
    });
    return (data as List).map((e) => '$e').toList();
  }

  Future<(List<BestsellerBook>, DateTime?, String)> bestsellers({
    String source = '',
    String contentType = 'physical_book',
    String category = '',
    String readerTarget = '',
    int page = 1,
    int pageSize = 30,
  }) async {
    if (!isConfigured) {
      return (const <BestsellerBook>[], null, '구매 서버 주소가 설정되지 않았습니다.');
    }
    final data = await _get('/api/v1/bestsellers', {
      'source': source,
      'content_type': contentType,
      'category': category,
      'reader_target': readerTarget,
      'page': '$page',
      'page_size': '$pageSize',
    });
    final map = Map<String, dynamic>.from(data as Map);
    final items = (map['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => BestsellerBook.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (
      items,
      DateTime.tryParse('${map['last_success_at'] ?? ''}'),
      '${map['safe_message'] ?? ''}',
    );
  }

  Future<(List<PurchaseOffer>, String, bool)> offers({
    String isbn13 = '',
    String isbn10 = '',
    String title = '',
    String author = '',
    String contentType = 'physical_book',
    String sourceItemId = '',
  }) async {
    if (!isConfigured) {
      return (const <PurchaseOffer>[], '구매 서버 주소가 설정되지 않았습니다.', false);
    }
    final data = await _get('/api/v1/purchase/offers', {
      'isbn13': isbn13,
      'isbn10': isbn10,
      'title': title,
      'author': author,
      'content_type': contentType,
      'source_item_id': sourceItemId,
    });
    final map = Map<String, dynamic>.from(data as Map);
    final offers = (map['offers'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PurchaseOffer.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (offers, '${map['safe_message'] ?? ''}', map['stale'] == true);
  }

  Future<(List<PurchaseFormatCandidate>, String)> formatCandidates({
    String targetContentType = 'physical_book',
    String title = '',
    String author = '',
    String publisher = '',
    String isbn13 = '',
    String isbn10 = '',
    String sourceItemId = '',
  }) async {
    if (!isConfigured) {
      return (const <PurchaseFormatCandidate>[], '구매 서버 주소가 설정되어 있지 않습니다.');
    }
    final data = await _get('/api/v1/purchase/format-candidates', {
      'target_content_type': targetContentType,
      'title': title,
      'author': author,
      'publisher': publisher,
      'isbn13': isbn13,
      'isbn10': isbn10,
      'source_item_id': sourceItemId,
    });
    final map = Map<String, dynamic>.from(data as Map);
    final candidates = (map['candidates'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (e) => PurchaseFormatCandidate.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
    return (candidates, '${map['safe_message'] ?? ''}');
  }

  Future<Object> _get(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final response = await _client
        .get(_uri(path, Map<String, String>.from(query)))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('구매 서버 연결 실패');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
