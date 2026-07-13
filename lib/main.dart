import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'config/app_config.dart';
import 'config/genre_mapping.dart';
import 'models/models.dart';
import 'models/loan_alert.dart';
import 'models/purchase_models.dart';
import 'repositories/library_repository.dart';
import 'services/services.dart';
import 'services/loan_alert_service.dart';
import 'services/purchase_api.dart';
import 'storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadDebugDotEnv();
  runApp(const KLibraryApp());
}

Future<void> _loadDebugDotEnv() async {
  var shouldLoad = false;
  assert(() {
    shouldLoad = true;
    return true;
  }());
  if (shouldLoad) {
    await dotenv.load(fileName: '.env', isOptional: true);
  }
}

class KLibraryApp extends StatelessWidget {
  const KLibraryApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2F6F5E);
    return MaterialApp(
      title: 'K Library',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF7F8F4),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F8F4),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppState extends ChangeNotifier {
  AppState() {
    init();
  }

  final repo = LibraryRepository();
  final store = LocalStore();
  final distance = DistanceService();
  final locator = DeviceLocationService();
  final links = ExternalLinkService();
  final purchaseApi = PurchaseApiClient();
  final loanAlerts = LoanAlertService();

  RecommendationPrefs prefs = const RecommendationPrefs();
  String region = '서울특별시';
  String popularAge = '전체';
  String popularGender = '전체';
  String popularGenre = '전체';
  String popularPeriod = '최근 30일';
  List<Book> recommendations = const [];
  List<Book> popular = const [];
  List<Book> favoriteBooks = const [];
  List<LibraryBranch> favoriteLibraries = const [];
  List<Book> recentBooks = const [];
  List<String> recentSearches = const [];
  List<LibraryBranch> libraries = const [];
  bool recommendationsLoading = false;
  bool popularLoading = false;
  double? userLat;
  double? userLon;
  bool loading = true;
  String? bannerMessage;
  List<LoanAlertItem> loanAlertItems = const [];

  Future<void> init() async {
    loading = true;
    notifyListeners();
    prefs = await store.loadRecommendationPrefs();
    region = await store.loadRegion();
    popularAge = prefs.ageGroup;
    popularGender = prefs.gender;
    await loanAlerts.initialize();
    await loanAlerts.checkDueItems();
    await reloadLocal();
    await refreshRemote();
    loading = false;
    notifyListeners();
  }

  Future<void> refreshRemote() async {
    await Future.wait([loadRecommendations(), loadPopular(), loadLibraries()]);
  }

  Future<void> reloadLocal() async {
    favoriteBooks = await store.favoriteBooks();
    favoriteLibraries = await store.favoriteLibraries();
    recentBooks = await store.recentBooks();
    recentSearches = await store.loadRecentSearches();
    loanAlertItems = await loanAlerts.list();
    notifyListeners();
  }

  Future<void> updatePrefs(RecommendationPrefs value) async {
    prefs = value;
    notifyListeners();
    await store.saveRecommendationPrefs(value);
    await loadRecommendations(forceRefresh: true);
  }

  Future<void> updateRegion(String value) async {
    region = value;
    await store.saveRegion(value);
    await loadLibraries();
    notifyListeners();
  }

  Future<void> loadRecommendations({bool forceRefresh = false}) async {
    recommendationsLoading = true;
    if (forceRefresh) recommendations = const [];
    notifyListeners();
    try {
      recommendations = await repo.recommendations(
        prefs,
        period: popularPeriod,
        forceRefresh: forceRefresh,
      );
      bannerMessage = null;
    } catch (e) {
      recommendations = const [];
      bannerMessage = '추천 데이터를 불러오지 못했습니다. API 키와 네트워크를 확인해 주세요.';
    } finally {
      recommendationsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPopular({
    String? ageGroup,
    String? gender,
    String? genre,
    String? period,
    bool forceRefresh = false,
  }) async {
    popularAge = ageGroup ?? popularAge;
    popularGender = gender ?? popularGender;
    popularGenre = genre ?? popularGenre;
    popularPeriod = period ?? popularPeriod;
    popularLoading = true;
    if (forceRefresh) popular = const [];
    notifyListeners();
    try {
      popular = await repo.popularBooks(
        ageGroup: popularAge,
        gender: popularGender,
        genre: popularGenre,
        period: popularPeriod,
        forceRefresh: forceRefresh,
      );
      bannerMessage = null;
    } catch (e) {
      popular = const [];
      bannerMessage = '인기 대출도서를 불러오지 못했습니다. API 키와 네트워크를 확인해 주세요.';
    } finally {
      popularLoading = false;
      notifyListeners();
    }
  }

  Future<List<Book>> search(String query) async {
    await store.addRecentSearch(query);
    recentSearches = await store.loadRecentSearches();
    loanAlertItems = await loanAlerts.list();
    notifyListeners();
    return repo.searchBooks(query);
  }

  Future<List<LibraryHolding>> holdings(Book book) async {
    await store.addRecentBook(book);
    await reloadLocal();
    return repo.holdings(book.isbn, region: region);
  }

  Future<void> loadLibraries({String? query}) async {
    try {
      final data = await repo.libraries(region: region, query: query);
      libraries = distance.rankLibraries(
        data,
        userLat: userLat,
        userLon: userLon,
      );
      bannerMessage = null;
    } catch (e) {
      libraries = const [];
      bannerMessage = '도서관 목록을 불러오지 못했습니다. API 키와 네트워크를 확인해 주세요.';
    }
    notifyListeners();
  }

  Future<void> requestLocation() async {
    final pos = await locator.currentPosition();
    userLat = pos?.latitude;
    userLon = pos?.longitude;
    bannerMessage = pos == null
        ? '위치 권한 없이도 지역 선택으로 검색할 수 있습니다.'
        : '현재 위치 기준으로 가까운 도서관을 정렬했습니다.';
    if (pos != null) {
      await loadLibraries();
    } else {
      libraries = distance.rankLibraries(
        libraries,
        userLat: userLat,
        userLon: userLon,
      );
      notifyListeners();
    }
  }

  Future<void> toggleBook(Book book) async {
    await store.toggleFavoriteBook(book);
    await reloadLocal();
  }

  Future<String?> addLoanAlert({
    required Book book,
    required LibraryHolding holding,
  }) async {
    final message = await loanAlerts.add(
      title: book.title,
      isbn: book.isbn,
      libraryName: holding.library.name,
      libraryCode: holding.library.id,
      homepage: holding.library.homepage ?? '',
      coverUrl: book.coverUrl ?? '',
    );
    loanAlertItems = await loanAlerts.list();
    notifyListeners();
    return message;
  }

  Future<void> removeLoanAlert(String id) async {
    await loanAlerts.remove(id);
    loanAlertItems = await loanAlerts.list();
    notifyListeners();
  }

  Future<void> restartLoanAlert(String id) async {
    await loanAlerts.restart(id);
    loanAlertItems = await loanAlerts.list();
    notifyListeners();
  }

  Future<void> checkLoanAlertNow(LoanAlertItem item) async {
    await loanAlerts.checkNow(item, notify: true);
    loanAlertItems = await loanAlerts.list();
    notifyListeners();
  }

  Future<void> toggleLibrary(LibraryBranch library) async {
    await store.toggleFavoriteLibrary(library);
    await reloadLocal();
  }

  bool isFavoriteBook(Book book) => favoriteBooks.any((e) => e.id == book.id);
  bool isFavoriteLibrary(LibraryBranch library) =>
      favoriteLibraries.any((e) => e.id == library.id);
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final AppState state;
  int index = 0;

  @override
  void initState() {
    super.initState();
    state = AppState();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final page = switch (index) {
          0 => HomePage(
            state: state,
            openSearch: () => setState(() => index = 1),
          ),
          1 => SearchPage(state: state),
          2 => LibrariesPage(state: state),
          3 => ShelfPage(state: state),
          4 => PurchasePage(state: state),
          _ => SettingsPage(state: state),
        };
        return Scaffold(
          appBar: AppBar(
            title: const Text('K Library'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: ModePill(
                    isDemo: AppConfig.isDemoMode,
                    key: ValueKey(AppConfig.dataMode),
                  ),
                ),
              ),
            ],
          ),
          body: state.loading
              ? const Center(child: CircularProgressIndicator())
              : page,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '홈',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: '검색'),
              NavigationDestination(
                icon: Icon(Icons.local_library_outlined),
                selectedIcon: Icon(Icons.local_library),
                label: '도서관',
              ),
              NavigationDestination(
                icon: Icon(Icons.bookmark_border),
                selectedIcon: Icon(Icons.bookmark),
                label: '보관함',
              ),
              NavigationDestination(
                icon: Icon(Icons.shopping_bag_outlined),
                selectedIcon: Icon(Icons.shopping_bag),
                label: '구매',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '설정',
              ),
            ],
          ),
        );
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({required this.state, required this.openSearch, super.key});
  final AppState state;
  final VoidCallback openSearch;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: state.refreshRemote,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (state.bannerMessage != null)
            MessageCard(message: state.bannerMessage!),
          SearchLauncher(onTap: openSearch),
          const SizedBox(height: 12),
          RegionBar(state: state),
          const SizedBox(height: 18),
          SectionHeader(
            title: '맞춤 도서 추천',
            action: '조건 수정',
            onTap: () => showPrefsSheet(context, state),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip(label: Text(state.prefs.ageGroup)),
              Chip(label: Text(state.prefs.gender)),
              ...state.prefs.genres.map((e) => Chip(label: Text(e))),
            ],
          ),
          const SizedBox(height: 8),
          if (state.recommendationsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state.recommendations.isEmpty)
            const StateBox(
              icon: Icons.auto_stories_outlined,
              title: '추천 결과가 없습니다',
            )
          else
            ...state.recommendations.map(
              (book) => BookTile(book: book, state: state),
            ),
          const SizedBox(height: 18),
          SectionHeader(
            title: '인기 대출도서',
            action: '필터',
            onTap: () => showPopularFilter(context, state),
          ),
          Wrap(
            spacing: 6,
            children: [
              Chip(label: Text(state.popularPeriod)),
              Chip(label: Text(state.popularAge)),
              Chip(label: Text(state.popularGender)),
              Chip(label: Text(state.popularGenre)),
            ],
          ),
          const SizedBox(height: 8),
          if (state.popularLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state.popular.isEmpty)
            const StateBox(
              icon: Icons.leaderboard_outlined,
              title: '인기 대출도서가 없습니다',
            )
          else
            ...state.popular
                .take(8)
                .map(
                  (book) => BookTile(book: book, state: state, showRank: true),
                ),
          const SizedBox(height: 18),
          SectionHeader(
            title: '가까운 도서관',
            action: '위치 사용',
            onTap: state.requestLocation,
          ),
          ...state.libraries
              .take(5)
              .map((library) => LibraryTile(library: library, state: state)),
          if (state.recentBooks.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionHeader(title: '최근 본 책'),
            ...state.recentBooks
                .take(3)
                .map((book) => BookTile(book: book, state: state)),
          ],
        ],
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({required this.state, super.key});
  final AppState state;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = TextEditingController();
  Timer? timer;
  List<Book> results = const [];
  bool searching = false;
  String? error;

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> runSearch(String query) async {
    if (query.trim().isEmpty || searching) return;
    setState(() {
      searching = true;
      error = null;
    });
    try {
      results = await widget.state.search(query);
    } catch (e) {
      error = AppConfig.isDemoMode
          ? '데모 검색 중 오류가 발생했습니다.'
          : '검색에 실패했습니다. API 키와 네트워크를 확인해 주세요.';
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SearchBar(
          controller: controller,
          hintText: '책 제목, 저자, ISBN 검색',
          leading: const Icon(Icons.search),
          trailing: [
            IconButton(
              tooltip: '지우기',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                controller.clear();
                results = const [];
              }),
            ),
          ],
          onSubmitted: runSearch,
          onChanged: (value) {
            timer?.cancel();
            timer = Timer(
              const Duration(milliseconds: 500),
              () => runSearch(value),
            );
          },
        ),
        if (widget.state.recentSearches.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionHeader(
            title: '최근 검색어',
            action: '전체 삭제',
            onTap: () async {
              await widget.state.store.clearRecentSearches();
              await widget.state.reloadLocal();
            },
          ),
          Wrap(
            spacing: 8,
            children: widget.state.recentSearches
                .map(
                  (q) => InputChip(
                    label: Text(q),
                    onPressed: () {
                      controller.text = q;
                      runSearch(q);
                    },
                    onDeleted: () async {
                      await widget.state.store.removeRecentSearch(q);
                      await widget.state.reloadLocal();
                    },
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        if (searching)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (error != null)
          StateBox(
            icon: Icons.error_outline,
            title: error!,
            action: '다시 시도',
            onTap: () => runSearch(controller.text),
          )
        else if (controller.text.isNotEmpty && results.isEmpty)
          const StateBox(icon: Icons.search_off, title: '검색 결과가 없습니다')
        else
          ...results.map((book) => BookTile(book: book, state: widget.state)),
      ],
    );
  }
}

