class BestsellerSource {
  const BestsellerSource({
    required this.source,
    required this.label,
    required this.enabled,
  });
  final String source;
  final String label;
  final bool enabled;
  factory BestsellerSource.fromJson(Map<String, dynamic> json) =>
      BestsellerSource(
        source: '${json['source'] ?? ''}',
        label: '${json['label'] ?? json['source'] ?? ''}',
        enabled: json['enabled'] == true,
      );
}

class BestsellerBook {
  const BestsellerBook({
    required this.source,
    required this.category,
    required this.rank,
    required this.title,
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
  factory BestsellerBook.fromJson(Map<String, dynamic> json) => BestsellerBook(
    source: '${json['source'] ?? ''}',
    category: '${json['category'] ?? '종합'}',
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
    this.price,
    this.originalPrice,
    this.shippingFee,
    this.totalPrice,
    this.productUrl = '',
    this.imageUrl = '',
    this.availability = '확인 필요',
    this.productType = 'book',
    this.matchedBy = '매칭 확인 필요',
    this.fetchedAt,
  });
  final String provider;
  final String merchantName;
  final String productName;
  final String isbn13;
  final int? price;
  final int? originalPrice;
  final int? shippingFee;
  final int? totalPrice;
  final String productUrl;
  final String imageUrl;
  final String availability;
  final String productType;
  final String matchedBy;
  final DateTime? fetchedAt;
  factory PurchaseOffer.fromJson(Map<String, dynamic> json) => PurchaseOffer(
    provider: '${json['provider'] ?? ''}',
    merchantName: '${json['merchant_name'] ?? ''}',
    productName: '${json['product_name'] ?? ''}',
    isbn13: '${json['isbn13'] ?? ''}',
    price: _int(json['price']),
    originalPrice: _int(json['original_price']),
    shippingFee: _int(json['shipping_fee']),
    totalPrice: _int(json['total_price']),
    productUrl: '${json['product_url'] ?? ''}',
    imageUrl: '${json['image_url'] ?? ''}',
    availability: '${json['availability'] ?? '확인 필요'}',
    productType: '${json['product_type'] ?? 'book'}',
    matchedBy: '${json['matched_by'] ?? '매칭 확인 필요'}',
    fetchedAt: DateTime.tryParse('${json['fetched_at'] ?? ''}'),
  );
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.replaceAll(',', ''));
}
