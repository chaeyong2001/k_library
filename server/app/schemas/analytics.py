from datetime import datetime, timezone
import json
from typing import Any

from pydantic import BaseModel, Field, field_validator


ALLOWED_EVENT_TYPES = {
    "home_book_open",
    "library_search_result_open",
    "purchase_search_result_open",
    "bestseller_book_open",
    "purchase_detail_open",
    "format_tab_change",
    "alternate_format_candidate_open",
    "outbound_store_click",
    "lowest_price_click",
    "library_save",
    "library_remove",
}

ALLOWED_CONTENT_TYPES = {"physical_book", "ebook", "audiobook", ""}
ALLOWED_PROVIDERS = {"aladin", "yes24", "kyobo", "naver", "unknown", ""}
MAX_BATCH_SIZE = 50
MAX_METADATA_CHARS = 4096


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


class AnalyticsEventIn(BaseModel):
    event_id: str = Field(min_length=8, max_length=80)
    anonymous_install_id: str = Field(min_length=8, max_length=80)
    session_id: str = Field(min_length=8, max_length=80)
    event_type: str
    occurred_at: datetime = Field(default_factory=now_utc)
    app_version: str = Field(default="", max_length=40)
    platform: str = Field(default="", max_length=40)
    entry_source: str = Field(default="", max_length=80)
    content_type: str = Field(default="physical_book", max_length=40)
    provider: str = Field(default="unknown", max_length=40)
    isbn13: str = Field(default="", max_length=20)
    isbn10: str = Field(default="", max_length=20)
    source_item_id: str = Field(default="", max_length=160)
    title: str = Field(default="", max_length=300)
    author: str = Field(default="", max_length=240)
    displayed_price: int | None = None
    original_price: int | None = None
    was_lowest_price: bool = False
    selected_format: str = Field(default="", max_length=40)
    source_screen: str = Field(default="", max_length=80)
    destination_type: str = Field(default="", max_length=80)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("event_type")
    @classmethod
    def validate_event_type(cls, value: str) -> str:
        if value not in ALLOWED_EVENT_TYPES:
            raise ValueError("unsupported event_type")
        return value

    @field_validator("content_type")
    @classmethod
    def validate_content_type(cls, value: str) -> str:
        if value not in ALLOWED_CONTENT_TYPES:
            raise ValueError("unsupported content_type")
        return value or "physical_book"

    @field_validator("provider")
    @classmethod
    def validate_provider(cls, value: str) -> str:
        if value not in ALLOWED_PROVIDERS:
            return "unknown"
        return value or "unknown"

    @field_validator("displayed_price", "original_price")
    @classmethod
    def validate_price(cls, value: int | None) -> int | None:
        if value is not None and value < 0:
            raise ValueError("price must be non-negative")
        return value

    @field_validator("metadata")
    @classmethod
    def validate_metadata(cls, value: dict[str, Any]) -> dict[str, Any]:
        encoded = json.dumps(value, ensure_ascii=False, default=str)
        if len(encoded) > MAX_METADATA_CHARS:
            raise ValueError("metadata is too large")
        return value


class AnalyticsBatchIn(BaseModel):
    events: list[AnalyticsEventIn] = Field(default_factory=list, max_length=MAX_BATCH_SIZE)


class AnalyticsBatchOut(BaseModel):
    accepted: int
    duplicates: int

