from dataclasses import dataclass, field
from datetime import datetime, timezone


@dataclass
class Offer:
    provider: str
    merchant_name: str
    product_name: str
    isbn13: str = ""
    offer_type: str = "priced_offer"
    source_type: str = "priced"
    display_name: str = ""
    description: str = ""
    action_label: str = ""
    price: int | None = None
    original_price: int | None = None
    shipping_fee: int | None = None
    total_price: int | None = None
    product_url: str = ""
    image_url: str = ""
    availability: str = "확인 필요"
    product_type: str = "book"
    content_type: str = "physical_book"
    matched_by: str = "매칭 확인 필요"
    message: str = ""
    category: str = ""
    fetched_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


class ShoppingProvider:
    async def search(
        self,
        *,
        isbn13: str = "",
        isbn10: str = "",
        title: str = "",
        author: str = "",
        content_type: str = "physical_book",
    ) -> list[Offer]:
        raise NotImplementedError