class LibrariesPage extends StatefulWidget {
  const LibrariesPage({required this.state, super.key});
  final AppState state;
  @override
  State<LibrariesPage> createState() => _LibrariesPageState();
}

class _LibrariesPageState extends State<LibrariesPage> {
  final controller = TextEditingController();
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (widget.state.bannerMessage != null)
          MessageCard(message: widget.state.bannerMessage!),
        RegionBar(state: widget.state),
        const SizedBox(height: 10),
        SearchBar(
          controller: controller,
          hintText: '도서관명 또는 주소 검색',
          leading: const Icon(Icons.local_library_outlined),
          onChanged: (value) {
            timer?.cancel();
            timer = Timer(
              const Duration(milliseconds: 350),
              () => widget.state.loadLibraries(query: value),
            );
          },
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: widget.state.requestLocation,
          icon: const Icon(Icons.my_location),
          label: const Text('현재 위치에서 가까운 순으로 보기'),
        ),
        const SizedBox(height: 12),
        if (widget.state.libraries.isEmpty)
          const StateBox(
            icon: Icons.local_library_outlined,
            title: '도서관 목록이 없습니다',
          )
        else
          ...widget.state.libraries.map(
            (library) => LibraryTile(library: library, state: widget.state),
          ),
      ],
    );
  }
}

