import httpx
from .base import BestsellerProvider, BestsellerRecord

ALADIN_ITEM_LIST = "http://www.aladin.co.kr/ttb/api/ItemList.aspx"

# Aladin domestic book category ids used by the Open API CategoryId parameter.
# Keep "종합" as the all-books bestseller request without CategoryId.
ALADIN_CATEGORY_IDS: dict[str, int | None] = {
    "종합": None,
    "소설·문학": 1,
    "인문": 656,
    "경제·경영": 170,
    "자기계발": 336,
    "과학": 987,
    "역사": 74,
    "사회": 798,
    "에세이": 55890,
}

# Aladin eBook category ids confirmed from official Aladin category pages.
ALADIN_EBOOK_CATEGORY_IDS: dict[str, int | None] = {
    "종합": None,
    "소설·문학": 90842,
    "인문": 38403,
    "경제·경영": 90835,
    "자기계발": 38400,
    "과학": 38405,
    "역사": 38397,
    "사회": 38404,
    "에세이": 55889,
}

# Official Aladin top-level audience category ids confirmed from Aladin category pages.
ALADIN_READER_TARGET_CATEGORY_IDS: dict[str, int] = {
    "유아": 13789,
    "어린이": 1108,
    "청소년": 1137,
}


class AladinBestsellerProvider(BestsellerProvider):
    source = "aladin"

    def __init__(self, ttb_key: str):
        self.ttb_key = ttb_key

    async def fetch(
        self,
        category: str = "종합",
        limit: int = 50,
        reader_target: str | None = None,
        content_type: str = "physical_book",
    ) -> list[BestsellerRecord]:
        if not self.ttb_key:
            return []
        ebook = content_type == "ebook"
        params = {
            "ttbkey": self.ttb_key,
            "QueryType": "Bestseller",
            "MaxResults": str(min(limit, 50)),
            "start": "1",
            "SearchTarget": "eBook" if ebook else "Book",
            "output": "js",
            "Version": "20131101",
        }
        if ebook:
            category_id = ALADIN_EBOOK_CATEGORY_IDS.get(category)
            if category_id is not None:
                params["CategoryId"] = str(category_id)
        elif reader_target in ALADIN_READER_TARGET_CATEGORY_IDS:
            params["CategoryId"] = str(ALADIN_READER_TARGET_CATEGORY_IDS[reader_target])
        else:
            category_id = ALADIN_CATEGORY_IDS.get(category)
            if category_id is not None:
                params["CategoryId"] = str(category_id)
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            response = await client.get(ALADIN_ITEM_LIST, params=params)
            response.raise_for_status()
            data = response.json()
        records: list[BestsellerRecord] = []
        for idx, item in enumerate(data.get("item", [])[:limit], start=1):
            if ebook and str(item.get("mallType") or "").upper() != "EBOOK":
                continue
            category_name = str(item.get("categoryName") or "")
            records.append(
                BestsellerRecord(
                    source=self.source,
                    source_item_id=str(item.get("itemId", "")),
                    category=_genre_from_aladin_category(category_name, category, None if ebook else reader_target),
                    content_type=content_type,
                    reader_target="미분류" if ebook else reader_target or "성인",
                    rank=idx,
                    title=str(item.get("title", "")),
                    author=str(item.get("author", "")),
                    publisher=str(item.get("publisher", "")),
                    publication_date=str(item.get("pubDate", "")),
                    isbn10=str(item.get("isbn", "")),
                    isbn13=str(item.get("isbn13", "")),
                    cover_url=str(item.get("cover", "")),
                    source_product_url=str(item.get("link", "")),
                )
            )
        return [r for r in records if r.title]


def _genre_from_aladin_category(category_name: str, fallback: str, reader_target: str | None) -> str:
    if not reader_target:
        return fallback
    if "소설" in category_name or "문학" in category_name or "동화" in category_name:
        return "소설·문학"
    if "경제" in category_name or "경영" in category_name:
        return "경제·경영"
    if "자기계발" in category_name:
        return "자기계발"
    if "과학" in category_name or "수학" in category_name:
        return "과학"
    if "역사" in category_name:
        return "역사"
    if "사회" in category_name:
        return "사회"
    if "인문" in category_name or "철학" in category_name:
        return "인문"
    if "에세이" in category_name:
        return "에세이"
    return "종합"
