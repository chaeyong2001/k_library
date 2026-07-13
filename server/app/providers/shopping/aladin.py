from urllib.parse import quote_plus
import httpx
from .base import Offer, ShoppingProvider

ALADIN_ITEM_LOOKUP = "http://www.aladin.co.kr/ttb/api/ItemLookUp.aspx"
ALADIN_ITEM_SEARCH = "http://www.aladin.co.kr/ttb/api/ItemSearch.aspx"


class AladinOfferProvider(ShoppingProvider):
    def __init__(self, ttb_key: str, *, timeout: float = 12.0):
        self.ttb_key = ttb_key
        self.timeout = timeout

    async def search(
        self,
        *,
        isbn13: str = "",
        isbn10: str = "",
        title: str = "",
        author: str = "",
    ) -> list[Offer]:
        if not self.ttb_key:
            return []
        if isbn13 or isbn10:
            by_isbn = await self._lookup(isbn13 or isbn10, isbn13=bool(isbn13))
            if by_isbn:
                return by_isbn
        query = " ".join(part for part in [title, author] if part).strip() or title.strip()
        if not query:
            return []
        return await self._search(query, matched_by="제목+저자" if author else "제목")

    async def _lookup(self, item_id: str, *, isbn13: bool) -> list[Offer]:
        params = {
            "ttbkey": self.ttb_key,
            "ItemId": item_id,
            "ItemIdType": "ISBN13" if isbn13 else "ISBN",
            "output": "js",
            "Version": "20131101",
        }
        data = await self._get(ALADIN_ITEM_LOOKUP, params)
        return self._offers(data.get("item", []), matched_by="ISBN")

    async def _search(self, query: str, *, matched_by: str) -> list[Offer]:
        params = {
            "ttbkey": self.ttb_key,
            "Query": query,
            "QueryType": "Keyword",
            "SearchTarget": "Book",
            "MaxResults": "10",
            "start": "1",
            "output": "js",
            "Version": "20131101",
        }
        data = await self._get(ALADIN_ITEM_SEARCH, params)
        return self._offers(data.get("item", []), matched_by=matched_by)

    async def _get(self, url: str, params: dict[str, str]) -> dict:
        async with httpx.AsyncClient(timeout=self.timeout, follow_redirects=True) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()
        return data if isinstance(data, dict) else {}

    def _offers(self, items: list[dict], *, matched_by: str) -> list[Offer]:
        offers: list[Offer] = []
        for item in items:
            title = str(item.get("title") or "")
            if not title or _blocked(title):
                continue
            price = _to_int(item.get("priceSales"))
            original = _to_int(item.get("priceStandard"))
            url = str(item.get("link") or "")
            if not url:
                query = quote_plus(str(item.get("isbn13") or title))
                url = f"https://www.aladin.co.kr/search/wsearchresult.aspx?SearchTarget=Book&SearchWord={query}"
            offers.append(
                Offer(
                    provider="aladin",
                    offer_type="priced_offer",
                    merchant_name="알라딘",
                    product_name=title,
                    isbn13=str(item.get("isbn13") or ""),
                    price=price,
                    original_price=original,
                    total_price=price,
                    product_url=url,
                    image_url=str(item.get("cover") or ""),
                    availability="판매처 확인",
                    matched_by=matched_by,
                    message="가격, 재고, 배송비, 혜택은 결제 전 판매처에서 최종 확인해 주세요.",
                    category=str(item.get("categoryName") or ""),
                )
            )
        return offers[:3]


def _blocked(value: str) -> bool:
    lowered = value.lower()
    return any(token in lowered for token in ["ebook", "전자책", "오디오북", "중고", "세트", "분철", "굿즈"])


def _to_int(value) -> int | None:
    try:
        text = str(value or "").replace(",", "").strip()
        return int(text) if text else None
    except Exception:
        return None