class ShelfPage extends StatelessWidget {
  const ShelfPage({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SectionHeader(
          title: '즐겨찾는 책',
          action: '전체 삭제',
          onTap: () async {
            await state.store.clearFavoriteBooks();
            await state.reloadLocal();
          },
        ),
        if (state.favoriteBooks.isEmpty)
          const StateBox(icon: Icons.bookmark_border, title: '저장한 책이 없습니다')
        else
          ...state.favoriteBooks.map((b) => BookTile(book: b, state: state)),
        const SizedBox(height: 18),
        SectionHeader(
          title: '즐겨찾는 도서관',
          action: '전체 삭제',
          onTap: () async {
            await state.store.clearFavoriteLibraries();
            await state.reloadLocal();
          },
        ),
        if (state.favoriteLibraries.isEmpty)
          const StateBox(
            icon: Icons.local_library_outlined,
            title: '저장한 도서관이 없습니다',
          )
        else
          ...state.favoriteLibraries.map(
            (l) => LibraryTile(library: l, state: state),
          ),
        const SizedBox(height: 18),
        SectionHeader(
          title: '최근 본 책',
          action: '전체 삭제',
          onTap: () async {
            await state.store.clearRecentBooks();
            await state.reloadLocal();
          },
        ),
        ...state.recentBooks.map((b) => BookTile(book: b, state: state)),
        const SizedBox(height: 18),
        LoanAlertSection(state: state),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        InfoCard(
          title: 'API 연결 상태',
          body:
              '${AppConfig.dataModeLabel}\n실행 예: flutter run --dart-define=DATA4LIBRARY_AUTH_KEY=발급키',
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('추천 조건 수정'),
          onTap: () => showPrefsSheet(context, state),
        ),
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: const Text('위치 권한 안내'),
          subtitle: const Text('가까운 도서관 기능을 사용할 때만 요청하며 서버에 저장하지 않습니다.'),
          onTap: state.requestLocation,
        ),
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('데이터 캐시 삭제'),
          onTap: () async {
            await state.store.clearCaches();
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('캐시를 삭제했습니다.')));
            }
          },
        ),
        const InfoCard(
          title: '공공데이터 출처',
          body:
              '도서관 정보나루 Open API의 도서 검색, 인기 대출도서, 도서관 목록, 보유 도서관, 대출 가능 여부 API를 사용합니다.',
        ),
        const InfoCard(
          title: '비공식 앱 고지',
          body: '이 앱은 국립중앙도서관, 도서관 정보나루, 지방자치단체 또는 각 도서관이 직접 운영하는 공식 앱이 아닙니다.',
        ),
        const InfoCard(
          title: '개인정보 안내',
          body:
              '회원가입과 로그인을 사용하지 않습니다. 추천 조건, 즐겨찾기, 최근 검색어는 기기 내부에 저장됩니다. 위치정보는 거리 계산에만 사용합니다.',
        ),
        const InfoCard(
          title: '제외된 기능',
          body:
              '비공식 로그인, 스크래핑, 예약 자동화는 포함하지 않습니다. 구매 옵션은 공식 API 또는 외부 판매처 이동으로만 제공합니다.',
        ),
      ],
    );
  }
}

