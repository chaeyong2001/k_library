class BestsellerSource {
  const BestsellerSource({
    required this.source,
    required this.label,
    required this.enabled,
    this.categories = const [],
    this.readerTargets = const [],
  });
  final String source;
  final String label;
  final bool enabled;
  final List<String> categories;
  final List<String> readerTargets;
  factory BestsellerSource.fromJson(Map<String, dynamic> json) =>
      BestsellerSource(
        source: '${json['source'] ?? ''}',
        label: '${json['label'] ?? json['source'] ?? ''}',
        enabled: json['enabled'] == true,
        categories: (json['categories'] as List? ?? const [])
            .map((e) => '$e')
            .where((e) => e.trim().isNotEmpty)
            .toList(),
        readerTargets: (json['reader_targets'] as List? ?? const [])
            .map((e) => '$e')
            .where((e) => e.trim().isNotEmpty)
            .toList(),
      );
}

class BestsellerBook {
  const BestsellerBook({
    required this.source,
    required this.category,
    required this.rank,
    required this.title,
    this.sourceItemId = '',
    this.contentType = 'physical_book',
    this.readerTarget = '미분류',
    this.author = '',
    this.publisher = '',
    this.isbn13 = '',
    this.isbn10 = '',
    this.coverUrl = '',
    this.productUrl = '',
    this.collectedAt,
    this.rankingDate = '',
  });
  final String source;
  final String category;
  final String sourceItemId;
  final String contentType;
  final String readerTarget;
  final int rank;
  final String title;
  final String author;
  final String publisher;
  final String isbn13;
  final String isbn10;
  final String coverUrl;
  final String productUrl;
  final DateTime? collectedAt;
  final String rankingDate;
  String get sourceItemKey =>
      '$source:$contentType:${sourceItemId.isNotEmpty
          ? sourceItemId
          : isbn13.isNotEmpty
          ? isbn13
          : isbn10.isNotEmpty
          ? isbn10
          : title}';
  factory BestsellerBook.fromJson(Map<String, dynamic> json) => BestsellerBook(
    source: '${json['source'] ?? ''}',
    category: '${json['category'] ?? '종합'}',
    sourceItemId: '${json['source_item_id'] ?? ''}',
    contentType: '${json['content_type'] ?? 'physical_book'}',
    readerTarget: '${json['reader_target'] ?? '미분류'}',
    rank: _int(json['rank']) ?? 0,
    title: '${json['title'] ?? ''}',
    author: '${json['author'] ?? ''}',
    publisher: '${json['publisher'] ?? ''}',
    isbn13: '${json['isbn13'] ?? ''}',
    isbn10: '${json['isbn10'] ?? ''}',
    coverUrl: '${json['cover_url'] ?? ''}',
    productUrl: '${json['source_product_url'] ?? ''}',
    collectedAt: DateTime.tryParse('${json['collected_at'] ?? ''}'),
    rankingDate: '${json['ranking_date'] ?? ''}',
  );
}

class PurchaseOffer {
  const PurchaseOffer({
    required this.provider,
    required this.merchantName,
    required this.productName,
    this.isbn13 = '',
    this.offerType = 'priced_offer',
    this.sourceType = 'priced',
    this.displayName = '',
    this.description = '',
    this.actionLabel = '',
    this.price,
    this.originalPrice,
    this.shippingFee,
    this.totalPrice,
    this.productUrl = '',
    this.imageUrl = '',
    this.availability = '확인 필요',
    this.productType = 'book',
    this.contentType = 'physical_book',
    this.matchedBy = '매칭 확인 필요',
    this.message = '',
    this.category = '',
    this.fetchedAt,
  });
  final String provider;
  final String merchantName;
  final String productName;
  final String isbn13;
  final String offerType;
  final String sourceType;
  final String displayName;
  final String description;
  final String actionLabel;
  final int? price;
  final int? originalPrice;
  final int? shippingFee;
  final int? totalPrice;
  final String productUrl;
  final String imageUrl;
  final String availability;
  final String productType;
  final String contentType;
  final String matchedBy;
  final String message;
  final String category;
  final DateTime? fetchedAt;

  bool get isPriced => offerType == 'priced_offer' && price != null;
  bool get isExternalLink => offerType == 'external_link';
  String get label => displayName.isNotEmpty
      ? displayName
      : merchantName.isNotEmpty
      ? merchantName
      : provider;
  String get actionText => actionLabel.isNotEmpty
      ? actionLabel
      : isPriced
      ? '상품 보기'
      : '$label에서 찾기';

  factory PurchaseOffer.fromJson(Map<String, dynamic> json) => PurchaseOffer(
    provider: '${json['provider'] ?? ''}',
    merchantName: '${json['merchant_name'] ?? ''}',
    productName: '${json['product_name'] ?? ''}',
    isbn13: '${json['isbn13'] ?? ''}',
    offerType: '${json['offer_type'] ?? 'priced_offer'}',
    sourceType: '${json['source_type'] ?? 'priced'}',
    displayName: '${json['display_name'] ?? ''}',
    description: '${json['description'] ?? ''}',
    actionLabel: '${json['action_label'] ?? ''}',
    price: _int(json['price']),
    originalPrice: _int(json['original_price']),
    shippingFee: _int(json['shipping_fee']),
    totalPrice: _int(json['total_price']),
    productUrl: '${json['product_url'] ?? ''}',
    imageUrl: '${json['image_url'] ?? ''}',
    availability: '${json['availability'] ?? '확인 필요'}',
    productType: '${json['product_type'] ?? 'book'}',
    contentType: '${json['content_type'] ?? 'physical_book'}',
    matchedBy: '${json['matched_by'] ?? '매칭 확인 필요'}',
    message: '${json['message'] ?? ''}',
    category: '${json['category'] ?? ''}',
    fetchedAt: DateTime.tryParse('${json['fetched_at'] ?? ''}'),
  );
}

class PurchaseFormatCandidate {
  const PurchaseFormatCandidate({
    required this.candidateId,
    required this.contentType,
    required this.title,
    this.author = '',
    this.publisher = '',
    this.isbn13 = '',
    this.sourceItemId = '',
    this.coverUrl = '',
    this.price,
    this.originalPrice,
    this.productUrl = '',
    this.matchScore = 0,
    this.matchReasons = const [],
  });

  final String candidateId;
  final String contentType;
  final String title;
  final String author;
  final String publisher;
  final String isbn13;
  final String sourceItemId;
  final String coverUrl;
  final int? price;
  final int? originalPrice;
  final String productUrl;
  final double matchScore;
  final List<String> matchReasons;

  factory PurchaseFormatCandidate.fromJson(Map<String, dynamic> json) =>
      PurchaseFormatCandidate(
        candidateId: '${json['candidate_id'] ?? ''}',
        contentType: '${json['content_type'] ?? 'physical_book'}',
        title: '${json['title'] ?? ''}',
        author: '${json['author'] ?? ''}',
        publisher: '${json['publisher'] ?? ''}',
        isbn13: '${json['isbn13'] ?? ''}',
        sourceItemId: '${json['source_item_id'] ?? ''}',
        coverUrl: '${json['cover_url'] ?? ''}',
        price: _int(json['price']),
        originalPrice: _int(json['original_price']),
        productUrl: '${json['product_url'] ?? ''}',
        matchScore: _double(json['match_score']) ?? 0,
        matchReasons: (json['match_reasons'] as List? ?? const [])
            .map((e) => '$e')
            .where((e) => e.trim().isNotEmpty)
            .toList(),
      );
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.replaceAll(',', ''));
}

double? _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}');
}
