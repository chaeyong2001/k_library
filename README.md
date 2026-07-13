# K Library

로그인 없이 전국 국·공립도서관 도서 검색, 인기 대출도서 필터, 보유 도서관과 대출 가능 여부, 가까운 도서관을 확인하는 Flutter Android 앱입니다.

## API 키 연결

개발 중에는 `lib/config/local_dev_config.dart`에 로컬 전용 정보나루 키를 입력한 뒤 `flutter run`만 실행합니다. 이 파일은 `.gitignore` 처리되어 저장소에 올리지 않습니다.

기존 `--dart-define=DATA4LIBRARY_AUTH_KEY=...` 방식도 debug/profile 개발 실행에서는 유지됩니다. Release/AAB에서는 Flutter 앱에 정보나루 키를 직접 포함하지 않도록 차단합니다.

## 구현된 실제 API 흐름

- `srchBooks`: 제목, 저자, ISBN 검색
- `loanItemSrch`: 최근 7일/30일/90일, 연령대, 성별, 장르 기반 인기 대출도서
- `libSrch`: 지역별 도서관 목록
- `libSrchByBook`: 선택 지역 내 보유 도서관 조회
- `bookExist`: 도서관별 보유 여부와 대출 가능 여부 확인

## 주요 기능

- 홈, 검색, 도서관, 보관함, 설정 하단 내비게이션
- 맞춤 추천 조건 저장과 실제 인기 대출도서 기반 추천
- 인기 대출도서 필터 UI와 실제 API 연결
- 도서 제목, 저자, ISBN 검색과 최근 검색어 관리
- 책 상세에서 보유 도서관, 대출 가능 상태, 최근 조회 시각 표시
- 현재 위치 허용 시 거리 계산과 가까운 도서관 정렬
- 위치 권한 거부 시 지역 선택 방식 사용
- 도서관 홈페이지, 전화, 길찾기 외부 이동
- 즐겨찾기, 최근 본 책, 최근 검색어 로컬 저장

비공식 로그인, HTML 스크래핑, 예약 자동화는 포함하지 않습니다. 구매 옵션은 공식 API 또는 외부 판매처 이동으로만 제공합니다.
## 개발 실행 설정

개발·APK 실기기 테스트 단계에서는 `flutter run`만으로 실행할 수 있도록 로컬 개발 설정 파일을 사용합니다.

1. `lib/config/local_dev_config.example.dart`를 참고합니다.
2. 같은 폴더의 `lib/config/local_dev_config.dart`에 개발용 정보나루 키를 직접 입력합니다.
3. Railway 구매 API 주소 기본값은 `https://k-library-api-production.up.railway.app`입니다.
4. `local_dev_config.dart`는 `.gitignore`에 포함되어야 하며 저장소에 올리지 않습니다.

개발 중 실행:

```powershell
flutter run
```

기존 방식도 유지됩니다. 우선순위는 다음과 같습니다.

1. `--dart-define`
2. `.env`
3. `lib/config/local_dev_config.dart`

Release/AAB에서는 local dev 값이 assert-only 경로로 제거되며, `.env`도 Flutter asset에 포함하지 않습니다. 출시 전에는 `docs/release_security_checklist.md`를 확인하세요.

주의: `ALADIN_TTB_KEY`, `DATABASE_URL`, `ADMIN_SYNC_KEY` 같은 Railway 서버 전용 값은 Flutter 코드나 `--dart-define`에 넣지 않습니다.


