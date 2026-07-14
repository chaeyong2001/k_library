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

  Future<List<BestsellerSource>> sources() async {
    if (!isConfigured) {
      return const [];
    }
    final data = await _get('/api/v1/bestsellers/sources');
    return (data as List)
        .whereType<Map>()
        .map((e) => BestsellerSource.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.enabled)
        .toList();
  }

  Future<List<String>> categories() async {
    if (!isConfigured) {
      return const ['종합'];
    }
    final data = await _get('/api/v1/bestsellers/categories');
    return (data as List).map((e) => '$e').toList();
  }

  Future<(List<BestsellerBook>, DateTime?, String)> bestsellers({
    String source = '',
    String category = '',
    String readerTarget = '',
  }) async {
    if (!isConfigured) {
      return (const <BestsellerBook>[], null, '구매 서버 주소가 설정되지 않았습니다.');
    }
    final data = await _get('/api/v1/bestsellers', {
      'source': source,
      'category': category,
      'reader_target': readerTarget,
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
  }) async {
    if (!isConfigured) {
      return (const <PurchaseOffer>[], '구매 서버 주소가 설정되지 않았습니다.', false);
    }
    final data = await _get('/api/v1/purchase/offers', {
      'isbn13': isbn13,
      'isbn10': isbn10,
      'title': title,
      'author': author,
    });
    final map = Map<String, dynamic>.from(data as Map);
    final offers = (map['offers'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PurchaseOffer.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (offers, '${map['safe_message'] ?? ''}', map['stale'] == true);
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
