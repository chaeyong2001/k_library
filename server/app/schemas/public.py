from datetime import datetime
from pydantic import BaseModel


class BestsellerItemOut(BaseModel):
    source: str
    source_item_id: str = ""
    content_type: str = "physical_book"
    category: str
    reader_target: str = "미분류"
    rank: int
    previous_rank: int | None = None
    title: str
    author: str = ""
    publisher: str = ""
    publication_date: str = ""
    isbn10: str = ""
    isbn13: str = ""
    cover_url: str = ""
    source_product_url: str = ""
    collected_at: datetime
    ranking_date: str


class BestsellerResponse(BaseModel):
    active_sources: list[str]
    selected_source: str | None
    content_type: str = "physical_book"
    category: str | None
    reader_target: str | None = None
    items: list[BestsellerItemOut]
    last_success_at: datetime | None = None
    cached: bool = True
    safe_message: str = ""


class OfferOut(BaseModel):
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
    fetched_at: datetime


class OfferResponse(BaseModel):
    query: dict
    offers: list[OfferOut]
    cached: bool = False
    stale: bool = False
    safe_message: str = ""


class FormatCandidateOut(BaseModel):
    candidate_id: str
    content_type: str
    title: str
    author: str = ""
    publisher: str = ""
    isbn13: str = ""
    source_item_id: str = ""
    cover_url: str = ""
    price: int | None = None
    original_price: int | None = None
    product_url: str = ""
    match_score: float = 0
    match_reasons: list[str] = []


class FormatCandidateResponse(BaseModel):
    query_title: str = ""
    normalized_title: str = ""
    target_content_type: str = "physical_book"
    candidates: list[FormatCandidateOut] = []
    safe_message: str = ""


class SourceOut(BaseModel):
    source: str
    label: str
    enabled: bool
    categories: list[str] = []
    reader_targets: list[str] = []
