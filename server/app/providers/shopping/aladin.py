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
        source_item_id: str = "",
    ) -> list[Offer]:
        if not self.ttb_key:
            return []
        if source_item_id:
            by_item_id = await self._lookup(
                source_item_id,
                item_id_type="ItemId",
                content_type=content_type,
            )
            if by_item_id:
                return by_item_id
        if isbn13 or isbn10:
            by_isbn = await self._lookup(
                isbn13 or isbn10,
                item_id_type="ISBN13" if isbn13 else "ISBN",
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

    async def _lookup(self, item_id: str, *, item_id_type: str, content_type: str) -> list[Offer]:
        params = {
            "ttbkey": self.ttb_key,
            "ItemId": item_id,
            "ItemIdType": item_id_type,
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

    async def format_candidates(
        self,
        *,
        title: str = "",
        author: str = "",
        publisher: str = "",
        content_type: str = "physical_book",
        limit: int = 10,
    ) -> list[dict]:
        if not self.ttb_key or not title.strip():
            return []
        queries = _candidate_queries(title, author)
        candidates: dict[str, dict] = {}
        for query in queries:
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
            for item in data.get("item", []):
                candidate = _candidate_from_item(
                    item,
                    expected_title=title,
                    expected_author=author,
                    expected_publisher=publisher,
                    content_type=content_type,
                )
                if candidate is None:
                    continue
                key = candidate["source_item_id"] or candidate["isbn13"] or candidate["product_url"]
                if key and (key not in candidates or candidate["match_score"] > candidates[key]["match_score"]):
                    candidates[key] = candidate
            if len(candidates) >= limit:
                break
        result = sorted(candidates.values(), key=lambda item: item["match_score"], reverse=True)
        return result[:limit]

    async def search_products(
        self,
        *,
        query: str = "",
        isbn13: str = "",
        isbn10: str = "",
        content_type: str = "physical_book",
        limit: int = 20,
    ) -> list[dict]:
        if not self.ttb_key:
            return []
        if isbn13 or isbn10:
            item_id = isbn13 or isbn10
            data = await self._get(
                ALADIN_ITEM_LOOKUP,
                {
                    "ttbkey": self.ttb_key,
                    "ItemId": item_id,
                    "ItemIdType": "ISBN13" if isbn13 else "ISBN",
                    "output": "js",
                    "Version": "20131101",
                },
            )
            items = data.get("item", [])
        else:
            if not query.strip():
                return []
            data = await self._get(
                ALADIN_ITEM_SEARCH,
                {
                    "ttbkey": self.ttb_key,
                    "Query": query.strip(),
                    "QueryType": "Keyword",
                    "SearchTarget": "eBook" if content_type == "ebook" else "Book",
                    "MaxResults": str(min(max(limit, 1), 50)),
                    "start": "1",
                    "output": "js",
                    "Version": "20131101",
                },
            )
            items = data.get("item", [])
        results: list[dict] = []
        for item in items:
            result = _search_result_from_item(item, query=query, content_type=content_type)
            if result is not None:
                results.append(result)
        results.sort(key=lambda item: item.get("match_score", 0), reverse=True)
        return _dedupe_search_results(results)[:limit]

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

_CANDIDATE_SUFFIX_TOKENS = [
    "특별판",
    "기념판",
    "개정판",
    "리커버",
    "양장본",
    "초판본",
    "한정판",
    "에디션",
    "합본",
    "세트",
    "박스 세트",
    "워크북",
    "별책",
    "부록",
    "보급판",
    "소장판",
]


def _candidate_queries(title: str, author: str) -> list[str]:
    compact = _compact_query_title(title)
    raw = title.strip()
    queries: list[str] = []
    for value in [" ".join(part for part in [raw, author.strip()] if part), " ".join(part for part in [compact, author.strip()] if part), compact]:
        value = " ".join(value.split())
        if value and value not in queries:
            queries.append(value)
    return queries


def _compact_query_title(value: str) -> str:
    text = value.strip()
    for delimiter in [" - ", " : ", " | "]:
        if delimiter in text:
            head, tail = text.split(delimiter, 1)
            if _looks_like_suffix(tail):
                text = head.strip()
                break
    text = re.sub(r"\s*[\(\[]([^\)\]]+)[\)\]]\s*", lambda match: " " if _looks_like_suffix(match.group(1)) else match.group(0), text)
    return " ".join(text.split()) or value.strip()


def _looks_like_suffix(value: str) -> bool:
    lowered = value.lower()
    return any(token.lower() in lowered for token in _CANDIDATE_SUFFIX_TOKENS)


def _candidate_from_item(
    item: dict,
    *,
    expected_title: str,
    expected_author: str,
    expected_publisher: str,
    content_type: str,
) -> dict | None:
    title = str(item.get("title") or "")
    author = str(item.get("author") or "")
    publisher = str(item.get("publisher") or "")
    mall_type = str(item.get("mallType") or "").upper()
    if content_type == "ebook" and mall_type != "EBOOK":
        return None
    if content_type == "physical_book" and mall_type == "EBOOK":
        return None
    if not title or _blocked(title, content_type):
        return None
    expected = _normalize_title(expected_title)
    compact_expected = _normalize_title(_compact_query_title(expected_title))
    candidate = _normalize_title(title)
    if not expected or not candidate:
        return None
    similarity = max(
        SequenceMatcher(None, expected, candidate).ratio(),
        SequenceMatcher(None, compact_expected, candidate).ratio() if compact_expected else 0,
    )
    containment = bool(compact_expected and (compact_expected in candidate or candidate in compact_expected))
    if similarity < 0.55 and not containment:
        return None
    reasons: list[str] = []
    score = similarity * 60
    if containment:
        score += 15
        reasons.append("제목 핵심어 일치")
    if expected == candidate or compact_expected == candidate:
        score += 20
        reasons.append("제목 정규화 일치")
    expected_author_key = _normalize_author(expected_author)
    candidate_author_key = _normalize_author(author)
    if expected_author_key and candidate_author_key:
        if expected_author_key in candidate_author_key:
            score += 15
            reasons.append("저자 일치")
        else:
            score -= 15
            reasons.append("저자 확인 필요")
    expected_publisher_key = _normalize_author(expected_publisher)
    candidate_publisher_key = _normalize_author(publisher)
    if expected_publisher_key and candidate_publisher_key and expected_publisher_key in candidate_publisher_key:
        score += 5
        reasons.append("출판사 일치")
    if item.get("cover"):
        score += 3
        reasons.append("표지 제공")
    if _to_int(item.get("priceSales")) is not None:
        score += 2
        reasons.append("가격 제공")
    return {
        "candidate_id": str(item.get("itemId") or item.get("isbn13") or item.get("link") or title),
        "content_type": content_type,
        "title": title,
        "author": author,
        "publisher": publisher,
        "isbn13": str(item.get("isbn13") or ""),
        "source_item_id": str(item.get("itemId") or ""),
        "cover_url": str(item.get("cover") or ""),
        "price": _to_int(item.get("priceSales")),
        "original_price": _to_int(item.get("priceStandard")),
        "product_url": str(item.get("link") or ""),
        "match_score": round(max(score, 0), 2),
        "match_reasons": reasons or ["후보 검색 결과"],
    }


def _search_result_from_item(item: dict, *, query: str, content_type: str) -> dict | None:
    title = str(item.get("title") or "")
    author = str(item.get("author") or "")
    mall_type = str(item.get("mallType") or "").upper()
    if content_type == "ebook" and mall_type != "EBOOK":
        return None
    if content_type == "physical_book" and mall_type == "EBOOK":
        return None
    if not title or _blocked(title, content_type):
        return None
    isbn13 = str(item.get("isbn13") or "")
    isbn10 = str(item.get("isbn") or "")
    normalized_query = _normalize_title(query)
    normalized_title = _normalize_title(title)
    normalized_author = _normalize_author(author)
    score = 0.0
    if isbn13 and query.replace("-", "").replace(" ", "") == isbn13:
        score += 120
    if isbn10 and query.replace("-", "").replace(" ", "") == isbn10:
        score += 120
    if normalized_query and normalized_title == normalized_query:
        score += 100
    elif normalized_query and normalized_title.startswith(normalized_query):
        score += 80
    elif normalized_query and normalized_query in normalized_title:
        score += 60
    if normalized_query and normalized_author and normalized_query in normalized_author:
        score += 30
    if item.get("cover"):
        score += 3
    if _to_int(item.get("priceSales")) is not None:
        score += 2
    return {
        "provider": "aladin",
        "content_type": content_type,
        "source_item_id": str(item.get("itemId") or ""),
        "title": title,
        "author": author,
        "publisher": str(item.get("publisher") or ""),
        "publication_date": str(item.get("pubDate") or ""),
        "isbn10": isbn10,
        "isbn13": isbn13,
        "cover_url": str(item.get("cover") or ""),
        "product_url": str(item.get("link") or ""),
        "price": _to_int(item.get("priceSales")),
        "original_price": _to_int(item.get("priceStandard")),
        "availability": "판매처 확인",
        "mall_type": mall_type,
        "match_score": round(score, 2),
    }


def _dedupe_search_results(items: list[dict]) -> list[dict]:
    unique: dict[str, dict] = {}
    for item in items:
        key = (
            item.get("source_item_id")
            or item.get("isbn13")
            or item.get("isbn10")
            or ":".join(
                [
                    _normalize_title(str(item.get("title") or "")),
                    _normalize_author(str(item.get("author") or "")),
                    _normalize_author(str(item.get("publisher") or "")),
                    str(item.get("content_type") or ""),
                ]
            )
        )
        if key and key not in unique:
            unique[key] = item
    return list(unique.values())

def _to_int(value) -> int | None:
    try:
        text = str(value or "").replace(",", "").strip()
        return int(text) if text else None
    except Exception:
        return None


