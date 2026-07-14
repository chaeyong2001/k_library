import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/purchase_models.dart';
import '../services/purchase_api.dart';
import '../services/services.dart';

class BookPurchaseDetailPage extends StatefulWidget {
  const BookPurchaseDetailPage({
    required this.purchaseApi,
    required this.links,
    this.isbn13 = '',
    this.isbn10 = '',
    this.title = '',
    this.author = '',
    this.publisher = '',
    this.coverUrl = '',
    this.publicationDate = '',
    this.sourceProductUrl = '',
    this.contentType = 'physical_book',
    super.key,
  });

  factory BookPurchaseDetailPage.fromBestseller({
    required BestsellerBook book,
    required PurchaseApiClient purchaseApi,
    required ExternalLinkService links,
  }) => BookPurchaseDetailPage(
    purchaseApi: purchaseApi,
    links: links,
    isbn13: book.isbn13,
    isbn10: book.isbn10,
    title: book.title,
    author: book.author,
    publisher: book.publisher,
    coverUrl: book.coverUrl,
    publicationDate: book.rankingDate,
    sourceProductUrl: book.productUrl,
    contentType: book.contentType,
  );

  factory BookPurchaseDetailPage.fromBook({
    required Book book,
    required PurchaseApiClient purchaseApi,
    required ExternalLinkService links,
  }) {
    final isbn = book.isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    return BookPurchaseDetailPage(
      purchaseApi: purchaseApi,
      links: links,
      isbn13: isbn.length == 13 ? isbn : '',
      isbn10: isbn.length == 10 ? isbn : '',
      title: book.title,
      author: book.author,
      publisher: book.publisher,
      coverUrl: book.coverUrl ?? '',
      publicationDate: book.publishYear,
      sourceProductUrl: book.detailUrl ?? '',
    );
  }

  final PurchaseApiClient purchaseApi;
  final ExternalLinkService links;
  final String isbn13;
  final String isbn10;
  final String title;
  final String author;
  final String publisher;
  final String coverUrl;
  final String publicationDate;
  final String sourceProductUrl;
  final String contentType;

  @override
  State<BookPurchaseDetailPage> createState() => _BookPurchaseDetailPageState();
}

class _BookPurchaseDetailPageState extends State<BookPurchaseDetailPage> {
  List<PurchaseOffer> offers = const [];
  bool loading = true;
  String message = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadOffers());
  }

  Future<void> _loadOffers() async {
    setState(() => loading = true);
    try {
      final result = await widget.purchaseApi.offers(
        isbn13: widget.isbn13,
        isbn10: widget.isbn10,
        title: widget.title,
        author: widget.author,
        contentType: widget.contentType,
      );
      offers = _sortOffers(result.$1);
      message = result.$2;
    } catch (_) {
      offers = const [];
      message = '구매 옵션을 불러올 수 없습니다.';
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowestOffer = _lowestPricedOffer(offers);
    final title = widget.title.trim().isEmpty ? '도서 구매' : widget.title;
    return Scaffold(
      appBar: AppBar(title: Text(_shortTitle(title))),
      body: RefreshIndicator(
        onRefresh: _loadOffers,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _BookSummary(
              title: title,
              author: widget.author,
              publisher: widget.publisher,
              isbn: widget.isbn13.isNotEmpty ? widget.isbn13 : widget.isbn10,
              publicationDate: widget.publicationDate,
              coverUrl: widget.coverUrl,
              contentType: widget.contentType,
            ),
            const SizedBox(height: 18),
            Text('구매 옵션', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (offers.isEmpty)
              const _DetailInfoBox(
                icon: Icons.storefront_outlined,
                title: '구매 옵션이 없습니다.',
                body: '검색어를 바꾸거나 판매처에서 직접 확인해 주세요.',
              )
            else
              ...offers.map(
                (offer) => _PurchaseOfferCard(
                  offer: offer,
                  isLowest: identical(offer, lowestOffer),
                  openUrl: widget.links.openWebsite,
                ),
              ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailInfoBox(
                icon: Icons.info_outline,
                title: '안내',
                body: message,
              ),
            ],
            const SizedBox(height: 12),
            const _DetailInfoBox(
              icon: Icons.verified_user_outlined,
              title: '판매처 안내',
              body:
                  '가격, 재고, 배송비, 혜택은 변경될 수 있으며 결제 전 판매처에서 최종 확인해야 합니다. 이 앱은 각 판매처의 공식 앱이나 공식 제휴 앱이 아닙니다. 외부 판매처로 이동하면 해당 업체의 정책이 적용됩니다.',
            ),
          ],
        ),
      ),
    );
  }
}