class BookTile extends StatelessWidget {
  const BookTile({
    required this.book,
    required this.state,
    this.showRank = false,
    super.key,
  });
  final Book book;
  final AppState state;
  final bool showRank;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: BookCover(book: book, rank: showRank ? book.rank : null),
          title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${book.author}\n${book.publisher} ${book.publishYear} · ISBN ${book.isbn}\n${book.reason}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: '즐겨찾기',
            icon: Icon(
              state.isFavoriteBook(book)
                  ? Icons.bookmark
                  : Icons.bookmark_border,
            ),
            onPressed: () => state.toggleBook(book),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BookDetailPage(book: book, state: state),
            ),
          ),
        ),
      ),
    );
  }
}

class BookDetailPage extends StatefulWidget {
  const BookDetailPage({required this.book, required this.state, super.key});
  final Book book;
  final AppState state;
  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  late Future<List<LibraryHolding>> future;
  bool onlyAvailable = true;

  @override
  void initState() {
    super.initState();
    future = widget.state.holdings(widget.book);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('책 상세')),
      body: FutureBuilder<List<LibraryHolding>>(
        future: future,
        builder: (context, snapshot) {
          final holdings = snapshot.data ?? const <LibraryHolding>[];
          final available = holdings
              .where((e) => e.status == LoanStatus.available)
              .length;
          final ranked = widget.state.distance.rankNearbyHoldings(
            holdings,
            selectedRegion: widget.state.region,
            userLat: widget.state.userLat,
            userLon: widget.state.userLon,
          );
          final list = onlyAvailable ? ranked : holdings;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCover(book: widget.book, width: 88, height: 124),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.book.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.book.author} · ${widget.book.publisher} ${widget.book.publishYear}',
                        ),
                        Text('ISBN ${widget.book.isbn}'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            StatusChip(
                              icon: Icons.inventory_2_outlined,
                              label: '보유 ${holdings.length}곳',
                            ),
                            StatusChip(
                              icon: Icons.check_circle_outline,
                              label: '대출 가능 $available곳',
                            ),
                            if (widget.book.isDemo)
                              const StatusChip(
                                icon: Icons.science_outlined,
                                label: '데모 데이터',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      widget.state.isFavoriteBook(widget.book)
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    onPressed: () => widget.state.toggleBook(widget.book),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PurchasePage(
                      state: widget.state,
                      initialBook: widget.book,
                    ),
                  ),
                ),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('구매 옵션 확인'),
              ),
              const SizedBox(height: 8),
              if (widget.book.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(widget.book.description!),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => setState(() => onlyAvailable = true),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('대출 가능 우선'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await widget.state.requestLocation();
                        setState(() {});
                      },
                      icon: const Icon(Icons.my_location),
                      label: const Text('가까운 순'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('대출 가능')),
                  ButtonSegment(value: false, label: Text('전체 보유')),
                ],
                selected: {onlyAvailable},
                onSelectionChanged: (v) =>
                    setState(() => onlyAvailable = v.first),
              ),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (list.isEmpty)
                const StateBox(
                  icon: Icons.local_library_outlined,
                  title: '표시할 보유 도서관이 없습니다',
                )
              else
                ...list.map(
                  (h) => LibraryTile(
                    library: h.library,
                    state: widget.state,
                    holding: h,
                    alertBook: widget.book,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class LibraryTile extends StatelessWidget {
  const LibraryTile({
    required this.library,
    required this.state,
    this.holding,
    this.alertBook,
    super.key,
  });
  final LibraryBranch library;
  final AppState state;
  final LibraryHolding? holding;
  final Book? alertBook;

  @override
  Widget build(BuildContext context) {
    final status = holding?.status;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
                child: const Icon(Icons.local_library),
              ),
              title: Text(
                library.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${library.address}\n${library.region == state.region ? '선택 지역' : '인접 지역'} · ${state.distance.distanceLabel(library)}${status == null ? '' : ' · ${status.label}'}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: '즐겨찾기',
                icon: Icon(
                  state.isFavoriteLibrary(library)
                      ? Icons.star
                      : Icons.star_border,
                ),
                onPressed: () => state.toggleLibrary(library),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LibraryDetailPage(
                    library: library,
                    state: state,
                    holding: holding,
                  ),
                ),
              ),
            ),
            if (holding?.status == LoanStatus.loaned && alertBook != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final message = await state.addLoanAlert(
                      book: alertBook!,
                      holding: holding!,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            message ??
                                '대출 가능 알림을 등록했습니다. 방문 전 도서관 홈페이지나 전화로 최종 확인해 주세요.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('대출 가능 알림 받기'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LibraryDetailPage extends StatelessWidget {
  const LibraryDetailPage({
    required this.library,
    required this.state,
    this.holding,
    super.key,
  });
  final LibraryBranch library;
  final AppState state;
  final LibraryHolding? holding;

  @override
  Widget build(BuildContext context) {
    final disabled = library.homepage == null;
    return Scaffold(
      appBar: AppBar(title: const Text('도서관 상세')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(library.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (holding != null)
                StatusChip(
                  icon: Icons.fact_check_outlined,
                  label: holding!.status.label,
                ),
              StatusChip(
                icon: Icons.place_outlined,
                label: state.distance.distanceLabel(library),
              ),
              if (library.operator != null)
                StatusChip(
                  icon: Icons.account_balance_outlined,
                  label: library.operator!,
                ),
            ],
          ),
          const SizedBox(height: 16),
          InfoCard(title: '주소', body: library.address),
          if (library.phone != null)
            InfoCard(title: '전화번호', body: library.phone!),
          if (library.homepage != null)
            InfoCard(title: '홈페이지', body: library.homepage!),
          if (library.closedInfo != null)
            InfoCard(title: '휴관일', body: library.closedInfo!),
          if (library.operatingTime != null)
            InfoCard(title: '운영시간', body: library.operatingTime!),
          if (holding != null)
            InfoCard(
              title: '최근 조회 시각',
              body: holding!.checkedAt.toLocal().toString().substring(0, 16),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: disabled
                ? null
                : () => state.links.openWebsite(library.homepage),
            icon: const Icon(Icons.open_in_new),
            label: const Text('도서관 홈페이지에서 확인'),
          ),
          OutlinedButton.icon(
            onPressed: library.phone == null
                ? null
                : () => state.links.call(library.phone),
            icon: const Icon(Icons.call),
            label: const Text('전화하기'),
          ),
          OutlinedButton.icon(
            onPressed: () => state.links.directions(library),
            icon: const Icon(Icons.directions),
            label: const Text('길찾기'),
          ),
          if (disabled)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('공식 홈페이지 URL이 없어 이동 버튼을 비활성화했습니다.'),
            ),
        ],
      ),
    );
  }
}

