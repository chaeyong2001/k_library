import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/purchase_models.dart';
import '../services/analytics_service.dart';
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
    this.sourceItemId = '',
    this.analytics,
    this.entrySource = '',
    this.sourceScreen = '',
    super.key,
  });

  factory BookPurchaseDetailPage.fromBestseller({
    required BestsellerBook book,
    required PurchaseApiClient purchaseApi,
    required ExternalLinkService links,
    AnalyticsService? analytics,
    String entrySource = '',
    String sourceScreen = '',
  }) => BookPurchaseDetailPage(
    purchaseApi: purchaseApi,
    links: links,
    analytics: analytics,
    entrySource: entrySource,
    sourceScreen: sourceScreen,
    isbn13: book.isbn13,
    isbn10: book.isbn10,
    title: book.title,
    author: book.author,
    publisher: book.publisher,
    coverUrl: book.coverUrl,
    publicationDate: book.rankingDate,
    sourceProductUrl: book.productUrl,
    contentType: book.contentType,
    sourceItemId: book.sourceItemId,
  );

  factory BookPurchaseDetailPage.fromBook({
    required Book book,
    required PurchaseApiClient purchaseApi,
    required ExternalLinkService links,
    AnalyticsService? analytics,
    String entrySource = AnalyticsEntrySource.libraryDetail,
    String sourceScreen = 'book_detail',
  }) {
    final isbn = book.isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    return BookPurchaseDetailPage(
      purchaseApi: purchaseApi,
      links: links,
      analytics: analytics,
      entrySource: entrySource,
      sourceScreen: sourceScreen,
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
  final String sourceItemId;
  final AnalyticsService? analytics;
  final String entrySource;
  final String sourceScreen;

  @override
  State<BookPurchaseDetailPage> createState() => _BookPurchaseDetailPageState();
}

class _BookPurchaseDetailPageState extends State<BookPurchaseDetailPage> {
  late String selectedContentType;
  final Map<String, _OfferState> _states = {};
  final Map<String, PurchaseFormatCandidate> _selectedCandidates = {};

  @override
  void initState() {
    super.initState();
    selectedContentType = widget.contentType == 'ebook'
        ? 'ebook'
        : 'physical_book';
    _trackDetailOpen();
    unawaited(_loadOffers(selectedContentType));
  }

  _OfferState get _currentState =>
      _states[selectedContentType] ?? const _OfferState.loading();

  List<PurchaseOffer> get _currentOffers => _currentState.offers;

  PurchaseFormatCandidate? get _selectedCandidate =>
      _selectedCandidates[selectedContentType];

  PurchaseOffer? get _primaryMatchedOffer {
    for (final offer in _currentOffers) {
      if (offer.offerType == 'priced_offer') return offer;
    }
    return null;
  }

  String get _summaryTitle {
    final candidateTitle = _selectedCandidate?.title.trim() ?? '';
    if (candidateTitle.isNotEmpty) return candidateTitle;
    final offerTitle = _primaryMatchedOffer?.productName.trim() ?? '';
    return offerTitle.isNotEmpty
        ? offerTitle
        : widget.title.trim().isEmpty
        ? '도서 구매'
        : widget.title.trim();
  }

  String get _summaryCoverUrl {
    final candidateCover = _selectedCandidate?.coverUrl.trim() ?? '';
    if (candidateCover.isNotEmpty) return candidateCover;
    final offerCover = _primaryMatchedOffer?.imageUrl.trim() ?? '';
    return offerCover.isNotEmpty ? offerCover : widget.coverUrl;
  }

  String get _summaryIsbn {
    final candidateIsbn = _selectedCandidate?.isbn13.trim() ?? '';
    if (candidateIsbn.isNotEmpty) return candidateIsbn;
    final offerIsbn = _primaryMatchedOffer?.isbn13.trim() ?? '';
    if (offerIsbn.isNotEmpty) return offerIsbn;
    return widget.isbn13.isNotEmpty ? widget.isbn13 : widget.isbn10;
  }

  String get _summaryAuthor {
    final candidateAuthor = _selectedCandidate?.author.trim() ?? '';
    return candidateAuthor.isNotEmpty ? candidateAuthor : widget.author;
  }

  String get _summaryPublisher {
    final candidatePublisher = _selectedCandidate?.publisher.trim() ?? '';
    return candidatePublisher.isNotEmpty ? candidatePublisher : widget.publisher;
  }

  Future<void> _loadOffers(String contentType, {bool force = false}) async {
    if (!force && _states[contentType]?.loaded == true) return;
    final selectedCandidate = _selectedCandidates[contentType];
    setState(() {
      _states[contentType] = const _OfferState.loading();
    });
    try {
      final result = await widget.purchaseApi.offers(
        isbn13: selectedCandidate?.isbn13 ?? widget.isbn13,
        isbn10: widget.isbn10,
        title: selectedCandidate?.title ?? widget.title,
        author: selectedCandidate?.author ?? widget.author,
        contentType: contentType,
        sourceItemId: selectedCandidate?.sourceItemId ?? widget.sourceItemId,
      );
      final offers = _sortOffers(result.$1);
      var candidates = const <PurchaseFormatCandidate>[];
      var candidateMessage = '';
      final hasPricedOffer = offers.any((offer) => _comparablePrice(offer) != null);
      if (!hasPricedOffer && selectedCandidate == null) {
        final candidateResult = await widget.purchaseApi.formatCandidates(
          targetContentType: contentType,
          title: widget.title,
          author: widget.author,
          publisher: widget.publisher,
          isbn13: widget.isbn13,
          isbn10: widget.isbn10,
        );
        candidates = candidateResult.$1;
        candidateMessage = candidateResult.$2;
      }
      _states[contentType] = _OfferState.loaded(
        offers: offers,
        candidates: candidates,
        message: result.$2,
        candidateMessage: candidateMessage,
      );
    } catch (_) {
      _states[contentType] = const _OfferState.loaded(
        offers: [],
        candidates: [],
        message: '구매 옵션을 불러올 수 없습니다.',
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
    unawaited(
      widget.analytics?.track(
        eventType: AnalyticsEventType.formatTabChange,
        entrySource: widget.entrySource,
        sourceScreen: widget.sourceScreen,
        contentType: value,
        isbn13: _summaryIsbn.length == 13 ? _summaryIsbn : widget.isbn13,
        isbn10: _summaryIsbn.length == 10 ? _summaryIsbn : widget.isbn10,
        title: _analyticsTitle,
        author: _analyticsAuthor,
        selectedFormat: value,
      ),
    );
    await _loadOffers(value);
  }

  Future<void> _selectCandidate(PurchaseFormatCandidate candidate) async {
    _selectedCandidates[selectedContentType] = candidate;
    unawaited(
      widget.analytics?.track(
        eventType: AnalyticsEventType.alternateFormatCandidateOpen,
        entrySource: AnalyticsEntrySource.alternateFormatCandidate,
        sourceScreen: widget.sourceScreen,
        contentType: candidate.contentType,
        provider: 'aladin',
        isbn13: candidate.isbn13,
        sourceItemId: candidate.sourceItemId,
        title: candidate.title,
        author: candidate.author,
        displayedPrice: candidate.price,
        originalPrice: candidate.originalPrice,
        selectedFormat: candidate.contentType,
        metadata: {'match_score': candidate.matchScore},
      ),
    );
    await _loadOffers(selectedContentType, force: true);
  }

  Future<void> _clearSelectedCandidate() async {
    _selectedCandidates.remove(selectedContentType);
    await _loadOffers(selectedContentType, force: true);
  }

  String get _analyticsTitle =>
      widget.entrySource == AnalyticsEntrySource.purchaseSearch
      ? ''
      : _summaryTitle;

  String get _analyticsAuthor =>
      widget.entrySource == AnalyticsEntrySource.purchaseSearch
      ? ''
      : _summaryAuthor;

  void _trackDetailOpen() {
    unawaited(
      widget.analytics?.track(
        eventType: AnalyticsEventType.purchaseDetailOpen,
        entrySource: widget.entrySource,
        sourceScreen: widget.sourceScreen,
        contentType: selectedContentType,
        isbn13: widget.isbn13,
        isbn10: widget.isbn10,
        sourceItemId: widget.sourceItemId,
        title: widget.entrySource == AnalyticsEntrySource.purchaseSearch
            ? ''
            : widget.title,
        author: widget.entrySource == AnalyticsEntrySource.purchaseSearch
            ? ''
            : widget.author,
        selectedFormat: selectedContentType,
      ),
    );
  }

  void _openOffer(
    PurchaseOffer offer, {
    required bool isLowest,
    required int comparableOfferCount,
  }) {
    final comparablePrice = _comparablePrice(offer);
    final isComparableLowest =
        isLowest && comparablePrice != null && comparableOfferCount > 1;
    unawaited(
      widget.analytics?.track(
        eventType: isComparableLowest
            ? AnalyticsEventType.lowestPriceClick
            : AnalyticsEventType.outboundStoreClick,
        entrySource: widget.entrySource,
        sourceScreen: widget.sourceScreen,
        destinationType: 'external_store',
        contentType: offer.contentType.isEmpty
            ? selectedContentType
            : offer.contentType,
        provider: offer.provider,
        isbn13: offer.isbn13.isNotEmpty ? offer.isbn13 : _summaryIsbn,
        title: _analyticsTitle,
        author: _analyticsAuthor,
        displayedPrice: comparablePrice,
        originalPrice: offer.originalPrice,
        wasLowestPrice: isLowest,
        selectedFormat: selectedContentType,
        metadata: {
          'offer_type': offer.offerType,
          'merchant_name': offer.merchantName,
          'matched_by': offer.matchedBy,
        },
      ),
    );
    unawaited(widget.links.openWebsite(offer.productUrl));
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
              author: _summaryAuthor,
              publisher: _summaryPublisher,
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
              '${_formatLabel(selectedContentType)} 가격 비교',
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
                      '현재 선택한 도서와 정확히 일치하는 ${_formatLabel(selectedContentType)}을 자동으로 찾지 못했습니다. 아래 후보 도서가 있다면 직접 확인해 보세요.',
                  actionLabel: '다시 확인',
                  onAction: _refreshSelected,
                )
              else
                ...pricedOffers.map(
                  (offer) => _PurchaseOfferCard(
                    offer: offer,
                    isLowest: identical(offer, lowestOffer),
                    lowestLabel: pricedOffers.length == 1
                        ? '현재 확인된 가격'
                        : '현재 확인된 최저가',
                    onOpen: (offer) => _openOffer(
                      offer,
                      isLowest: identical(offer, lowestOffer),
                      comparableOfferCount: pricedOffers.length,
                    ),
                    contentType: selectedContentType,
                  ),
                ),
              if (externalOffers.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '다른 판매처에서 검색',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _DetailInfoBox(
                  icon: Icons.search,
                  title: '다른 판매처에서 직접 검색해 볼 수 있습니다.',
                  body: '아래 버튼은 검색 페이지로 이동하며 실제 상품 존재를 보장하지 않습니다.',
                ),
                const SizedBox(height: 8),
                ...externalOffers.map(
                  (offer) => _PurchaseOfferCard(
                    offer: offer,
                    isLowest: false,
                    lowestLabel: '',
                    onOpen: (offer) => _openOffer(
                      offer,
                      isLowest: false,
                      comparableOfferCount: pricedOffers.length,
                    ),
                    contentType: selectedContentType,
                  ),
                ),
              ],
              if (state.candidates.isNotEmpty || _selectedCandidate != null) ...[
                const SizedBox(height: 16),
                _CandidateSection(
                  contentType: selectedContentType,
                  candidates: state.candidates,
                  selectedCandidate: _selectedCandidate,
                  message: state.candidateMessage,
                  onSelect: _selectCandidate,
                  onClear: _clearSelectedCandidate,
                ),
              ],
            ],
            if (state.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailInfoBox(
                icon: Icons.info_outline,
                title: '안내',
                body: state.message,
              ),
            ],
            const SizedBox(height: 12),
            const _DetailInfoBox(
              icon: Icons.verified_user_outlined,
              title: '판매처 안내',
              body:
                  '가격, 재고, 배송비, 혜택은 변경될 수 있으며 결제 전 판매처에서 최종 확인해야 합니다. 이 앱은 각 판매처의 공식 앱이나 공식 제휴 앱이 아닙니다.',
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
    required this.candidates,
    required this.message,
    this.candidateMessage = '',
  });

  const _OfferState.loading()
    : loading = true,
      offers = const [],
      candidates = const [],
      message = '',
      candidateMessage = '';

  const _OfferState.loaded({
    required this.offers,
    required this.candidates,
    required this.message,
    this.candidateMessage = '',
  }) : loading = false;

  final bool loading;
  final List<PurchaseOffer> offers;
  final List<PurchaseFormatCandidate> candidates;
  final String message;
  final String candidateMessage;

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
                  if (author.isNotEmpty) _MetaLine(label: '저자', value: author),
                  if (publisher.isNotEmpty)
                    _MetaLine(label: '출판사', value: publisher),
                  if (isbn.isNotEmpty) _MetaLine(label: 'ISBN', value: isbn),
                  if (publicationDate.isNotEmpty)
                    _MetaLine(label: '출간일', value: publicationDate),
                  if (sourceProductUrl.isNotEmpty)
                    const _MetaLine(label: '상품 링크', value: '판매처에서 확인 가능'),
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
          label: Text('종이책'),
        ),
        ButtonSegment(
          value: 'ebook',
          icon: Icon(Icons.tablet_mac_outlined),
          label: Text('전자책'),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

class _CandidateSection extends StatelessWidget {
  const _CandidateSection({
    required this.contentType,
    required this.candidates,
    required this.selectedCandidate,
    required this.message,
    required this.onSelect,
    required this.onClear,
  });

  final String contentType;
  final List<PurchaseFormatCandidate> candidates;
  final PurchaseFormatCandidate? selectedCandidate;
  final String message;
  final ValueChanged<PurchaseFormatCandidate> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final selected = selectedCandidate;
    if (selected != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Badge(label: Text('선택한 ${_formatLabel(contentType)}')),
              const SizedBox(height: 8),
              Text(
                selected.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (selected.author.isNotEmpty) Text(selected.author),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.undo),
                label: const Text('선택 취소'),
              ),
            ],
          ),
        ),
      );
    }

    if (candidates.isEmpty) {
      return _DetailInfoBox(
        icon: Icons.info_outline,
        title: _emptyTitle(contentType),
        body:
            '${message.isEmpty ? '후보 도서를 찾지 못했습니다.' : message}\n다른 판매처에서 직접 검색해 볼 수 있습니다.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('비슷한 도서 후보', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '아래 후보는 다른 판본 또는 다른 권일 수 있으므로 판매처에서 상세 정보를 확인해 주세요.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 258,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _CandidateCard(
              candidate: candidates[index],
              onSelect: onSelect,
            ),
          ),
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.onSelect});

  final PurchaseFormatCandidate candidate;
  final ValueChanged<PurchaseFormatCandidate> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 52,
                      height: 78,
                      child: candidate.coverUrl.isEmpty
                          ? const _CoverPlaceholder(size: 24)
                          : Image.network(
                              candidate.coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const _CoverPlaceholder(size: 24),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Badge(label: Text(_formatLabel(candidate.contentType))),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                candidate.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (candidate.author.isNotEmpty)
                Text(
                  candidate.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (candidate.publisher.isNotEmpty)
                Text(
                  candidate.publisher,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const Spacer(),
              Text(
                candidate.price == null
                    ? '가격 확인'
                    : '${_formatWon(candidate.price)}원',
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => onSelect(candidate),
                  child: const Text('이 도서 확인'),
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
    required this.onOpen,
    required this.contentType,
  });

  final PurchaseOffer offer;
  final bool isLowest;
  final String lowestLabel;
  final ValueChanged<PurchaseOffer> onOpen;
  final String contentType;

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
                    : () => onOpen(offer),
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
  if (trimmed.isEmpty) return '도서 구매';
  return trimmed.length > 14 ? '${trimmed.substring(0, 14)}...' : trimmed;
}

String _formatLabel(String contentType) =>
    contentType == 'ebook' ? '전자책' : '종이책';

String _emptyTitle(String contentType) =>
    contentType == 'ebook'
        ? '현재 연결된 판매처에서 확인 가능한 전자책 상품이 없습니다.'
        : '현재 연결된 판매처에서 확인 가능한 종이책 상품이 없습니다.';

String _actionText(PurchaseOffer offer, String contentType) {
  if (offer.offerType == 'priced_offer') return '상품 보기';
  if (offer.provider == 'yes24') {
    return contentType == 'ebook'
        ? 'YES24 eBook에서 검색'
        : 'YES24에서 종이책 검색';
  }
  if (offer.provider == 'kyobo') {
    return contentType == 'ebook'
        ? '교보 eBook에서 검색'
        : '교보문고에서 종이책 검색';
  }
  return offer.actionText;
}
