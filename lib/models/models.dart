import 'dart:convert';

enum LoanStatus { available, loaned, checkRequired, unavailable }

extension LoanStatusText on LoanStatus {
  String get label => switch (this) {
    LoanStatus.available => '대출 가능',
    LoanStatus.loaned => '대출 중',
    LoanStatus.checkRequired => '확인 필요',
    LoanStatus.unavailable => '정보 미제공',
  };
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.publisher,
    required this.publishYear,
    required this.isbn,
    this.coverUrl,
    this.detailUrl,
    this.description,
    this.rank,
    this.loanCount,
    this.genre = '분류 미제공',
    this.reason = '공공데이터 기반',
    this.isDemo = false,
  });

  final String id;
  final String title;
  final String author;
  final String publisher;
  final String publishYear;
  final String isbn;
  final String? coverUrl;
  final String? detailUrl;
  final String? description;
  final int? rank;
  final int? loanCount;
  final String genre;
  final String reason;
  final bool isDemo;

  factory Book.fromJson(
    Map<String, dynamic> json, {
    bool isDemo = false,
    String? reason,
  }) {
    final isbn = normalizeIsbn(readString(json, ['isbn13', 'isbn', 'isbn10']));
    final title = readString(json, ['bookname', 'title'], '제목 미제공');
    final rank = readInt(json, ['ranking', 'rank', 'no']);
    final genre = readString(json, ['class_nm', 'genre'], '분류 미제공');
    return Book(
      id: readString(json, [
        'bookKey',
        'id',
        'bookDtlUrl',
      ], isbn.isEmpty ? title : isbn),
      title: title,
      author: readString(json, ['authors', 'author'], '저자 미제공'),
      publisher: readString(json, ['publisher'], '출판사 미제공'),
      publishYear: readString(json, [
        'publication_year',
        'publicationYear',
        'pubYear',
        'pubyear',
      ], ''),
      isbn: isbn,
      coverUrl: validUrl(
        readString(json, ['bookImageURL', 'coverUrl', 'imageUrl']),
      ),
      detailUrl: validUrl(readString(json, ['bookDtlUrl', 'detailUrl'])),
      description: emptyToNull(
        readString(json, ['description', 'contents', 'bookDescription']),
      ),
      rank: rank,
      loanCount: readInt(json, ['loan_count', 'loanCount']),
      genre: genre,
      reason: reason ?? (isDemo ? '데모 데이터' : '도서관 대출 데이터 기반'),
      isDemo: isDemo,
    );
  }

  Book copyWith({String? reason, bool? isDemo}) => Book(
    id: id,
    title: title,
    author: author,
    publisher: publisher,
    publishYear: publishYear,
    isbn: isbn,
    coverUrl: coverUrl,
    detailUrl: detailUrl,
    description: description,
    rank: rank,
    loanCount: loanCount,
    genre: genre,
    reason: reason ?? this.reason,
    isDemo: isDemo ?? this.isDemo,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'publisher': publisher,
    'publishYear': publishYear,
    'isbn': isbn,
    'coverUrl': coverUrl,
    'detailUrl': detailUrl,
    'description': description,
    'rank': rank,
    'loanCount': loanCount,
    'genre': genre,
    'reason': reason,
    'isDemo': isDemo,
  };

  static Book fromEncoded(String source) =>
      Book.fromJson(jsonDecode(source) as Map<String, dynamic>, isDemo: true);
  String encode() => jsonEncode(toJson());
}

class LibraryBranch {
  const LibraryBranch({
    required this.id,
    required this.name,
    required this.address,
    required this.region,
    required this.district,
    this.phone,
    this.homepage,
    this.closedInfo,
    this.operatingTime,
    this.operator,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.isDemo = false,
  });

  final String id;
  final String name;
  final String address;
  final String region;
  final String district;
  final String? phone;
  final String? homepage;
  final String? closedInfo;
  final String? operatingTime;
  final String? operator;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;
  final bool isDemo;

  LibraryBranch copyWith({double? distanceMeters, bool? isDemo}) =>
      LibraryBranch(
        id: id,
        name: name,
        address: address,
        region: region,
        district: district,
        phone: phone,
        homepage: homepage,
        closedInfo: closedInfo,
        operatingTime: operatingTime,
        operator: operator,
        latitude: latitude,
        longitude: longitude,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        isDemo: isDemo ?? this.isDemo,
      );

