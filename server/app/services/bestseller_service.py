from datetime import datetime, timezone
from sqlalchemy import delete, select
from sqlalchemy.orm import Session
from ..config import get_settings
from ..models.db_models import BestsellerItem, SyncRun
from ..providers.bestseller.yes24 import Yes24BestsellerProvider
from ..providers.bestseller.aladin import AladinBestsellerProvider

GENRE_CATEGORIES = ["종합", "소설·문학", "인문", "경제·경영", "자기계발", "과학", "역사", "사회", "에세이"]
READER_TARGETS = ["유아", "어린이", "청소년", "성인"]
YES24_CATEGORIES = ["종합"]
YES24_READER_TARGETS: list[str] = []
ALADIN_CATEGORIES = GENRE_CATEGORIES
ALADIN_READER_TARGETS = READER_TARGETS
CONTENT_TYPES = ["physical_book", "ebook"]
ALADIN_EBOOK_CATEGORIES = GENRE_CATEGORIES


class BestsellerService:
    def __init__(self, db: Session):
        self.db = db
        self.settings = get_settings()

    def active_sources(self, content_type: str = "physical_book") -> list[str]:
        if content_type == "ebook":
            return ["aladin"] if self.settings.enable_aladin_bestseller else []
        return self.settings.enabled_sources

    def categories(self, source: str | None = None, content_type: str = "physical_book") -> list[str]:
        if source:
            return self.source_categories(source, content_type)
        if content_type == "ebook":
            return ALADIN_EBOOK_CATEGORIES
        return GENRE_CATEGORIES

    def reader_targets(self) -> list[str]:
        return READER_TARGETS

    def source_categories(self, source: str, content_type: str = "physical_book") -> list[str]:
        if content_type == "ebook":
            return ALADIN_EBOOK_CATEGORIES if source == "aladin" else []
        if source == "yes24":
            return YES24_CATEGORIES
        if source == "aladin":
            return ALADIN_CATEGORIES
        return []

    def source_reader_targets(self, source: str, content_type: str = "physical_book") -> list[str]:
        if content_type == "ebook":
            return []
        if source == "yes24":
            return YES24_READER_TARGETS
        if source == "aladin":
            return ALADIN_READER_TARGETS
        return []

    def list_items(
        self,
        source: str | None,
        content_type: str,
        category: str | None,
        reader_target: str | None,
        page: int,
        page_size: int,
    ):
        page_size = min(max(page_size, 1), self.settings.max_page_size)
        category = (category or "").strip()
        reader_target = (reader_target or "").strip()
        if category == "전체":
            category = ""
        if reader_target == "전체":
            reader_target = ""

        stmt = select(BestsellerItem)
        if source:
            stmt = stmt.where(BestsellerItem.source == source)
        else:
            active = self.active_sources(content_type)
            if not active:
                return []
            stmt = stmt.where(BestsellerItem.source.in_(active))
        stmt = stmt.where(BestsellerItem.content_type == content_type)

        if content_type == "physical_book":
            if reader_target:
                stmt = stmt.where(BestsellerItem.reader_target == reader_target)
                if reader_target == "성인":
                    stmt = stmt.where(BestsellerItem.category == (category or "종합"))
            else:
                stmt = stmt.where(BestsellerItem.reader_target == "성인")
                stmt = stmt.where(BestsellerItem.category == (category or "종합"))
        else:
            stmt = stmt.where(BestsellerItem.category == (category or "종합"))

        if content_type == "physical_book" and reader_target:
            stmt = stmt.order_by(
                BestsellerItem.source,
                BestsellerItem.content_type,
                BestsellerItem.reader_target,
                BestsellerItem.ranking_date.desc(),
                BestsellerItem.rank,
            )
        else:
            stmt = stmt.order_by(
                BestsellerItem.source,
                BestsellerItem.content_type,
                BestsellerItem.category,
                BestsellerItem.ranking_date.desc(),
                BestsellerItem.rank,
            )
        return list(self.db.scalars(stmt.offset((page - 1) * page_size).limit(page_size)).all())

    def last_success_at(self, source: str | None = None, content_type: str = "physical_book"):
        stmt = select(SyncRun).where(SyncRun.status == "success")
        if source:
            stmt = stmt.where(SyncRun.source == source)
        stmt = stmt.where(SyncRun.content_type == content_type)
        stmt = stmt.order_by(SyncRun.last_success_at.desc().nullslast())
        run = self.db.scalars(stmt).first()
        return run.last_success_at if run else None

    async def refresh(self, source: str | None = None, content_type: str | None = None) -> dict:
        content_types = [content_type] if content_type else CONTENT_TYPES
        result: dict[str, str | dict[str, str]] = {}
        for item_content_type in content_types:
            active = self.active_sources(item_content_type)
            if source and source not in active:
                result[f"{source}:{item_content_type}"] = "skipped"
                continue
            sources = [source] if source else active
            for item_source in sources:
                key = f"{item_source}:{item_content_type}"
                plans = self._refresh_plans(item_source, item_content_type)
                if not plans:
                    result[key] = "unsupported"
                    continue
                category_result: dict[str, str] = {}
                for plan in plans:
                    category = plan["category"]
                    reader_target = plan["reader_target"]
                    label = plan["label"]
                    limit = plan["limit"]
                    try:
                        records = await self._provider(item_source).fetch(category=category, reader_target=reader_target, limit=limit, content_type=item_content_type)
                        if not records:
                            category_result[label] = "empty"
                            self._record_run(item_source, item_content_type, "failed", f"{label} 베스트셀러 결과가 비어 있습니다.")
                            continue
                        today = datetime.now(timezone.utc).date().isoformat()
                        self.db.execute(self._delete_stmt(item_source, item_content_type, category, reader_target))
                        for record in records:
                            self.db.add(
                                BestsellerItem(
                                    source=record.source,
                                    source_item_id=record.source_item_id,
                                    content_type=record.content_type,
                                    category=record.category,
                                    reader_target=record.reader_target,
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
                        category_result[label] = "success"
                    except Exception:
                        self.db.rollback()
                        category_result[label] = "failed"
                        self._record_run(item_source, item_content_type, "failed", f"{label} 베스트셀러 갱신에 실패했습니다. 기존 데이터가 유지됩니다.")
                        self.db.commit()
                if any(status == "success" for status in category_result.values()):
                    self._record_run(item_source, item_content_type, "success", "")
                    self.db.commit()
                result[key] = category_result
        return result

    def _refresh_plans(self, source: str, content_type: str) -> list[dict]:
        if content_type == "ebook":
            if source != "aladin":
                return []
            return [
                {
                    "category": category,
                    "reader_target": None,
                    "label": f"전자책/{category}",
                    "limit": 50 if category == "종합" else 30,
                }
                for category in ALADIN_EBOOK_CATEGORIES
            ]
        if source == "yes24":
            return [{"category": "종합", "reader_target": None, "label": "종합", "limit": 50}]
        if source == "aladin":
            plans = [
                {
                    "category": category,
                    "reader_target": None,
                    "label": category,
                    "limit": 50 if category == "종합" else 30,
                }
                for category in ALADIN_CATEGORIES
            ]
            plans.extend(
                {
                    "category": "종합",
                    "reader_target": target,
                    "label": f"독자 대상/{target}",
                    "limit": 30,
                }
                for target in ["유아", "어린이", "청소년"]
            )
            return plans
        return []

    def _delete_stmt(self, source: str, content_type: str, category: str, reader_target: str | None):
        stmt = delete(BestsellerItem).where(BestsellerItem.source == source, BestsellerItem.content_type == content_type)
        if reader_target:
            return stmt.where(BestsellerItem.reader_target == reader_target)
        if content_type == "ebook":
            return stmt.where(BestsellerItem.category == category)
        return stmt.where(BestsellerItem.category == category, BestsellerItem.reader_target == "성인")

    def _provider(self, source: str):
        if source == "yes24":
            return Yes24BestsellerProvider()
        if source == "aladin":
            return AladinBestsellerProvider(self.settings.aladin_ttb_key)
        raise ValueError("지원하지 않는 베스트셀러 소스입니다.")

    def _record_run(self, source: str, content_type: str, status: str, safe_message: str):
        self.db.add(SyncRun(source=source, content_type=content_type, status=status, last_success_at=datetime.now(timezone.utc) if status == "success" else None, last_attempt_at=datetime.now(timezone.utc), safe_message=safe_message))
