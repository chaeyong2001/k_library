from datetime import datetime, timedelta, timezone
import json
from sqlalchemy import select
from sqlalchemy.orm import Session
from ..config import get_settings
from ..models.db_models import PurchaseOfferCache
from ..providers.shopping.base import Offer
from ..providers.shopping.registry import ShoppingProviderEntry, ShoppingProviderRegistry


class PurchaseService:
    def __init__(self, db: Session):
        self.db = db
        self.settings = get_settings()
        self.registry = ShoppingProviderRegistry(self.settings)

    async def offers(
        self,
        *,
        isbn13: str = "",
        isbn10: str = "",
        title: str = "",
        author: str = "",
        content_type: str = "physical_book",
        source_item_id: str = "",
    ) -> tuple[list[Offer], bool, bool, str]:
        cache_key = self._cache_key(isbn13, isbn10, title, author, content_type, source_item_id)
        cached = self.db.scalar(
            select(PurchaseOfferCache).where(PurchaseOfferCache.cache_key == cache_key)
        )
        now = datetime.now(timezone.utc)
        priced: list[Offer] = []
        cached_used = False
        stale = False
        message = ""

        if cached and cached.expires_at > now:
            priced = self._decode_cache(cached.payload_json)
            cached_used = True
        else:
            try:
                priced = await self._priced_offers(
                    isbn13=isbn13,
                    isbn10=isbn10,
                    title=title,
                    author=author,
                    content_type=content_type,
                    source_item_id=source_item_id,
                )
                priced = self._normalize_priced(
                    priced,
                    isbn13=isbn13,
                    isbn10=isbn10,
                    title=title,
                    author=author,
                    content_type=content_type,
                )
                if priced:
                    self._save_cache(cache_key, isbn13 or isbn10 or title, priced)
                elif cached:
                    priced = self._decode_cache(cached.payload_json)
                    cached_used = True
                    stale = True
                    message = "가격 조회 결과가 없어 오래된 캐시를 표시합니다."
                else:
                    message = "가격 결과가 없습니다. 외부 판매처에서 확인해 주세요."
            except Exception:
                if cached:
                    priced = self._decode_cache(cached.payload_json)
                    cached_used = True
                    stale = True
                    message = "가격 조회 실패로 오래된 캐시를 표시합니다."
                else:
                    message = "가격을 불러올 수 없습니다. 외부 판매처에서 확인해 주세요."

        links = await self._external_links(
            isbn13=isbn13,
            isbn10=isbn10,
            title=title,
            author=author,
            content_type=content_type,
            source_item_id=source_item_id,
        )
        return [*priced, *links], cached_used, stale, message

    async def _priced_offers(self, *, isbn13: str, isbn10: str, title: str, author: str, content_type: str, source_item_id: str = "") -> list[Offer]:
        offers: list[Offer] = []
        for entry in self.registry.priced_entries():
            result = await entry.provider.search(
                isbn13=isbn13,
                isbn10=isbn10,
                title=title,
                author=author,
                content_type=content_type,
                source_item_id=source_item_id,
            )
            offers.extend(self._with_meta(result, entry))
        return offers

    async def _external_links(self, *, isbn13: str, isbn10: str, title: str, author: str, content_type: str, source_item_id: str = "") -> list[Offer]:
        links: list[Offer] = []
        for entry in self.registry.external_link_entries():
            result = await entry.provider.search(
                isbn13=isbn13,
                isbn10=isbn10,
                title=title,
                author=author,
                content_type=content_type,
                source_item_id=source_item_id,
            )
            links.extend(self._with_meta(result, entry))
        return links

    async def format_candidates(
        self,
        *,
        title: str = "",
        author: str = "",
        publisher: str = "",
        target_content_type: str = "physical_book",
    ) -> tuple[str, str, list[dict], str]:
        query_title = " ".join(title.split())
        normalized_title = " ".join(query_title.split())
        if not query_title:
            return query_title, normalized_title, [], "후보 검색에 사용할 제목이 없습니다."
        candidates: list[dict] = []
        for entry in self.registry.priced_entries():
            finder = getattr(entry.provider, "format_candidates", None)
            if finder is None:
                continue
            result = await finder(
                title=query_title,
                author=author,
                publisher=publisher,
                content_type=target_content_type,
                limit=10,
            )
            candidates.extend(result)
        candidates.sort(key=lambda item: item.get("match_score", 0), reverse=True)
        safe_message = "" if candidates else "확인 가능한 후보 도서를 찾지 못했습니다."
        return query_title, normalized_title, candidates[:10], safe_message

    async def search_results(
        self,
        *,
        query: str = "",
        isbn13: str = "",
        isbn10: str = "",
        content_type: str = "physical_book",
        limit: int = 20,
    ) -> tuple[list[dict], str]:
        results: list[dict] = []
        for entry in self.registry.priced_entries():
            finder = getattr(entry.provider, "search_products", None)
            if finder is None:
                continue
            results.extend(
                await finder(
                    query=query,
                    isbn13=isbn13,
                    isbn10=isbn10,
                    content_type=content_type,
                    limit=limit,
                )
            )
        results = self._dedupe_search_results(results)
        results.sort(key=lambda item: item.get("match_score", 0), reverse=True)
        return results[:limit], "" if results else "검색 조건에 맞는 도서를 찾지 못했습니다."

    def _with_meta(self, offers: list[Offer], entry: ShoppingProviderEntry) -> list[Offer]:
        for offer in offers:
            offer.provider = offer.provider or entry.meta.provider_id
            offer.merchant_name = offer.merchant_name or entry.meta.display_name
            offer.display_name = entry.meta.display_name
            offer.source_type = entry.meta.role
            offer.offer_type = offer.offer_type or entry.meta.offer_type
            offer.description = entry.meta.description
            offer.action_label = entry.meta.action_label
        return offers

    def _normalize_priced(self, offers: list[Offer], *, isbn13: str, isbn10: str, title: str, author: str, content_type: str = "physical_book") -> list[Offer]:
        unique: dict[str, Offer] = {}
        for offer in offers:
            if offer.offer_type != "priced_offer":
                continue
            key = offer.provider + ":" + (offer.isbn13 or offer.product_url or offer.product_name)
            if isbn13 or isbn10:
                offer.matched_by = "ISBN"
            elif title and author:
                offer.matched_by = "제목+저자"
            elif title:
                offer.matched_by = "제목"
            unique.setdefault(key, offer)
        result = list(unique.values())
        result.sort(key=lambda x: x.total_price if x.total_price is not None else 10**12)
        return result[:3]

    def _decode_cache(self, payload_json: str) -> list[Offer]:
        offers: list[Offer] = []
        for item in json.loads(payload_json):
            if item.get("fetched_at"):
                item["fetched_at"] = datetime.fromisoformat(item["fetched_at"])
            offers.append(Offer(**item))
        return offers

    def _save_cache(self, cache_key: str, normalized_query: str, offers: list[Offer]) -> None:
        payload = json.dumps(
            [
                offer.__dict__ | {"fetched_at": offer.fetched_at.isoformat()}
                for offer in offers
                if offer.offer_type == "priced_offer"
            ],
            ensure_ascii=False,
            default=str,
        )
        now = datetime.now(timezone.utc)
        item = self.db.scalar(
            select(PurchaseOfferCache).where(PurchaseOfferCache.cache_key == cache_key)
        )
        if item is None:
            item = PurchaseOfferCache(
                cache_key=cache_key,
                query_type="isbn" if normalized_query.isdigit() else "keyword",
                normalized_query=normalized_query,
                payload_json=payload,
                expires_at=now + timedelta(hours=self.settings.purchase_cache_ttl_hours),
                last_success_at=now,
            )
            self.db.add(item)
        else:
            item.payload_json = payload
            item.expires_at = now + timedelta(hours=self.settings.purchase_cache_ttl_hours)
            item.last_success_at = now
            item.stale = False
        self.db.commit()

    def _cache_key(self, isbn13: str, isbn10: str, title: str, author: str, content_type: str, source_item_id: str = "") -> str:
        value = source_item_id.strip() or isbn13.strip() or isbn10.strip() or f"{title.strip()} {author.strip()}".strip()
        return f"purchase:{content_type}:aladin:" + " ".join(value.lower().split())

    def _dedupe_search_results(self, results: list[dict]) -> list[dict]:
        unique: dict[str, dict] = {}
        for item in results:
            key = (
                item.get("source_item_id")
                or item.get("isbn13")
                or item.get("isbn10")
                or ":".join(
                    [
                        str(item.get("title") or "").strip().lower(),
                        str(item.get("author") or "").strip().lower(),
                        str(item.get("publisher") or "").strip().lower(),
                        str(item.get("content_type") or ""),
                    ]
                )
            )
            if key and key not in unique:
                unique[key] = item
        return list(unique.values())

