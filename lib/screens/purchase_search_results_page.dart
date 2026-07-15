import 'dart:async';

import 'package:flutter/material.dart';

import '../models/purchase_models.dart';
import '../services/analytics_service.dart';
import '../services/purchase_api.dart';
import '../services/services.dart';
import 'book_purchase_detail_page.dart';

class PurchaseSearchResultsPage extends StatefulWidget {
  const PurchaseSearchResultsPage({
    required this.purchaseApi,
    required this.links,
    required this.analytics,
    required this.query,
    required this.contentType,
    this.isbn13 = '',
    this.isbn10 = '',
    super.key,
  });

  final PurchaseApiClient purchaseApi;
  final ExternalLinkService links;
  final AnalyticsService analytics;
  final String query;
  final String contentType;
  final String isbn13;
  final String isbn10;

  @override
  State<PurchaseSearchResultsPage> createState() =>
      _PurchaseSearchResultsPageState();
}

class _PurchaseSearchResultsPageState extends State<PurchaseSearchResultsPage> {
  List<PurchaseSearchResult> results = const [];
  String message = '';
  bool loading = true;
  int _requestId = 0;

  String get _formatLabel => widget.contentType == 'ebook' ? '전자책' : '종이책';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      loading = true;
      message = '';
    });
    try {
      final response = await widget.purchaseApi.searchResults(
        query: widget.isbn13.isNotEmpty || widget.isbn10.isNotEmpty
            ? ''
            : widget.query,
        isbn13: widget.isbn13,
        isbn10: widget.isbn10,
        contentType: widget.contentType,
        limit: 20,
      );
      if (requestId != _requestId) return;
      results = response.$1;
      message = response.$2;
    } catch (_) {
      if (requestId != _requestId) return;
      results = const [];
      message = '검색 결과를 불러오지 못했습니다.';
    } finally {
      if (requestId == _requestId && mounted) {
        setState(() => loading = false);
      }
    }
  }

  void _openDetail(PurchaseSearchResult result) {
    unawaited(
      widget.analytics.track(
        eventType: AnalyticsEventType.purchaseSearchResultOpen,
        entrySource: AnalyticsEntrySource.purchaseSearch,
        sourceScreen: 'purchase_search_results',
        contentType: result.contentType,
        provider: result.provider,
        isbn13: result.isbn13,
        isbn10: result.isbn10,
        sourceItemId: result.sourceItemId,
        title: result.title,
        author: result.author,
        displayedPrice: result.price,
        originalPrice: result.originalPrice,
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookPurchaseDetailPage(
          purchaseApi: widget.purchaseApi,
          links: widget.links,
          analytics: widget.analytics,
          entrySource: AnalyticsEntrySource.purchaseSearch,
          sourceScreen: 'purchase_search_results',
          isbn13: result.isbn13,
          isbn10: result.isbn10,
          title: result.title,
          author: result.author,
          publisher: result.publisher,
          coverUrl: result.coverUrl,
          publicationDate: result.publicationDate,
          sourceProductUrl: result.productUrl,
          contentType: result.contentType,
          sourceItemId: result.sourceItemId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('도서 검색 결과')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          key: PageStorageKey(
            'purchase-search:${widget.contentType}:${widget.query}:${widget.isbn13}:${widget.isbn10}',
          ),
          slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _SearchSummary(
                      query: widget.query,
                      formatLabel: _formatLabel,
                      count: results.length,
                    ),
                  ),
                ),
                if (loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (results.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _StateBox(
                      icon: Icons.search_off,
                      title: '검색 결과가 없습니다',
                      body: message.isEmpty
                          ? '검색 조건에 맞는 도서를 찾지 못했습니다.'
                          : message,
                      actionLabel: '다시 시도',
                      onAction: _load,
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        '책 제목이 같은 여러 판본이 있을 수 있으므로 원하는 도서를 선택해 주세요.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.separated(
                      itemBuilder: (context, index) {
                        final item = results[index];
                        return _ResultCard(
                          result: item,
                          formatLabel: _formatLabel,
                          onSelect: () => _openDetail(item),
                        );
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemCount: results.length,
                    ),
                  ),
                ],
              ],
            ),
        ),
      ),
    );
  }
}

class _SearchSummary extends StatelessWidget {
  const _SearchSummary({
    required this.query,
    required this.formatLabel,
    required this.count,
  });

  final String query;
  final String formatLabel;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Badge(label: Text(formatLabel)),
            const SizedBox(height: 8),
            Text(
              query,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('검색 결과 $count건'),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.formatLabel,
    required this.onSelect,
  });

  final PurchaseSearchResult result;
  final String formatLabel;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 74,
                  height: 108,
                  child: result.coverUrl.isEmpty
                      ? const _CoverPlaceholder()
                      : Image.network(
                          result.coverUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : const _CoverPlaceholder(),
                          errorBuilder: (_, _, _) => const _CoverPlaceholder(),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Badge(label: Text(formatLabel)),
                        if (result.availability.isNotEmpty)
                          Badge(label: Text(result.availability)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (result.author.isNotEmpty)
                      _MetaLine(label: '저자', value: result.author),
                    if (result.publisher.isNotEmpty)
                      _MetaLine(label: '출판사', value: result.publisher),
                    if (result.publicationDate.isNotEmpty)
                      _MetaLine(label: '출간일', value: result.publicationDate),
                    _MetaLine(
                      label: 'ISBN',
                      value: result.isbn13.isNotEmpty
                          ? result.isbn13
                          : result.isbn10,
                    ),
                    if (result.price != null)
                      _MetaLine(label: '판매가', value: '${_formatWon(result.price)}원'),
                    if (result.originalPrice != null)
                      _MetaLine(
                        label: '정가',
                        value: '${_formatWon(result.originalPrice)}원',
                      ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: onSelect,
                        child: const Text('이 도서 선택'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.menu_book_outlined)),
    );
  }
}

class _StateBox extends StatelessWidget {
  const _StateBox({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

String _formatWon(int? value) {
  if (value == null) return '-';
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final remaining = text.length - i;
    buffer.write(text[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