class SearchLauncher extends StatelessWidget {
  const SearchLauncher({required this.onTap, super.key});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(28),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Row(
        children: [
          Icon(Icons.search),
          SizedBox(width: 10),
          Text('책 제목, 저자, ISBN 검색'),
        ],
      ),
    ),
  );
}

class RegionBar extends StatelessWidget {
  const RegionBar({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: state.region,
          decoration: const InputDecoration(
            labelText: '기본 지역',
            border: OutlineInputBorder(),
          ),
          items: regions
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            if (v != null) state.updateRegion(v);
          },
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        tooltip: '현재 위치',
        onPressed: state.requestLocation,
        icon: const Icon(Icons.my_location),
      ),
    ],
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.action,
    this.onTap,
    super.key,
  });
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    ),
  );
}

class BookCover extends StatelessWidget {
  const BookCover({
    this.book,
    this.rank,
    this.width = 56,
    this.height = 78,
    super.key,
  });
  final Book? book;
  final int? rank;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) {
    final url = book?.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFFE8EFE9),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (url != null)
              Image.network(
                url,
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.menu_book, size: 28),
              )
            else
              const Icon(Icons.menu_book, size: 28),
            if (rank != null)
              Positioned(top: 4, left: 4, child: Badge(label: Text('$rank'))),
          ],
        ),
      ),
    );
  }
}