  factory LibraryBranch.fromJson(
    Map<String, dynamic> json, {
    bool isDemo = false,
  }) {
    final address = readString(json, ['address', 'addr'], '주소 미제공');
    return LibraryBranch(
      id: readString(json, [
        'libCode',
        'id',
      ], readString(json, ['libName', 'name'], 'library')),
      name: readString(json, ['libName', 'name'], '도서관명 미제공'),
      address: address,
      region: readString(json, ['region', 'sido'], inferRegion(address)),
      district: readString(json, [
        'district',
        'sigungu',
      ], inferDistrict(address)),
      phone: emptyToNull(readString(json, ['tel', 'phone'])),
      homepage: validUrl(readString(json, ['homepage', 'homepageUrl', 'url'])),
      closedInfo: emptyToNull(readString(json, ['closed', 'closedInfo'])),
      operatingTime: emptyToNull(readString(json, ['operatingTime', 'hours'])),
      operator: emptyToNull(readString(json, ['operator'])),
      latitude: readDouble(json, ['latitude', 'lat']),
      longitude: readDouble(json, ['longitude', 'lng', 'lon']),
      isDemo: isDemo,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'region': region,
    'district': district,
    'phone': phone,
    'homepage': homepage,
    'closedInfo': closedInfo,
    'operatingTime': operatingTime,
    'operator': operator,
    'latitude': latitude,
    'longitude': longitude,
    'isDemo': isDemo,
  };

  static LibraryBranch fromEncoded(String source) => LibraryBranch.fromJson(
    jsonDecode(source) as Map<String, dynamic>,
    isDemo: true,
  );
  String encode() => jsonEncode(toJson());
}

class LibraryHolding {
  const LibraryHolding({
    required this.library,
    required this.status,
    required this.checkedAt,
  });

  final LibraryBranch library;
  final LoanStatus status;
  final DateTime checkedAt;
}

class RecommendationPrefs {
  const RecommendationPrefs({
    this.ageGroup = '30대',
    this.gender = '전체',
    this.genres = const ['문학'],
  });

  final String ageGroup;
  final String gender;
  final List<String> genres;

  RecommendationPrefs copyWith({
    String? ageGroup,
    String? gender,
    List<String>? genres,
  }) => RecommendationPrefs(
    ageGroup: ageGroup ?? this.ageGroup,
    gender: gender ?? this.gender,
    genres: genres ?? this.genres,
  );

  Map<String, dynamic> toJson() => {
    'ageGroup': ageGroup,
    'gender': gender,
    'genres': genres,
  };

  factory RecommendationPrefs.fromJson(Map<String, dynamic> json) =>
      RecommendationPrefs(
        ageGroup: json['ageGroup']?.toString() ?? '30대',
        gender: json['gender']?.toString() ?? '전체',
        genres:
            (json['genres'] as List?)?.map((e) => e.toString()).toList() ??
            const ['문학'],
      );
}

String readString(
  Map<String, dynamic> json,
  List<String> keys, [
  String fallback = '',
]) {
  for (final key in keys) {
    final value = json[key];
    if (value != null &&
        value.toString().trim().isNotEmpty &&
        value.toString() != '-') {
      return value.toString().trim();
    }
  }
  return fallback;
}

int? readInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.replaceAll(',', '').trim());
  }
  return null;
}

double? readDouble(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
  }
  return null;
}

String normalizeIsbn(String raw) => raw
    .split(RegExp(r'[,;/\s]+'))
    .map((e) => e.replaceAll(RegExp(r'[^0-9Xx]'), ''))
    .where((e) => e.length == 10 || e.length == 13)
    .join(', ');

String? validUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  return uri.toString();
}

String? emptyToNull(String value) => value.trim().isEmpty ? null : value.trim();

String inferRegion(String address) {
  const names = [
    '서울특별시',
    '부산광역시',
    '대구광역시',
    '인천광역시',
    '광주광역시',
    '대전광역시',
    '울산광역시',
    '세종특별자치시',
    '경기도',
    '강원특별자치도',
    '강원도',
    '충청북도',
    '충청남도',
    '전북특별자치도',
    '전라북도',
    '전라남도',
    '경상북도',
    '경상남도',
    '제주특별자치도',
  ];
  for (final name in names) {
    if (address.startsWith(name)) {
      return name == '강원도'
          ? '강원특별자치도'
          : name == '전라북도'
          ? '전북특별자치도'
          : name;
    }
  }
  return address.split(' ').firstOrNull ?? '지역 미제공';
}

String inferDistrict(String address) {
  final parts = address.split(' ');
  if (parts.length > 1) return parts[1];
  return '';
}
