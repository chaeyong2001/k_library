import '../models/models.dart';

class DemoDataSource {
  final books = const <Book>[
    Book(
      id: 'demo-1',
      title: '불편한 편의점',
      author: '김호연',
      publisher: '나무옆의자',
      publishYear: '2021',
      isbn: '9791161571188',
      rank: 1,
      loanCount: 1820,
      genre: '문학',
      reason: '데모 데이터: 문학 인기 대출 흐름 확인용',
      isDemo: true,
    ),
    Book(
      id: 'demo-2',
      title: '아몬드',
      author: '손원평',
      publisher: '창비',
      publishYear: '2017',
      isbn: '9788936434267',
      rank: 2,
      loanCount: 1654,
      genre: '문학',
      reason: '데모 데이터: 선택 장르 추천 확인용',
      isDemo: true,
    ),
    Book(
      id: 'demo-3',
      title: '역사의 쓸모',
      author: '최태성',
      publisher: '다산초당',
      publishYear: '2019',
      isbn: '9791130621968',
      rank: 3,
      loanCount: 1312,
      genre: '역사',
      reason: '데모 데이터: 역사 분야 인기 대출 흐름 확인용',
      isDemo: true,
    ),
    Book(
      id: 'demo-4',
      title: '코스모스',
      author: '칼 세이건',
      publisher: '사이언스북스',
      publishYear: '2006',
      isbn: '9788983711892',
      rank: 4,
      loanCount: 1190,
      genre: '과학',
      reason: '데모 데이터: 과학 분야 인기 대출 흐름 확인용',
      isDemo: true,
    ),
    Book(
      id: 'demo-5',
      title: '돈의 심리학',
      author: '모건 하우절',
      publisher: '인플루엔셜',
      publishYear: '2021',
      isbn: '9791191056372',
      rank: 5,
      loanCount: 987,
      genre: '경제·경영',
      reason: '데모 데이터: 경제·경영 추천 확인용',
      isDemo: true,
    ),
  ];

  final libraries = const <LibraryBranch>[
    LibraryBranch(
      id: '111003',
      name: '서울도서관',
      address: '서울특별시 중구 세종대로 110',
      region: '서울특별시',
      district: '중구',
      phone: '02-2133-0300',
      homepage: 'https://lib.seoul.go.kr',
      operator: '서울특별시',
      latitude: 37.5663,
      longitude: 126.9779,
      isDemo: true,
    ),
    LibraryBranch(
      id: '111010',
      name: '정독도서관',
      address: '서울특별시 종로구 북촌로5길 48',
      region: '서울특별시',
      district: '종로구',
      phone: '02-2011-5799',
      homepage: 'https://jdlib.sen.go.kr',
      operator: '서울특별시교육청',
      latitude: 37.5810,
      longitude: 126.9836,
      isDemo: true,
    ),
    LibraryBranch(
      id: '111452',
      name: '마포중앙도서관',
      address: '서울특별시 마포구 성산로 128',
      region: '서울특별시',
      district: '마포구',
      phone: '02-3153-5800',
      homepage: 'https://mplib.mapo.go.kr',
      operator: '마포구',
      latitude: 37.5638,
      longitude: 126.9084,
      isDemo: true,
    ),
    LibraryBranch(
      id: '311123',
      name: '성남시중앙도서관',
      address: '경기도 성남시 분당구 판교로 546',
      region: '경기도',
      district: '성남시',
      phone: '031-729-4500',
      homepage: 'https://www.snlib.go.kr',
      operator: '성남시',
      latitude: 37.3726,
      longitude: 127.1269,
      isDemo: true,
    ),
    LibraryBranch(
      id: '231001',
      name: '인천광역시 미추홀도서관',
      address: '인천광역시 남동구 인주대로776번길 53',
      region: '인천광역시',
      district: '남동구',
      phone: '032-440-6660',
      homepage: 'https://www.michuhollib.go.kr',
      operator: '인천광역시',
      latitude: 37.4497,
      longitude: 126.7302,
      isDemo: true,
    ),
  ];

  Future<List<Book>> recommendations(RecommendationPrefs prefs, {int limit = 5}) async {
    final preferred = books
        .where((b) => prefs.genres.contains(b.genre))
        .toList();
    final merged = [
      ...preferred,
      ...books.where((b) => !preferred.contains(b)),
    ];
    return merged
        .take(limit)
        .map(
          (b) => b.copyWith(
            reason:
                '데모 데이터: ${prefs.ageGroup} ${prefs.gender == '전체' ? '' : prefs.gender} ${b.genre} 인기 대출도서 기반',
            isDemo: true,
          ),
        )
        .toList();
  }

  Future<List<Book>> popular({
    String? ageGroup,
    String? gender,
    String? genre,
  }) async {
    final filtered = books
        .where((b) => genre == null || genre == '전체' || b.genre == genre)
        .toList();
    return filtered.isEmpty ? books : filtered;
  }

  Future<List<Book>> searchBooks(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return books
        .where(
          (b) => '${b.title} ${b.author} ${b.isbn}'.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<List<LibraryHolding>> holdings(String isbn) async {
    final now = DateTime.now();
    final statuses = [
      LoanStatus.available,
      LoanStatus.available,
      LoanStatus.loaned,
      LoanStatus.checkRequired,
      LoanStatus.available,
    ];
    return [
      for (var i = 0; i < libraries.length; i++)
        LibraryHolding(
          library: libraries[i],
          status: statuses[i],
          checkedAt: now,
        ),
    ];
  }

  Future<List<LibraryBranch>> libraryList({
    String? region,
    String? query,
  }) async {
    final q = query?.trim() ?? '';
    return libraries
        .where(
          (l) =>
              (region == null || region == '전체' || l.region == region) &&
              (q.isEmpty || l.name.contains(q) || l.address.contains(q)),
        )
        .toList();
  }
}
