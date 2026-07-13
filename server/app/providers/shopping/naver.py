import httpx
from .base import Offer, ShoppingProvider

class NaverApiHubShoppingProvider(ShoppingProvider):
    def __init__(self, *, endpoint: str, client_id: str = "", client_secret: str = "", api_key: str = ""):
        self.endpoint = endpoint
        self.client_id = client_id
        self.client_secret = client_secret
        self.api_key = api_key

    async def search(self, *, isbn13: str = "", isbn10: str = "", title: str = "", author: str = "") -> list[Offer]:
        if not self.endpoint:
            raise RuntimeError("NAVER API HUB 쇼핑 엔드포인트가 설정되지 않았습니다.")
        query = isbn13 or isbn10 or " ".join(part for part in [title, author] if part).strip()
        if not query:
            return []
        headers: dict[str, str] = {}
        if self.api_key:
            headers["X-API-KEY"] = self.api_key
        if self.client_id:
            headers["X-Naver-Client-Id"] = self.client_id
        if self.client_secret:
            headers["X-Naver-Client-Secret"] = self.client_secret
        async with httpx.AsyncClient(timeout=12.0) as client:
            response = await client.get(self.endpoint, params={"query": query, "display": 20}, headers=headers)
            response.raise_for_status()
            data = response.json()
        items = data.get("items", []) if isinstance(data, dict) else []
        offers: list[Offer] = []
        for item in items:
            title_text = str(item.get("title") or item.get("productName") or "").replace("<b>", "").replace("</b>", "")
            mall = str(item.get("mallName") or item.get("merchant") or "")
            price = _to_int(item.get("lprice") or item.get("price"))
            url = str(item.get("link") or item.get("url") or "")
            image = str(item.get("image") or item.get("imageUrl") or "")
            offers.append(Offer(provider="naver_api_hub", merchant_name=mall, product_name=title_text, isbn13=isbn13, price=price, total_price=price, product_url=url, image_url=image, matched_by="검색어"))
        return offers

def _to_int(value) -> int | None:
    try:
        return int(str(value).replace(",", ""))
    except Exception:
        return None
