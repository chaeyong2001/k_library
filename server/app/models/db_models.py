from datetime import datetime, timezone
from sqlalchemy import Boolean, DateTime, Integer, String, Text, UniqueConstraint, Index
from sqlalchemy.orm import Mapped, mapped_column
from ..database import Base

def now_utc() -> datetime:
    return datetime.now(timezone.utc)

class BestsellerItem(Base):
    __tablename__ = "kl_bestseller_items"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    source: Mapped[str] = mapped_column(String(32), index=True)
    source_item_id: Mapped[str] = mapped_column(String(160), default="")
    category: Mapped[str] = mapped_column(String(80), index=True, default="종합")
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
        UniqueConstraint("source", "category", "ranking_date", "rank", name="uq_kl_best_rank"),
        Index("ix_kl_best_source_category_rank", "source", "category", "ranking_date", "rank"),
    )

class SyncRun(Base):
    __tablename__ = "kl_sync_runs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    source: Mapped[str] = mapped_column(String(60), index=True)
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
