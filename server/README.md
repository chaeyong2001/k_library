# K Library Railway API

FastAPI 기반 구매 옵션/베스트셀러 서버입니다. Flutter 앱에는 `PURCHASE_API_BASE_URL`만 전달하고, 외부 서비스 키는 Railway 환경변수에만 보관합니다.

## 실행

```bash
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Railway 시작 명령:

```bash
uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

## DB 초기화

앱 시작 시 SQLAlchemy가 `kl_` 접두사 테이블을 자동 생성합니다. Alembic 마이그레이션은 아직 적용하지 않았습니다.

## 환경변수

- `DATABASE_URL`
- `ADMIN_SYNC_KEY`
- `ALADIN_TTB_KEY`
- `BESTSELLER_REFRESH_HOURS=72`
- `PURCHASE_CACHE_TTL_HOURS=12`
- `ENABLE_ALADIN_BESTSELLER=true`
- `ENABLE_YES24_BESTSELLER=false`
- `ENABLE_ALADIN_PURCHASE=true`
- `ENABLE_YES24_LINK=true`
- `ENABLE_KYOBO_LINK=true`
- `ENABLE_NAVER_SHOPPING=false`

1차 출시의 베스트셀러 소스는 알라딘 종이책/전자책 단일 소스입니다. YES24 베스트셀러 Provider는 공식 RSS/API가 다시 확인될 때까지 비활성으로 유지합니다. NAVER API HUB의 Shopping Insight API는 상품 검색/판매처별 가격 API가 아니므로 가격 조회에 사용하지 않습니다. 현재 NAVER Provider는 Registry에 연결 가능한 비활성 확장점이며, `ENABLE_NAVER_SHOPPING=false`이면 생성하거나 호출하지 않습니다.

## 구매 옵션 정책

- 알라딘 Open API: ISBN 또는 제목/저자 기반 상품 조회, 판매가, 정가, 이미지, 상품 URL 제공
- YES24: 베스트셀러 소스에서는 제외, 구매 상세에서는 외부 검색/상품 이동 링크만 제공
- 교보문고: 외부 검색 이동만 제공
- HTML 스크래핑, 가짜 가격, 공식 출처가 아닌 가격 표현은 사용하지 않습니다.

## 수동 갱신

```bash
curl -X POST "$BASE/api/v1/bestsellers/refresh" -H "X-Admin-Token: $ADMIN_SYNC_KEY"
```


