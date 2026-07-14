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
  late String selectedContentType;
  final Map<String, _OfferState> _states = {};

  @override
  void initState() {
    super.initState();
    selectedContentType = widget.contentType == 'ebook'
        ? 'ebook'
        : 'physical_book';
    unawaited(_loadOffers(selectedContentType));
  }

  _OfferState get _currentState =>
      _states[selectedContentType] ?? const _OfferState.loading();

  List<PurchaseOffer> get _currentOffers => _currentState.offers;

  PurchaseOffer? get _primaryMatchedOffer {
    for (final offer in _currentOffers) {
      if (offer.offerType == 'priced_offer') return offer;
    }
    return null;
  }

  String get _summaryTitle {
    final offerTitle = _primaryMatchedOffer?.productName.trim() ?? '';
    return offerTitle.isNotEmpty
        ? offerTitle
        : widget.title.trim().isEmpty
        ? 'Book purchase'
        : widget.title.trim();
  }

  String get _summaryCoverUrl {
    final offerCover = _primaryMatchedOffer?.imageUrl.trim() ?? '';
    return offerCover.isNotEmpty ? offerCover : widget.coverUrl;
  }

  String get _summaryIsbn {
    final offerIsbn = _primaryMatchedOffer?.isbn13.trim() ?? '';
    if (offerIsbn.isNotEmpty) return offerIsbn;
    return widget.isbn13.isNotEmpty ? widget.isbn13 : widget.isbn10;
  }

  Future<void> _loadOffers(String contentType, {bool force = false}) async {
    if (!force && _states[contentType]?.loaded == true) return;
    setState(() {
      _states[contentType] = const _OfferState.loading();
    });
    try {
      final result = await widget.purchaseApi.offers(
        isbn13: widget.isbn13,
        isbn10: widget.isbn10,
        title: widget.title,
        author: widget.author,
        contentType: contentType,
      );
      _states[contentType] = _OfferState.loaded(
        offers: _sortOffers(result.$1),
        message: result.$2,
      );
    } catch (_) {
      _states[contentType] = const _OfferState.loaded(
        offers: [],
        message: 'Unable to load purchase options.',
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshSelected() async {
    await _loadOffers(selectedContentType, force: true);
  }

  Future<void> _changeContentType(String value) async {
    if (value == selectedContentType) return;
    setState(() => selectedContentType = value);
    await _loadOffers(value);
  }

  @override
  Widget build(BuildContext context) {
    final state = _currentState;
    final pricedOffers = _currentOffers
        .where((offer) => _comparablePrice(offer) != null)
        .toList();
    final externalOffers = _currentOffers
        .where((offer) => _comparablePrice(offer) == null)
        .toList();
    final lowestOffer = _lowestPricedOffer(pricedOffers);
    return Scaffold(
      appBar: AppBar(title: Text(_shortTitle(_summaryTitle))),
      body: RefreshIndicator(
        onRefresh: _refreshSelected,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _BookSummary(
              title: _summaryTitle,
              author: widget.author,
              publisher: widget.publisher,
              isbn: _summaryIsbn,
              publicationDate: widget.publicationDate,
              coverUrl: _summaryCoverUrl,
              contentType: selectedContentType,
              sourceProductUrl:
                  _primaryMatchedOffer?.productUrl ?? widget.sourceProductUrl,
            ),
            const SizedBox(height: 14),
            _ContentTypeSelector(
              selected: selectedContentType,
              onChanged: _changeContentType,
            ),
            const SizedBox(height: 18),
            Text(
              '${_formatLabel(selectedContentType)} price options',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (state.loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (pricedOffers.isEmpty)
                _DetailInfoBox(
                  icon: Icons.storefront_outlined,
                  title: _emptyTitle(selectedContentType),
                  body:
                      'No confirmed ${_formatLabel(selectedContentType)} product was found from the connected priced provider. '
                      'This does not mean the format is unavailable everywhere.',
                  actionLabel: 'Retry',
                  onAction: _refreshSelected,
                )
              else
                ...pricedOffers.map(
                  (offer) => _PurchaseOfferCard(
                    offer: offer,
                    isLowest: identical(offer, lowestOffer),
                    lowestLabel: pricedOffers.length == 1
                        ? 'Confirmed price'
                        : 'Lowest confirmed price',
                    openUrl: widget.links.openWebsite,
                    contentType: selectedContentType,
                  ),
                ),
              if (externalOffers.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Search other stores',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _DetailInfoBox(
                  icon: Icons.search,
                  title: 'You can search other stores directly.',
                  body: 'These buttons open search pages and do not guarantee that the exact product exists.',
                ),
                const SizedBox(height: 8),
                ...externalOffers.map(
                  (offer) => _PurchaseOfferCard(
                    offer: offer,
                    isLowest: false,
                    lowestLabel: '',
                    openUrl: widget.links.openWebsite,
                    contentType: selectedContentType,
                  ),
                ),
              ],
            ],
            if (state.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailInfoBox(
                icon: Icons.info_outline,
                title: 'Notice',
                body: state.message,
              ),
            ],
            const SizedBox(height: 12),
            const _DetailInfoBox(
              icon: Icons.verified_user_outlined,
              title: 'Store notice',
              body:
                  'Prices, stock, shipping fees, and benefits can change. Please confirm final details at the store before purchase. This app is not an official store app or official affiliate app.',
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferState {
  const _OfferState({
    required this.loading,
    required this.offers,
    required this.message,
  });

  const _OfferState.loading()
    : loading = true,
      offers = const [],
      message = '';

  const _OfferState.loaded({
    required this.offers,
    required this.message,
  }) : loading = false;

  final bool loading;
  final List<PurchaseOffer> offers;
  final String message;

  bool get loaded => !loading;
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
    required this.sourceProductUrl,
  });

  final String title;
  final String author;
  final String publisher;
  final String isbn;
  final String publicationDate;
  final String coverUrl;
  final String contentType;
  final String sourceProductUrl;

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
                width: 112,
                height: 168,
                child: coverUrl.isEmpty
                    ? const _CoverPlaceholder(size: 44)
                    : Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const _CoverPlaceholder(size: 44),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Badge(
                    label: Text(_formatLabel(contentType)),
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (author.isNotEmpty) _MetaLine(label: 'Author', value: author),
                  if (publisher.isNotEmpty)
                    _MetaLine(label: 'Publisher', value: publisher),
                  if (isbn.isNotEmpty) _MetaLine(label: 'ISBN', value: isbn),
                  if (publicationDate.isNotEmpty)
                    _MetaLine(label: 'Date', value: publicationDate),
                  if (sourceProductUrl.isNotEmpty)
                    const _MetaLine(label: 'Product link', value: 'Available from store'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentTypeSelector extends StatelessWidget {
  const _ContentTypeSelector({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'physical_book',
          icon: Icon(Icons.menu_book_outlined),
          label: Text('Paperback'),
        ),
        ButtonSegment(
          value: 'ebook',
          icon: Icon(Icons.tablet_mac_outlined),
          label: Text('eBook'),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.first),
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
    required this.lowestLabel,
    required this.openUrl,
    required this.contentType,
  });

  final PurchaseOffer offer;
  final bool isLowest;
  final String lowestLabel;
  final Future<void> Function(String url) openUrl;
  final String contentType;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final priceText = offer.isPriced
        ? '${_formatWon(_comparablePrice(offer))} KRW'
        : offer.message.isNotEmpty
        ? offer.message
        : 'Check price at store';
    final originalText = offer.originalPrice == null
        ? ''
        : 'List price ${_formatWon(offer.originalPrice)} KRW';
    final actionText = _actionText(offer, contentType);
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
                    label: Text(lowestLabel),
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
                label: Text(actionText),
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
    this.actionLabel = '',
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(body),
        trailing: actionLabel.isEmpty
            ? null
            : TextButton(onPressed: onAction, child: Text(actionLabel)),
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
  if (trimmed.isEmpty) return 'Book purchase';
  return trimmed.length > 14 ? '${trimmed.substring(0, 14)}...' : trimmed;
}

String _formatLabel(String contentType) =>
    contentType == 'ebook' ? 'eBook' : 'Paperback';

String _emptyTitle(String contentType) =>
    contentType == 'ebook'
        ? 'No confirmed eBook product was found from connected stores.'
        : 'No confirmed paperback product was found from connected stores.';

String _actionText(PurchaseOffer offer, String contentType) {
  if (offer.offerType == 'priced_offer') return 'View product';
  if (offer.provider == 'yes24') {
    return contentType == 'ebook'
        ? 'Search YES24 eBook'
        : 'Search YES24 paperback';
  }
  if (offer.provider == 'kyobo') {
    return contentType == 'ebook'
        ? 'Search Kyobo eBook'
        : 'Search Kyobo paperback';
  }
  return offer.actionText;
}
