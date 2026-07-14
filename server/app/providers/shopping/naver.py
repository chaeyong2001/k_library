from .base import Offer, ShoppingProvider


class NaverApiHubShoppingProvider(ShoppingProvider):
    """Reserved placeholder.

    NAVER API HUB currently available Shopping Insight API is not a product
    search or merchant-price API, so this provider intentionally performs no
    network calls. Keep the class name as an extension point for a future
    official shopping/price API.
    """

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
        return []