class _BookSummary extends StatelessWidget {
  const _BookSummary({
    required this.title,
    required this.author,
    required this.publisher,
    required this.isbn,
    required this.publicationDate,
    required this.coverUrl,
    required this.contentType,
  });

  final String title;
  final String author;
  final String publisher;
  final String isbn;
  final String publicationDate;
  final String coverUrl;
  final String contentType;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 104,
                height: 156,
                child: coverUrl.isEmpty
                    ? const _CoverPlaceholder(size: 42)
                    : Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const _CoverPlaceholder(size: 42),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (author.isNotEmpty) _MetaLine(label: '저자', value: author),
                  if (publisher.isNotEmpty)
                    _MetaLine(label: '출판사', value: publisher),
                  if (isbn.isNotEmpty) _MetaLine(label: 'ISBN', value: isbn),
                  if (publicationDate.isNotEmpty)
                    _MetaLine(label: '출간/기준', value: publicationDate),
                  if (contentType == 'ebook')
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Badge(label: Text('전자책')),
                    ),
                ],
              ),
            ),
          ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$label: $value',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _PurchaseOfferCard extends StatelessWidget {
  const _PurchaseOfferCard({
    required this.offer,
    required this.isLowest,
    required this.openUrl,
  });

  final PurchaseOffer offer;
  final bool isLowest;
  final Future<void> Function(String url) openUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final priceText = offer.isPriced
        ? '${_formatWon(_comparablePrice(offer))}원'
        : offer.message.isNotEmpty
        ? offer.message
        : '가격은 판매처에서 확인';
    final originalText = offer.originalPrice == null
        ? ''
        : '정가 ${_formatWon(offer.originalPrice)}원';
    return Card(
      color: isLowest ? colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    offer.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isLowest)
                  Badge(
                    label: const Text('최저가'),
                    backgroundColor: colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (offer.productName.isNotEmpty)
              Text(
                offer.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            Text(priceText, style: Theme.of(context).textTheme.titleLarge),
            if (originalText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(originalText),
            ],
            if (offer.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(offer.description),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: offer.productUrl.isEmpty
                    ? null
                    : () => openUrl(offer.productUrl),
                icon: const Icon(Icons.open_in_new),
                label: Text(offer.actionText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.menu_book_outlined, size: size)),
    );
  }
}

class _DetailInfoBox extends StatelessWidget {
  const _DetailInfoBox({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(body),
      ),
    );
  }
}

List<PurchaseOffer> _sortOffers(List<PurchaseOffer> source) {
  final priced =
      source.where((offer) => _comparablePrice(offer) != null).toList()
        ..sort((a, b) {
          final price = _comparablePrice(a)!.compareTo(_comparablePrice(b)!);
          if (price != 0) return price;
          return a.label.compareTo(b.label);
        });
  final external = source
      .where((offer) => _comparablePrice(offer) == null)
      .toList();
  return [...priced, ...external];
}

PurchaseOffer? _lowestPricedOffer(List<PurchaseOffer> offers) {
  final priced = offers
      .where((offer) => _comparablePrice(offer) != null)
      .toList();
  if (priced.isEmpty) return null;
  priced.sort((a, b) {
    final price = _comparablePrice(a)!.compareTo(_comparablePrice(b)!);
    if (price != 0) return price;
    return a.label.compareTo(b.label);
  });
  return priced.first;
}

int? _comparablePrice(PurchaseOffer offer) {
  if (offer.offerType != 'priced_offer') return null;
  return offer.totalPrice ?? offer.price;
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

String _shortTitle(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '도서 구매';
  return trimmed.length > 14 ? '${trimmed.substring(0, 14)}...' : trimmed;
}
