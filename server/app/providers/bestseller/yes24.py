from datetime import datetime
import feedparser
import httpx
from .base import BestsellerProvider, BestsellerRecord

YES24_RSS = "https://www.yes24.com/24/category/bestsellerRss.aspx"


class Yes24BestsellerProvider(BestsellerProvider):
    source = "yes24"

    async def fetch(
        self,
        category: str = "종합",
        limit: int = 50,
        reader_target: str | None = None,
    ) -> list[BestsellerRecord]:
        params = {"CategoryNumber": "001", "sumgb": "09"}
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            response = await client.get(YES24_RSS, params=params)
            response.raise_for_status()
        feed = feedparser.parse(response.text)
        records: list[BestsellerRecord] = []
        for idx, entry in enumerate(feed.entries[:limit], start=1):
            records.append(
                BestsellerRecord(
                    source=self.source,
                    source_item_id=str(getattr(entry, "guid", "") or getattr(entry, "id", "") or getattr(entry, "link", "")),
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
