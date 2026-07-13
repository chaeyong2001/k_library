# K Library Railway API

FastAPI 기반 구매/베스트셀러 서버입니다. Flutter 앱에는 `PURCHASE_API_BASE_URL`만 전달하고, 외부 서비스 키는 Railway 환경변수에만 보관합니다.

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

앱 시작 시 SQLAlchemy가 `kl_` 접두사 테이블을 생성합니다. 기존 Railway DB와 충돌하지 않도록 `kl_bestseller_items`, `kl_sync_runs`, `kl_purchase_offer_cache`만 사용합니다.

## 환경변수

`.env.example` 참고:

- `DATABASE_URL`
- `ENABLE_YES24_BESTSELLER`
- `ENABLE_ALADIN_BESTSELLER`
- `ENABLE_NAVER_SHOPPING`
- `ALADIN_TTB_KEY`
- `NAVER_API_HUB_*`
- `ADMIN_REFRESH_TOKEN`

## 수동 갱신

```bash
curl -X POST "$BASE/api/v1/bestsellers/refresh" -H "X-Admin-Token: $ADMIN_REFRESH_TOKEN"
```

YES24는 공식 RSS, 알라딘은 공식 Open API 구조를 사용합니다. NAVER API HUB 쇼핑은 엔드포인트와 인증 방식이 확정되면 `NAVER_API_HUB_SHOPPING_URL` 및 인증 환경변수를 입력해 활성화합니다.
