import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../models/purchase_models.dart';

class AnalyticsEventType {
  static const homeBookOpen = 'home_book_open';
  static const librarySearchResultOpen = 'library_search_result_open';
  static const purchaseSearchResultOpen = 'purchase_search_result_open';
  static const bestsellerBookOpen = 'bestseller_book_open';
  static const purchaseDetailOpen = 'purchase_detail_open';
  static const formatTabChange = 'format_tab_change';
  static const alternateFormatCandidateOpen = 'alternate_format_candidate_open';
  static const outboundStoreClick = 'outbound_store_click';
  static const lowestPriceClick = 'lowest_price_click';
  static const librarySave = 'library_save';
  static const libraryRemove = 'library_remove';
}

class AnalyticsEntrySource {
  static const homeRecommendation = 'home_recommendation';
  static const homePopularLoan = 'home_popular_loan';
  static const librarySearch = 'library_search';
  static const purchaseSearch = 'purchase_search';
  static const physicalBestseller = 'physical_bestseller';
  static const ebookBestseller = 'ebook_bestseller';
  static const libraryDetail = 'library_detail';
  static const alternateFormatCandidate = 'alternate_format_candidate';
}

class AnalyticsService {
  AnalyticsService({http.Client? client}) : _client = client ?? http.Client();

  static const anonymousInstallIdKey = 'anonymous_install_id';
  static const _queueKey = 'analytics_pending_events_v1';
  static const _optOutKey = 'analytics_opt_out';
  static const _maxQueueSize = 100;
  static const _maxEventAge = Duration(days: 14);
  static const _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0+1',
  );

  final http.Client _client;
  final String sessionId = _uuidV4();
  SharedPreferences? _prefs;
  String? _anonymousInstallId;
  bool _flushing = false;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    var installId = prefs.getString(anonymousInstallIdKey);
    if (installId == null || installId.trim().isEmpty) {
      installId = _uuidV4();
      await prefs.setString(anonymousInstallIdKey, installId);
    }
    _anonymousInstallId = installId;
  }

  Future<void> trackBookOpen({
    required String eventType,
    required String entrySource,
    required Book book,
    String sourceScreen = '',
  }) {
    final isbn = _splitIsbn(book.isbn);
    return track(
      eventType: eventType,
      entrySource: entrySource,
      sourceScreen: sourceScreen,
      isbn13: isbn.$1,
      isbn10: isbn.$2,
      title: book.title,
      author: book.author,
      contentType: 'physical_book',
      metadata: {
        if (book.publisher.isNotEmpty) 'publisher': book.publisher,
        if (book.genre.isNotEmpty) 'genre': book.genre,
        if (book.rank != null) 'rank': book.rank,
      },
    );
  }

  Future<void> trackBestsellerOpen({
    required BestsellerBook book,
    required String entrySource,
    String sourceScreen = '',
  }) {
    return track(
      eventType: AnalyticsEventType.bestsellerBookOpen,
      entrySource: entrySource,
      sourceScreen: sourceScreen,
      contentType: book.contentType,
      provider: book.source,
      isbn13: book.isbn13,
      isbn10: book.isbn10,
      sourceItemId: book.sourceItemId,
      title: book.title,
      author: book.author,
      metadata: {
        'rank': book.rank,
        'category': book.category,
        'reader_target': book.readerTarget,
      },
    );
  }

  Future<void> trackLibraryToggle({
    required bool saved,
    required String libraryId,
  }) {
    return track(
      eventType: saved
          ? AnalyticsEventType.librarySave
          : AnalyticsEventType.libraryRemove,
      entrySource: AnalyticsEntrySource.libraryDetail,
      sourceScreen: 'library',
      metadata: {'library_id': libraryId},
    );
  }

  Future<void> track({
    required String eventType,
    String entrySource = '',
    String contentType = 'physical_book',
    String provider = 'unknown',
    String isbn13 = '',
    String isbn10 = '',
    String sourceItemId = '',
    String title = '',
    String author = '',
    int? displayedPrice,
    int? originalPrice,
    bool wasLowestPrice = false,
    String selectedFormat = '',
    String sourceScreen = '',
    String destinationType = '',
    Map<String, Object?> metadata = const {},
  }) async {
    await _ensureInitialized();
    final prefs = _prefs;
    final installId = _anonymousInstallId;
    if (prefs == null || installId == null) return;
    if (prefs.getBool(_optOutKey) == true) return;
    final event = <String, Object?>{
      'event_id': _uuidV4(),
      'anonymous_install_id': installId,
      'session_id': sessionId,
      'event_type': eventType,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': _appVersion,
      'platform': defaultTargetPlatform.name,
      'entry_source': entrySource,
      'content_type': contentType,
      'provider': provider.isEmpty ? 'unknown' : provider,
      'isbn13': isbn13,
      'isbn10': isbn10,
      'source_item_id': sourceItemId,
      'title': _limit(title, 300),
      'author': _limit(author, 240),
      if (displayedPrice != null) 'displayed_price': displayedPrice,
      if (originalPrice != null) 'original_price': originalPrice,
      'was_lowest_price': wasLowestPrice,
      'selected_format': selectedFormat,
      'source_screen': sourceScreen,
      'destination_type': destinationType,
      'metadata': _safeMetadata(metadata),
    };
    final queue = await _loadQueue();
    queue.add(event);
    await _saveQueue(queue);
    unawaited(flush());
  }

  Future<void> flush() async {
    if (_flushing) return;
    await _ensureInitialized();
    if (!AppConfig.purchaseEnabled || AppConfig.purchaseApiBaseUrl.isEmpty) {
      return;
    }
    final prefs = _prefs;
    if (prefs == null || prefs.getBool(_optOutKey) == true) return;
    final queue = await _loadQueue();
    if (queue.isEmpty) return;
    final batch = queue.length > 50 ? queue.sublist(0, 50) : queue;
    _flushing = true;
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConfig.purchaseApiBaseUrl}/api/v1/analytics/events'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'events': batch}),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _saveQueue(queue.sublist(batch.length));
      }
    } catch (_) {
      // Analytics must never block or surface errors in the app UI.
    } finally {
      _flushing = false;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_prefs == null || _anonymousInstallId == null) {
      await initialize();
    }
  }

  Future<List<Map<String, Object?>>> _loadQueue() async {
    final prefs = _prefs;
    if (prefs == null) return [];
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      final cutoff = DateTime.now().toUtc().subtract(_maxEventAge);
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, Object?>.from(e))
          .where((event) {
            final occurredAt = DateTime.tryParse('${event['occurred_at'] ?? ''}');
            return occurredAt == null || occurredAt.isAfter(cutoff);
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveQueue(List<Map<String, Object?>> queue) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final trimmed = queue.length > _maxQueueSize
        ? queue.sublist(queue.length - _maxQueueSize)
        : queue;
    await prefs.setString(_queueKey, jsonEncode(trimmed));
  }
}

