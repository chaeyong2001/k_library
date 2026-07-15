from datetime import datetime, timezone
from sqlalchemy import Boolean, DateTime, Integer, String, Text, UniqueConstraint, Index
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.types import JSON
from sqlalchemy.orm import Mapped, mapped_column
from ..database import Base


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


class BestsellerItem(Base):
    __tablename__ = "kl_bestseller_items"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    source: Mapped[str] = mapped_column(String(32), index=True)
    source_item_id: Mapped[str] = mapped_column(String(160), default="")
    content_type: Mapped[str] = mapped_column(String(40), index=True, default="physical_book")
    category: Mapped[str] = mapped_column(String(80), index=True, default="종합")
    reader_target: Mapped[str] = mapped_column(String(40), index=True, default="미분류")
    rank: Mapped[int] = mapped_column(Integer, index=True)
    previous_rank: Mapped[int | None] = mapped_column(Integer, nullable=True)
    title: Mapped[str] = mapped_column(String(300))
    author: Mapped[str] = mapped_column(String(240), default="")
    publisher: Mapped[str] = mapped_column(String(180), default="")
    publication_date: Mapped[str] = mapped_column(String(40), default="")
    isbn10: Mapped[str] = mapped_column(String(20), default="")
    isbn13: Mapped[str] = mapped_column(String(20), index=True, default="")
    cover_url: Mapped[str] = mapped_column(Text, default="")
    source_product_url: Mapped[str] = mapped_column(Text, default="")
    ranking_date: Mapped[str] = mapped_column(String(20), index=True)
    collected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)

    __table_args__ = (
        UniqueConstraint("source", "content_type", "category", "reader_target", "ranking_date", "rank", name="uq_kl_best_rank"),
        Index("ix_kl_best_source_content_category_reader_rank", "source", "content_type", "category", "reader_target", "ranking_date", "rank"),
    )


class SyncRun(Base):
    __tablename__ = "kl_sync_runs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    source: Mapped[str] = mapped_column(String(60), index=True)
    content_type: Mapped[str] = mapped_column(String(40), index=True, default="physical_book")
    status: Mapped[str] = mapped_column(String(30), default="pending")
    last_success_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)
    safe_message: Mapped[str] = mapped_column(String(400), default="")


class PurchaseOfferCache(Base):
    __tablename__ = "kl_purchase_offer_cache"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    cache_key: Mapped[str] = mapped_column(String(240), unique=True, index=True)
    query_type: Mapped[str] = mapped_column(String(40))
    normalized_query: Mapped[str] = mapped_column(String(240), index=True)
    payload_json: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    last_success_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    stale: Mapped[bool] = mapped_column(Boolean, default=False)


class AnalyticsEvent(Base):
    __tablename__ = "kl_analytics_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    event_id: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    anonymous_install_id: Mapped[str] = mapped_column(String(80), index=True)
    session_id: Mapped[str] = mapped_column(String(80), index=True)
    event_type: Mapped[str] = mapped_column(String(60), index=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc, index=True)
    app_version: Mapped[str] = mapped_column(String(40), default="")
    platform: Mapped[str] = mapped_column(String(40), default="")
    entry_source: Mapped[str] = mapped_column(String(80), default="")
    content_type: Mapped[str] = mapped_column(String(40), default="physical_book", index=True)
    provider: Mapped[str] = mapped_column(String(40), default="unknown", index=True)
    isbn13: Mapped[str] = mapped_column(String(20), default="")
    isbn10: Mapped[str] = mapped_column(String(20), default="")
    source_item_id: Mapped[str] = mapped_column(String(160), default="")
    title: Mapped[str] = mapped_column(String(300), default="")
    author: Mapped[str] = mapped_column(String(240), default="")
    displayed_price: Mapped[int | None] = mapped_column(Integer, nullable=True)
    original_price: Mapped[int | None] = mapped_column(Integer, nullable=True)
    was_lowest_price: Mapped[bool] = mapped_column(Boolean, default=False)
    selected_format: Mapped[str] = mapped_column(String(40), default="")
    source_screen: Mapped[str] = mapped_column(String(80), default="")
    destination_type: Mapped[str] = mapped_column(String(80), default="")
    event_metadata: Mapped[dict] = mapped_column("metadata", JSON().with_variant(JSONB, "postgresql"), default=dict)

    __table_args__ = (
        Index("ix_kl_analytics_event_type_occurred", "event_type", "occurred_at"),
        Index("ix_kl_analytics_provider_content", "provider", "content_type"),
    )
