from dataclasses import dataclass
from datetime import datetime, timezone

@dataclass
class Offer:
    provider: str
    merchant_name: str
    product_name: str
    isbn13: str = ""
    price: int | None = None
    original_price: int | None = None
    shipping_fee: int | None = None
    total_price: int | None = None
    product_url: str = ""
    image_url: str = ""
    availability: str = "확인 필요"
    product_type: str = "book"
    matched_by: str = "매칭 확인 필요"
    fetched_at: datetime = datetime.now(timezone.utc)

class ShoppingProvider:
    async def search(self, *, isbn13: str = "", isbn10: str = "", title: str = "", author: str = "") -> list[Offer]:
        raise NotImplementedError
