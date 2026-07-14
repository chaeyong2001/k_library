from urllib.parse import quote_plus
from .base import Offer, ShoppingProvider


class Yes24LinkProvider(ShoppingProvider):
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
        query = _query(isbn13, isbn10, title, author)
        if not query:
            return []
        domain = "EBOOK" if content_type == "ebook" else "BOOK"
        return [
            Offer(
                provider="yes24",
                offer_type="external_link",
                merchant_name="YES24",
                product_name=title or query,
                isbn13=isbn13,
                price=None,
                original_price=None,
                total_price=None,
                product_url=f"https://www.yes24.com/Product/Search?domain={domain}&query={quote_plus(query)}",
                availability="판매처 확인",
                product_type="ebook" if content_type == "ebook" else "book",
                content_type=content_type,
                matched_by=_matched_by(isbn13, isbn10, title, author),
                message="가격은 판매처에서 확인",
            )
        ]


class KyoboLinkProvider(ShoppingProvider):
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
        query = _query(isbn13, isbn10, title, author)
        if not query:
            return []
        gb_code = "EBK" if content_type == "ebook" else "TOT"
        return [
            Offer(
                provider="kyobo",
                offer_type="external_link",
                merchant_name="교보문고",
                product_name=title or query,
                isbn13=isbn13,
                price=None,
                original_price=None,
                total_price=None,
                product_url=f"https://search.kyobobook.co.kr/search?keyword={quote_plus(query)}&gbCode={gb_code}",
                availability="판매처 확인",
                product_type="ebook" if content_type == "ebook" else "book",
                content_type=content_type,
                matched_by=_matched_by(isbn13, isbn10, title, author),
                message="가격은 판매처에서 확인",
            )
        ]


def _query(isbn13: str, isbn10: str, title: str, author: str) -> str:
    return isbn13.strip() or isbn10.strip() or " ".join(part for part in [title.strip(), author.strip()] if part).strip() or title.strip()


def _matched_by(isbn13: str, isbn10: str, title: str, author: str) -> str:
    if isbn13:
        return "ISBN-13"
    if isbn10:
        return "ISBN-10"
    if title and author:
        return "제목+저자"
    return "제목"
