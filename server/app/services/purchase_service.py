from datetime import datetime, timedelta, timezone
import json
from sqlalchemy import select
from sqlalchemy.orm import Session
from ..config import get_settings
from ..models.db_models import PurchaseOfferCache
from ..providers.shopping.naver import NaverApiHubShoppingProvider
from ..providers.shopping.base import Offer

PRIORITY_MERCHANTS = ["YES24", "교보문고", "알라딘", "쿠팡", "영풍문고"]

class PurchaseService:
    def __init__(self, db: Session):
        self.db = db
        self.settings = get_settings()

    async def offers(self, *, isbn13: str = "", isbn10: str = "", title: str = "", author: str = "") -> tuple[list[Offer], bool, bool, str]:
        cache_key = self._cache_key(isbn13, isbn10, title, author)
        cached = self.db.scalar(select(PurchaseOfferCache).where(PurchaseOfferCache.cache_key == cache_key))
        now = datetime.now(timezone.utc)
        if cached and cached.expires_at > now:
            return [Offer(**item) for item in json.loads(cached.payload_json)], True, False, ""
        if not self.settings.enable_naver_shopping:
            if cached:
                return [Offer(**item) for item in json.loads(cached.payload_json)], True, True, "가격 정보는 현재 비활성화되어 오래된 캐시만 표시합니다."
            return [], False, False, "가격 조회 소스가 비활성화되어 있습니다."
        try:
            provider = NaverApiHubShoppingProvider(endpoint=self.settings.naver_api_hub_shopping_url, client_id=self.settings.naver_api_hub_client_id, client_secret=self.settings.naver_api_hub_client_secret, api_key=self.settings.naver_api_hub_api_key)
            raw = await provider.search(isbn13=isbn13, isbn10=isbn10, title=title, author=author)
            offers = self._normalize(raw, isbn13=isbn13, isbn10=isbn10, title=title, author=author)
            self._save_cache(cache_key, isbn13 or isbn10 or title, offers)
            return offers, False, False, "" if offers else "가격 정보가 없습니다."
        except Exception:
            if cached:
                return [Offer(**item) for item in json.loads(cached.payload_json)], True, True, "외부 가격 조회 실패로 오래된 캐시를 표시합니다."
            return [], False, False, "가격 정보를 불러올 수 없습니다."

    def _normalize(self, offers: list[Offer], *, isbn13: str, isbn10: str, title: str, author: str) -> list[Offer]:
        unique: dict[str, Offer] = {}
        for offer in offers:
            name = offer.product_name.lower()
            if any(block in name for block in ["ebook", "전자책", "오디오북", "중고", "세트", "분철", "굿즈"]):
                continue
            if offer.merchant_name and not any(m in offer.merchant_name for m in PRIORITY_MERCHANTS):
                continue
            key = offer.merchant_name or offer.product_url
            offer.matched_by = "ISBN" if isbn13 or isbn10 else "제목+저자"
            unique.setdefault(key, offer)
        result = list(unique.values())
        result.sort(key=lambda x: x.total_price if x.total_price is not None else 10**12)
        return result[:5]

    def _save_cache(self, cache_key: str, normalized_query: str, offers: list[Offer]) -> None:
        payload = json.dumps([offer.__dict__ | {"fetched_at": offer.fetched_at.isoformat()} for offer in offers], ensure_ascii=False, default=str)
        now = datetime.now(timezone.utc)
        item = self.db.scalar(select(PurchaseOfferCache).where(PurchaseOfferCache.cache_key == cache_key))
        if item is None:
            item = PurchaseOfferCache(cache_key=cache_key, query_type="isbn" if normalized_query.isdigit() else "keyword", normalized_query=normalized_query, payload_json=payload, expires_at=now + timedelta(hours=self.settings.offer_cache_ttl_hours), last_success_at=now)
            self.db.add(item)
        else:
            item.payload_json = payload
            item.expires_at = now + timedelta(hours=self.settings.offer_cache_ttl_hours)
            item.last_success_at = now
            item.stale = False
        self.db.commit()

    def _cache_key(self, isbn13: str, isbn10: str, title: str, author: str) -> str:
        value = isbn13.strip() or isbn10.strip() or f"{title.strip()} {author.strip()}".strip()
        return "purchase:" + " ".join(value.lower().split())