Map<String, Object?> _safeMetadata(Map<String, Object?> source) {
  final metadata = <String, Object?>{};
  for (final entry in source.entries) {
    final key = _limit(entry.key, 80);
    if (key.isEmpty) continue;
    final value = entry.value;
    if (value == null) continue;
    if (value is num || value is bool) {
      metadata[key] = value;
    } else {
      metadata[key] = _limit('$value', 240);
    }
  }
  final encoded = jsonEncode(metadata);
  if (encoded.length <= 3500) return metadata;
  return {'truncated': true};
}

String _limit(String value, int max) {
  final trimmed = value.trim();
  return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
}

(String, String) _splitIsbn(String value) {
  final parts = value
      .split(RegExp(r'[,;/\s]+'))
      .map((e) => e.replaceAll(RegExp(r'[^0-9Xx]'), ''))
      .where((e) => e.length == 10 || e.length == 13);
  var isbn13 = '';
  var isbn10 = '';
  for (final part in parts) {
    if (part.length == 13 && isbn13.isEmpty) isbn13 = part;
    if (part.length == 10 && isbn10.isEmpty) isbn10 = part;
  }
  return (isbn13, isbn10);
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final chars = bytes.map(hex).join();
  return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-'
      '${chars.substring(12, 16)}-${chars.substring(16, 20)}-'
      '${chars.substring(20)}';
}