class ModePill extends StatelessWidget {
  const ModePill({required this.isDemo, super.key});
  final bool isDemo;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: isDemo ? const Color(0xFFFFF3CD) : const Color(0xFFDFF5E8),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      isDemo ? '데모 데이터' : 'API 연결',
      style: Theme.of(context).textTheme.labelMedium,
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.icon, required this.label, super.key});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 18), label: Text(label));
}

class InfoCard extends StatelessWidget {
  const InfoCard({required this.title, required this.body, super.key});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(body),
          ],
        ),
      ),
    ),
  );
}

class MessageCard extends StatelessWidget {
  const MessageCard({required this.message, super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}

class StateBox extends StatelessWidget {
  const StateBox({
    required this.icon,
    required this.title,
    this.action,
    this.onTap,
    super.key,
  });
  final IconData icon;
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 8),
          Text(title),
          if (action != null)
            TextButton(onPressed: onTap, child: Text(action!)),
        ],
      ),
    ),
  );
}

Future<void> showPrefsSheet(BuildContext context, AppState state) async {
  var age = state.prefs.ageGroup;
  var gender = state.prefs.gender;
  var selected = [...state.prefs.genres];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('추천 조건', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: age,
              decoration: const InputDecoration(labelText: '연령대'),
              items: ageGroups
                  .where((e) => e != '전체')
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setSheet(() => age = v!),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: genders
                  .map((e) => ButtonSegment(value: e, label: Text(e)))
                  .toList(),
              selected: {gender},
              onSelectionChanged: (v) => setSheet(() => gender = v.first),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: genreMappings
                  .map(
                    (g) => FilterChip(
                      label: Text(g.label),
                      selected: selected.contains(g.label),
                      onSelected: (on) => setSheet(() {
                        if (on) {
                          selected.add(g.label);
                        } else {
                          selected.remove(g.label);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setSheet(() {
                      age = '30대';
                      gender = '전체';
                      selected = ['문학'];
                    }),
                    child: const Text('초기화'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(
                        state.updatePrefs(
                          RecommendationPrefs(
                            ageGroup: age,
                            gender: gender,
                            genres: selected.isEmpty ? ['문학'] : selected,
                          ),
                        ),
                      );
                    },
                    child: const Text('저장'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showPopularFilter(BuildContext context, AppState state) async {
  var age = state.popularAge;
  var gender = state.popularGender;
  var genre = state.popularGenre;
  var period = state.popularPeriod;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('인기 대출도서 필터', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: period,
              decoration: const InputDecoration(labelText: '조회 기간'),
              items: loanPeriods
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setSheet(() => period = v!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: age,
              decoration: const InputDecoration(labelText: '연령대'),
              items: ageGroups
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setSheet(() => age = v!),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: genders
                  .map((e) => ButtonSegment(value: e, label: Text(e)))
                  .toList(),
              selected: {gender},
              onSelectionChanged: (v) => setSheet(() => gender = v.first),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: genre,
              decoration: const InputDecoration(labelText: '장르'),
              items: [
                '전체',
                ...genreMappings.map((e) => e.label),
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setSheet(() => genre = v!),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                unawaited(
                  state.loadPopular(
                    ageGroup: age,
                    gender: gender,
                    genre: genre,
                    period: period,
                    forceRefresh: true,
                  ),
                );
              },
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    ),
  );
}

class PurchasePage extends StatefulWidget {
  const PurchasePage({required this.state, this.initialBook, super.key});
  final AppState state;
  final Book? initialBook;

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  final queryController = TextEditingController();
  List<BestsellerSource> sources = const [];
  List<String> categories = const ['종합'];
  List<BestsellerBook> bestsellers = const [];
  List<PurchaseOffer> offers = const [];
  String selectedSource = '';
  String selectedCategory = '종합';
  DateTime? lastUpdated;
  bool loading = true;
  bool offerLoading = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    final book = widget.initialBook;
    if (book != null) {
      queryController.text = book.isbn.isNotEmpty
          ? book.isbn
          : '${book.title} ${book.author}'.trim();
    }
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => loading = true);
    try {
      sources = await widget.state.purchaseApi.sources();
      categories = await widget.state.purchaseApi.categories();
      selectedSource = sources.isNotEmpty ? sources.first.source : '';
      selectedCategory = categories.contains(selectedCategory)
          ? selectedCategory
          : categories.first;
      await _loadBestsellers();
      final book = widget.initialBook;
      if (book != null) {
        await _loadOffers(
          isbn13: book.isbn,
          title: book.title,
          author: book.author,
        );
      }
    } catch (_) {
      message = '구매 서버에 연결할 수 없습니다.';
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _loadBestsellers() async {
    final result = await widget.state.purchaseApi.bestsellers(
      source: selectedSource,
      category: selectedCategory,
    );
    bestsellers = result.$1;
    lastUpdated = result.$2;
    message = result.$3;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadOffers({
    String isbn13 = '',
    String isbn10 = '',
    String title = '',
    String author = '',
  }) async {
    setState(() => offerLoading = true);
    final result = await widget.state.purchaseApi.offers(
      isbn13: isbn13,
      isbn10: isbn10,
      title: title,
      author: author,
    );
    offers = result.$1;
    message = result.$2;
    if (mounted) {
      setState(() => offerLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.purchaseEnabled) {
      return const Center(
        child: StateBox(
          icon: Icons.shopping_bag_outlined,
          title: '구매 탭이 비활성화되어 있습니다.',
        ),
      );
    }
    if (!widget.state.purchaseApi.isConfigured) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          StateBox(
            icon: Icons.settings_outlined,
            title: '구매 서버 주소가 설정되지 않았습니다.',
          ),
          InfoCard(
            title: '설정 필요',
            body:
                'PURCHASE_API_BASE_URL을 Railway 서버 주소로 입력하면 구매 옵션과 베스트셀러가 활성화됩니다.',
          ),
        ],
      );
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    final pricedOffers = offers.where((offer) => offer.isPriced).toList();
    final externalLinks = offers
        .where((offer) => offer.isExternalLink)
        .toList();
    var sourceLabel = '베스트셀러';
    for (final source in sources) {
      if (source.source == selectedSource) {
        sourceLabel = source.label;
        break;
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SearchBar(
          controller: queryController,
          hintText: 'ISBN, 제목, 저자로 구매 옵션 검색',
          leading: const Icon(Icons.search),
          onSubmitted: (value) => _loadOffers(title: value),
          trailing: [
            IconButton(
              onPressed: () => _loadOffers(title: queryController.text),
              icon: const Icon(Icons.manage_search),
              tooltip: '구매 옵션 확인',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sources.length > 1)
          SegmentedButton<String>(
            segments: sources
                .map(
                  (s) => ButtonSegment(value: s.source, label: Text(s.label)),
                )
                .toList(),
            selected: {selectedSource},
            onSelectionChanged: (value) async {
              selectedSource = value.first;
              await _loadBestsellers();
            },
          ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: selectedCategory,
          decoration: const InputDecoration(
            labelText: '카테고리',
            border: OutlineInputBorder(),
          ),
          items: categories
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (value) async {
            if (value != null) {
              selectedCategory = value;
              await _loadBestsellers();
            }
          },
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: sourceLabel,
          body:
              '마지막 갱신: ${lastUpdated == null ? '확인 필요' : lastUpdated!.toLocal().toString().substring(0, 16)}\n가격, 재고, 배송비, 혜택은 변경될 수 있으며 결제 전 판매처에서 최종 확인해야 합니다.',
        ),
        if (message.isNotEmpty) MessageCard(message: message),
        if (offerLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          ),
        if (offers.isNotEmpty) ...[
          const SectionHeader(title: '구매 옵션'),
          if (pricedOffers.isNotEmpty)
            ...pricedOffers.map(
              (offer) => _PurchaseOfferTile(
                offer: offer,
                openUrl: widget.state.links.openWebsite,
              ),
            ),
          if (externalLinks.isNotEmpty)
            ...externalLinks.map(
              (offer) => _PurchaseOfferTile(
                offer: offer,
                openUrl: widget.state.links.openWebsite,
              ),
            ),
          const InfoCard(
            title: '판매처 안내',
            body:
                '이 앱은 각 판매처의 공식 앱이나 공식 제휴 앱이 아닙니다. 외부 판매처로 이동하면 해당 업체의 정책이 적용됩니다.',
          ),
          const SizedBox(height: 16),
        ],
        const SectionHeader(title: '베스트셀러'),
        if (sources.isEmpty)
          const StateBox(
            icon: Icons.menu_book_outlined,
            title: '베스트셀러 데이터 소스 준비 중입니다.',
          )
        else if (bestsellers.isEmpty)
          const StateBox(
            icon: Icons.menu_book_outlined,
            title: '베스트셀러 데이터가 없습니다.',
          )
        else
          ...bestsellers.map(
            (book) => Card(
              child: ListTile(
                leading: Badge(
                  label: Text('${book.rank}'),
                  child: const Icon(Icons.menu_book),
                ),
                title: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${book.author}\n${book.publisher} · ${book.isbn13.isEmpty ? book.isbn10 : book.isbn13}',
                ),
                onTap: () => _loadOffers(
                  isbn13: book.isbn13,
                  isbn10: book.isbn10,
                  title: book.title,
                  author: book.author,
                ),
                trailing: IconButton(
                  tooltip: sourceLabel,

                  icon: const Icon(Icons.open_in_new),
                  onPressed: book.productUrl.isEmpty
                      ? null
                      : () => widget.state.links.openWebsite(book.productUrl),
                ),
              ),
            ),
          ),
        const InfoCard(
          title: '데이터 출처 안내',
          body:
              'YES24는 공식 베스트셀러 RSS와 외부 이동만 제공합니다. 알라딘은 Open API에서 제공되는 범위의 가격과 상품 정보를 표시합니다. 교보문고는 외부 검색 이동만 제공합니다.',
        ),
      ],
    );
  }
}

class _PurchaseOfferTile extends StatelessWidget {
  const _PurchaseOfferTile({required this.offer, required this.openUrl});
  final PurchaseOffer offer;
  final Future<void> Function(String url) openUrl;

  @override
  Widget build(BuildContext context) {
    final priceText = offer.isPriced
        ? '${_formatWon(offer.price)}원'
        : offer.message.isNotEmpty
        ? offer.message
        : '가격은 판매처에서 확인';
    final originalText = offer.originalPrice == null
        ? ''
        : '정가 ${_formatWon(offer.originalPrice)}원';
    final fetchedText = offer.fetchedAt == null
        ? '조회 시각 확인 필요'
        : '조회 ${offer.fetchedAt!.toLocal().toString().substring(0, 16)}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.storefront_outlined),
        title: Text(offer.label),
        subtitle: Text(
          [
            if (offer.productName.isNotEmpty) offer.productName,
            priceText,
            if (originalText.isNotEmpty) originalText,
            if (offer.isPriced) fetchedText,
            offer.matchedBy,
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: FilledButton.tonalIcon(
          onPressed: offer.productUrl.isEmpty
              ? null
              : () => openUrl(offer.productUrl),
          icon: const Icon(Icons.open_in_new),
          label: Text(offer.actionText),
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

class LoanAlertSection extends StatelessWidget {
  const LoanAlertSection({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '대출 알림'),
        const InfoCard(
          title: '안내',
          body:
              '도서관 정보나루의 대출 상태는 실제 도서관 현황과 반영 시점에 차이가 있을 수 있습니다. 알림을 받아도 방문 전 도서관 홈페이지나 전화로 최종 확인해 주세요.',
        ),
        if (state.loanAlertItems.isEmpty)
          const StateBox(
            icon: Icons.notifications_none,
            title: '등록한 대출 알림이 없습니다',
          )
        else
          ...state.loanAlertItems.map(
            (item) => Card(
              child: ListTile(
                leading: Icon(
                  item.completed
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${item.libraryName}\n${item.lastStatus} · 마지막 확인: ${item.lastCheckedAt == null ? '없음' : item.lastCheckedAt!.toLocal().toString().substring(0, 16)}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'check') {
                      unawaited(state.checkLoanAlertNow(item));
                    }
                    if (value == 'remove') {
                      unawaited(state.removeLoanAlert(item.id));
                    }
                    if (value == 'restart') {
                      unawaited(state.restartLoanAlert(item.id));
                    }
                    if (value == 'home') {
                      unawaited(state.links.openWebsite(item.homepage));
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'check', child: Text('지금 확인')),
                    if (item.completed)
                      const PopupMenuItem(
                        value: 'restart',
                        child: Text('다시 등록'),
                      ),
                    const PopupMenuItem(value: 'home', child: Text('도서관 홈페이지')),
                    const PopupMenuItem(value: 'remove', child: Text('알림 해제')),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
