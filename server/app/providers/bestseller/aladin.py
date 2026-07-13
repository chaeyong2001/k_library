import httpx
from .base import BestsellerProvider, BestsellerRecord

ALADIN_ITEM_LIST = "http://www.aladin.co.kr/ttb/api/ItemList.aspx"

class AladinBestsellerProvider(BestsellerProvider):
    source = "aladin"

    def __init__(self, ttb_key: str):
        self.ttb_key = ttb_key

    async def fetch(self, category: str = "종합", limit: int = 50) -> list[BestsellerRecord]:
        if not self.ttb_key:
            return []
        params = {
            "ttbkey": self.ttb_key,
            "QueryType": "Bestseller",
            "MaxResults": str(min(limit, 50)),
            "start": "1",
            "SearchTarget": "Book",
            "output": "js",
            "Version": "20131101",
        }
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            response = await client.get(ALADIN_ITEM_LIST, params=params)
            response.raise_for_status()
            data = response.json()
        records: list[BestsellerRecord] = []
        for idx, item in enumerate(data.get("item", [])[:limit], start=1):
            records.append(BestsellerRecord(
                source=self.source,
                source_item_id=str(item.get("itemId", "")),
                category=category,
                rank=idx,
                title=str(item.get("title", "")),
                author=str(item.get("author", "")),
                publisher=str(item.get("publisher", "")),
                publication_date=str(item.get("pubDate", "")),
                isbn10=str(item.get("isbn", "")),
                isbn13=str(item.get("isbn13", "")),
                cover_url=str(item.get("cover", "")),
                source_product_url=str(item.get("link", "")),
            ))
        return [r for r in records if r.title]
