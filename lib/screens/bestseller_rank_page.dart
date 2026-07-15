import 'dart:async';

import 'package:flutter/material.dart';

import '../models/purchase_models.dart';
import '../services/analytics_service.dart';
import '../services/purchase_api.dart';
import '../services/services.dart';
import 'book_purchase_detail_page.dart';

enum BestsellerRankingMode { genre, readerTarget }

class BestsellerRankPage extends StatefulWidget {
  const BestsellerRankPage({
    required this.purchaseApi,
    required this.links,
    required this.source,
    required this.sourceLabel,
    required this.title,
    required this.rankingMode,
    this.analytics,
    this.contentType = 'physical_book',
    this.category = '',
    this.readerTarget = '',
    super.key,
  });

  final PurchaseApiClient purchaseApi;
  final ExternalLinkService links;
  final String source;
  final String sourceLabel;
  final String title;
  final BestsellerRankingMode rankingMode;
  final AnalyticsService? analytics;
  final String contentType;
  final String category;
  final String readerTarget;

  @override
  State<BestsellerRankPage> createState() => _BestsellerRankPageState();
}

class _BestsellerRankPageState extends State<BestsellerRankPage> {
  List<BestsellerBook> books = const [];
  DateTime? lastUpdated;
  String message = '';
  bool loading = true;

  String get _requestKey {
    final mode = widget.rankingMode == BestsellerRankingMode.genre
        ? 'genre'
        : 'reader_target';
    final value = widget.rankingMode == BestsellerRankingMode.genre
        ? (widget.category.isEmpty ? 'all' : widget.category)
        : (widget.readerTarget.isEmpty ? 'all' : widget.readerTarget);
    return '${widget.source}:${widget.contentType}:$mode:$value';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final result = await widget.purchaseApi.bestsellers(
        source: widget.source,
        contentType: widget.contentType,
        category: widget.rankingMode == BestsellerRankingMode.genre
            ? widget.category
            : '',
        readerTarget: widget.rankingMode == BestsellerRankingMode.readerTarget
            ? widget.readerTarget
            : '',
        pageSize: 50,
      );
      books = _dedupeAndSort(result.$1);
      lastUpdated = result.$2;
      message = result.$3;
    } catch (_) {
      books = const [];
      message = '베스트셀러를 불러올 수 없습니다.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openDetail(BestsellerBook book) {
    final entrySource = book.contentType == 'ebook'
        ? AnalyticsEntrySource.ebookBestseller
        : AnalyticsEntrySource.physicalBestseller;
    unawaited(
      widget.analytics?.trackBestsellerOpen(
        book: book,
        entrySource: entrySource,
        sourceScreen: 'bestseller_rank',
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookPurchaseDetailPage.fromBestseller(
          book: book,
          purchaseApi: widget.purchaseApi,
          links: widget.links,
          analytics: widget.analytics,
          entrySource: entrySource,
          sourceScreen: 'bestseller_rank',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.rankingMode == BestsellerRankingMode.genre
        ? widget.category
        : '';
    final readerTarget =
        widget.rankingMode == BestsellerRankingMode.readerTarget
        ? widget.readerTarget
        : '';
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: PageStorageKey(_requestKey),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            InfoSummary(
              sourceLabel: widget.sourceLabel,
              rankingMode: widget.rankingMode,
              contentType: widget.contentType,
              category: category,
              readerTarget: readerTarget,
              lastUpdated: lastUpdated,
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message),
              ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (books.isEmpty)
              const _RankStateBox(
                icon: Icons.menu_book_outlined,
                title: '조건에 맞는 베스트셀러 데이터가 없습니다.',
              )
            else
              ...books.map(
                (book) => _RankBookCard(
                  book: book,
                  sourceLabel: widget.sourceLabel,
                  onTap: () => _openDetail(book),
                  onOpenSource: book.productUrl.isEmpty
                      ? null
                      : () {
                          unawaited(
                            widget.analytics?.track(
                              eventType: AnalyticsEventType.outboundStoreClick,
                              entrySource: book.contentType == 'ebook'
                                  ? AnalyticsEntrySource.ebookBestseller
                                  : AnalyticsEntrySource.physicalBestseller,
                              sourceScreen: 'bestseller_rank',
                              destinationType: 'external_store',
                              contentType: book.contentType,
                              provider: book.source,
                              isbn13: book.isbn13,
                              isbn10: book.isbn10,
                              sourceItemId: book.sourceItemId,
                              title: book.title,
                              author: book.author,
                            ),
                          );
                          unawaited(widget.links.openWebsite(book.productUrl));
                        },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class InfoSummary extends StatelessWidget {
  const InfoSummary({
    required this.sourceLabel,
    required this.rankingMode,
    required this.contentType,
    required this.category,
    required this.readerTarget,
    required this.lastUpdated,
    super.key,
  });

  final String sourceLabel;
  final BestsellerRankingMode rankingMode;
  final String contentType;
  final String category;
  final String readerTarget;
  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    final typeLabel = contentType == 'ebook' ? '전자책' : '종이책';
    final filter = rankingMode == BestsellerRankingMode.genre
        ? '장르: ${category.isEmpty ? '전체' : category}'
        : '독자 대상: ${readerTarget.isEmpty ? '전체' : readerTarget}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.leaderboard_outlined),
        title: Text(sourceLabel),
        subtitle: Text(
          '$typeLabel · $filter\n마지막 갱신: ${lastUpdated == null ? '확인 필요' : lastUpdated!.toLocal().toString().substring(0, 16)}',
        ),
      ),
    );
  }
}

class _RankBookCard extends StatelessWidget {
  const _RankBookCard({
    required this.book,
    required this.sourceLabel,
    required this.onTap,
    required this.onOpenSource,
  });

  final BestsellerBook book;
  final String sourceLabel;
  final VoidCallback onTap;
  final VoidCallback? onOpenSource;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 58,
                      height: 86,
                      child: book.coverUrl.isEmpty
                          ? const _RankCoverPlaceholder()
                          : Image.network(
                              book.coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const _RankCoverPlaceholder(),
                            ),
                    ),
                  ),
                  Positioned(
                    left: -6,
                    top: -6,
                    child: Badge(
                      label: Text('${book.rank}'),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (book.contentType == 'ebook') ...[
                      const SizedBox(height: 4),
                      const Badge(label: Text('전자책')),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (book.author.isNotEmpty) book.author,
                        if (book.publisher.isNotEmpty) book.publisher,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.isbn13.isEmpty ? book.isbn10 : book.isbn13,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: sourceLabel,
                icon: const Icon(Icons.open_in_new),
                onPressed: onOpenSource,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankCoverPlaceholder extends StatelessWidget {
  const _RankCoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.menu_book_outlined)),
    );
  }
}

class _RankStateBox extends StatelessWidget {
  const _RankStateBox({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 36),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

List<BestsellerBook> _dedupeAndSort(List<BestsellerBook> source) {
  final unique = <String, BestsellerBook>{};
  for (final book in source) {
    unique.putIfAbsent(book.sourceItemKey, () => book);
  }
  final list = unique.values.toList()..sort((a, b) => a.rank.compareTo(b.rank));
  return list;
}
