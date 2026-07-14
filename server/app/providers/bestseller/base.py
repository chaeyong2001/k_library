from dataclasses import dataclass


@dataclass
class BestsellerRecord:
    source: str
    source_item_id: str
    category: str
    rank: int
    content_type: str = "physical_book"
    reader_target: str = "미분류"
    title: str = ""
    author: str = ""
    publisher: str = ""
    publication_date: str = ""
    isbn10: str = ""
    isbn13: str = ""
    cover_url: str = ""
    source_product_url: str = ""
    previous_rank: int | None = None


class BestsellerProvider:
    source: str

    async def fetch(
        self,
        category: str = "종합",
        limit: int = 50,
        reader_target: str | None = None,
        content_type: str = "physical_book",
    ) -> list[BestsellerRecord]:
        raise NotImplementedError
