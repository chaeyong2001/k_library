import feedparser
import httpx
import logging
from .base import BestsellerProvider, BestsellerRecord

YES24_RSS = "https://www.yes24.com/24/category/bestsellerRss.aspx"
logger = logging.getLogger(__name__)


class Yes24BestsellerProvider(BestsellerProvider):
    source = "yes24"

    async def fetch(
        self,
        category: str = "종합",
        limit: int = 50,
        reader_target: str | None = None,
        content_type: str = "physical_book",
    ) -> list[BestsellerRecord]:
        if content_type != "physical_book":
            return []
        params = {"CategoryNumber": "001", "sumgb": "09"}
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            response = await client.get(
                YES24_RSS,
                params=params,
                headers={"User-Agent": "k-library/1.0 (+official-rss-check)"},
            )
            response.raise_for_status()
        content_type_header = response.headers.get("content-type", "")
        text = response.text
        prefix = text[:500].lower()
        looks_html = "<html" in prefix or "<!doctype html" in prefix
        looks_xml = text.lstrip("\ufeff").lstrip().startswith("<?xml") or "<rss" in prefix
        if looks_html or not looks_xml:
            logger.warning(
                "YES24 bestseller RSS returned non-RSS response: status=%s content_type=%s final_url=%s",
                response.status_code,
                content_type_header,
                response.url,
            )
            raise ValueError("YES24 bestseller RSS is not returning XML.")
        feed = feedparser.parse(text)
        if getattr(feed, "bozo", False):
            logger.warning(
                "YES24 bestseller RSS parse warning: %s",
                type(getattr(feed, "bozo_exception", None)).__name__,
            )
        if not feed.entries:
            raise ValueError("YES24 bestseller RSS returned no entries.")
        records: list[BestsellerRecord] = []
        for idx, entry in enumerate(feed.entries[:limit], start=1):
            records.append(
                BestsellerRecord(
                    source=self.source,
                    source_item_id=str(getattr(entry, "guid", "") or getattr(entry, "id", "") or getattr(entry, "link", "")),
                    content_type="physical_book",
                    category=category,
                    reader_target="미분류",
                    rank=idx,
                    title=str(getattr(entry, "title", "")).strip(),
                    author=str(getattr(entry, "author", "")).strip(),
                    publisher=str(getattr(entry, "publisher", "")).strip(),
                    publication_date=str(getattr(entry, "published", "")).strip(),
                    source_product_url=str(getattr(entry, "link", "")).strip(),
                )
            )
        return [r for r in records if r.title]
