from datetime import datetime, timezone
from sqlalchemy import delete, select
from sqlalchemy.orm import Session
from ..config import get_settings
from ..models.db_models import BestsellerItem, SyncRun
from ..providers.bestseller.yes24 import Yes24BestsellerProvider
from ..providers.bestseller.aladin import AladinBestsellerProvider

STANDARD_CATEGORIES = ["종합", "소설·문학", "인문", "경제·경영", "자기계발", "과학", "역사", "사회", "어린이", "청소년", "에세이"]
YES24_CATEGORIES = ["종합"]
ALADIN_CATEGORIES = STANDARD_CATEGORIES


class BestsellerService:
    def __init__(self, db: Session):
        self.db = db
        self.settings = get_settings()

    def active_sources(self) -> list[str]:
        return self.settings.enabled_sources

    def categories(self) -> list[str]:
        return STANDARD_CATEGORIES

    def source_categories(self, source: str) -> list[str]:
        if source == "yes24":
            return YES24_CATEGORIES
        if source == "aladin":
            return ALADIN_CATEGORIES
        return []

    def list_items(self, source: str | None, category: str | None, page: int, page_size: int):
        page_size = min(max(page_size, 1), self.settings.max_page_size)
        stmt = select(BestsellerItem)
        if source:
            stmt = stmt.where(BestsellerItem.source == source)
        if category:
            stmt = stmt.where(BestsellerItem.category == category)
        stmt = stmt.order_by(BestsellerItem.source, BestsellerItem.category, BestsellerItem.ranking_date.desc(), BestsellerItem.rank).offset((page - 1) * page_size).limit(page_size)
        return list(self.db.scalars(stmt).all())

    def last_success_at(self, source: str | None = None):
        stmt = select(SyncRun).where(SyncRun.status == "success")
        if source:
            stmt = stmt.where(SyncRun.source == source)
        stmt = stmt.order_by(SyncRun.last_success_at.desc().nullslast())
        run = self.db.scalars(stmt).first()
        return run.last_success_at if run else None

    async def refresh(self, source: str | None = None) -> dict:
        sources = [source] if source else self.active_sources()
        result: dict[str, str | dict[str, str]] = {}
        for item_source in sources:
            categories = self.source_categories(item_source)
            if not categories:
                result[item_source] = "unsupported"
                continue
            category_result: dict[str, str] = {}
            for category in categories:
                limit = 50 if category == "종합" else 30
                try:
                    records = await self._provider(item_source).fetch(category=category, limit=limit)
                    if not records:
                        category_result[category] = "empty"
                        self._record_run(item_source, "failed", f"{category} 베스트셀러 결과가 비어 있습니다.")
                        continue
                    today = datetime.now(timezone.utc).date().isoformat()
                    self.db.execute(
                        delete(BestsellerItem).where(
                            BestsellerItem.source == item_source,
                            BestsellerItem.category == category,
                        )
                    )
                    for record in records:
                        self.db.add(
                            BestsellerItem(
                                source=record.source,
                                source_item_id=record.source_item_id,
                                category=record.category,
                                rank=record.rank,
                                previous_rank=record.previous_rank,
                                title=record.title,
                                author=record.author,
                                publisher=record.publisher,
                                publication_date=record.publication_date,
                                isbn10=record.isbn10,
                                isbn13=record.isbn13,
                                cover_url=record.cover_url,
                                source_product_url=record.source_product_url,
                                ranking_date=today,
                            )
                        )
                    self.db.commit()
                    category_result[category] = "success"
                except Exception:
                    self.db.rollback()
                    category_result[category] = "failed"
                    self._record_run(item_source, "failed", f"{category} 베스트셀러 갱신에 실패했습니다. 기존 데이터가 유지됩니다.")
                    self.db.commit()
            if any(status == "success" for status in category_result.values()):
                self._record_run(item_source, "success", "")
                self.db.commit()
            result[item_source] = category_result
        return result

    def _provider(self, source: str):
        if source == "yes24":
            return Yes24BestsellerProvider()
        if source == "aladin":
            return AladinBestsellerProvider(self.settings.aladin_ttb_key)
        raise ValueError("지원하지 않는 베스트셀러 소스입니다.")

    def _record_run(self, source: str, status: str, safe_message: str):
        self.db.add(SyncRun(source=source, status=status, last_success_at=datetime.now(timezone.utc) if status == "success" else None, last_attempt_at=datetime.now(timezone.utc), safe_message=safe_message))
