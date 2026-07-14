from urllib.parse import quote_plus
from difflib import SequenceMatcher
from html import unescape
import re
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
        content_type: str = "physical_book",
    ) -> list[Offer]:
        if not self.ttb_key:
            return []
        if isbn13 or isbn10:
            by_isbn = await self._lookup(
                isbn13 or isbn10,
                isbn13=bool(isbn13),
                content_type=content_type,
            )
            if by_isbn:
                return by_isbn
        query = " ".join(part for part in [title, author] if part).strip() or title.strip()
        if not query:
            return []
        return await self._search(
            query,
            matched_by="제목+저자" if author else "제목",
            content_type=content_type,
            title=title,
            author=author,
        )

    async def _lookup(self, item_id: str, *, isbn13: bool, content_type: str) -> list[Offer]:
        params = {
            "ttbkey": self.ttb_key,
            "ItemId": item_id,
            "ItemIdType": "ISBN13" if isbn13 else "ISBN",
            "output": "js",
            "Version": "20131101",
        }
        data = await self._get(ALADIN_ITEM_LOOKUP, params)
        return self._offers(data.get("item", []), matched_by="ISBN", content_type=content_type)

    async def _search(
        self,
        query: str,
        *,
        matched_by: str,
        content_type: str,
        title: str = "",
        author: str = "",
    ) -> list[Offer]:
        params = {
            "ttbkey": self.ttb_key,
            "Query": query,
            "QueryType": "Keyword",
            "SearchTarget": "eBook" if content_type == "ebook" else "Book",
            "MaxResults": "10",
            "start": "1",
            "output": "js",
            "Version": "20131101",
        }
        data = await self._get(ALADIN_ITEM_SEARCH, params)
        return self._offers(
            data.get("item", []),
            matched_by=matched_by,
            content_type=content_type,
            expected_title=title,
            expected_author=author,
        )

    async def _get(self, url: str, params: dict[str, str]) -> dict:
        async with httpx.AsyncClient(timeout=self.timeout, follow_redirects=True) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()
        return data if isinstance(data, dict) else {}

    def _offers(
        self,
        items: list[dict],
        *,
        matched_by: str,
        content_type: str,
        expected_title: str = "",
        expected_author: str = "",
    ) -> list[Offer]:
        offers: list[Offer] = []
        for item in items:
            title = str(item.get("title") or "")
            author = str(item.get("author") or "")
            mall_type = str(item.get("mallType") or "").upper()
            if content_type == "ebook" and mall_type != "EBOOK":
                continue
            if content_type == "physical_book" and mall_type == "EBOOK":
                continue
            if not title or _blocked(title, content_type):
                continue
            if matched_by != "ISBN" and not _same_work(
                expected_title=expected_title,
                expected_author=expected_author,
                candidate_title=title,
                candidate_author=author,
            ):
                continue
            price = _to_int(item.get("priceSales"))
            original = _to_int(item.get("priceStandard"))
            url = str(item.get("link") or "")
            if not url:
                query = quote_plus(str(item.get("isbn13") or title))
                target = "eBook" if content_type == "ebook" else "Book"
                url = f"https://www.aladin.co.kr/search/wsearchresult.aspx?SearchTarget={target}&SearchWord={query}"
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
                    product_type="ebook" if content_type == "ebook" else "book",
                    content_type=content_type,
                    matched_by="high_confidence" if matched_by != "ISBN" else "exact",
                    message="가격, 재고, 배송비, 혜택은 결제 전 판매처에서 최종 확인해 주세요.",
                    category=str(item.get("categoryName") or ""),
                )
            )
        return offers[:3]


def _blocked(value: str, content_type: str) -> bool:
    lowered = value.lower()
    tokens = ["오디오북", "중고", "세트", "분철", "굿즈"]
    if content_type != "ebook":
        tokens.extend(["ebook", "전자책"])
    return any(token in lowered for token in tokens)


def _same_work(
    *,
    expected_title: str,
    expected_author: str,
    candidate_title: str,
    candidate_author: str,
) -> bool:
    expected = _normalize_title(expected_title)
    candidate = _normalize_title(candidate_title)
    if not expected or not candidate:
        return False
    title_match = (
        expected == candidate
        or expected in candidate
        or candidate in expected
        or SequenceMatcher(None, expected, candidate).ratio() >= 0.82
    )
    if not title_match:
        return False
    expected_author_key = _normalize_author(expected_author)
    if not expected_author_key:
        return True
    candidate_author_key = _normalize_author(candidate_author)
    return bool(candidate_author_key and expected_author_key in candidate_author_key)


def _normalize_title(value: str) -> str:
    text = unescape(re.sub(r"<[^>]+>", " ", value))
    text = re.sub(r"\([^)]*(ebook|전자책|종이책|paperback|양장|개정판)[^)]*\)", " ", text, flags=re.I)
    text = re.sub(r"\[[^\]]*(ebook|전자책|종이책|paperback)[^\]]*\]", " ", text, flags=re.I)
    text = re.sub(r"\b(e-?book|전자책|종이책|paperback)\b", " ", text, flags=re.I)
    text = re.sub(r"[^0-9a-zA-Z가-힣]+", "", text)
    return text.lower()


def _normalize_author(value: str) -> str:
    text = unescape(re.sub(r"<[^>]+>", " ", value))
    text = re.split(r"[,/;]| 지음| 저| 글| 옮김| 역", text)[0]
    text = re.sub(r"[^0-9a-zA-Z가-힣]+", "", text)
    return text.lower()


def _to_int(value) -> int | None:
    try:
        text = str(value or "").replace(",", "").strip()
        return int(text) if text else None
    except Exception:
        return None
