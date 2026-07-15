from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import case, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db
from ..models.db_models import AnalyticsEvent
from ..schemas.analytics import AnalyticsBatchIn, AnalyticsBatchOut

router = APIRouter(prefix="/api/v1", tags=["analytics"])


@router.post("/analytics/events", response_model=AnalyticsBatchOut)
def collect_events(payload: AnalyticsBatchIn, db: Session = Depends(get_db)):
    if not payload.events:
        return AnalyticsBatchOut(accepted=0, duplicates=0)

    event_ids = [event.event_id for event in payload.events]
    existing = {
        row[0]
        for row in db.query(AnalyticsEvent.event_id)
        .filter(AnalyticsEvent.event_id.in_(event_ids))
        .all()
    }
    accepted = 0
    duplicates = 0
    for event in payload.events:
        if event.event_id in existing:
            duplicates += 1
            continue
        db.add(
            AnalyticsEvent(
                event_id=event.event_id,
                anonymous_install_id=event.anonymous_install_id,
                session_id=event.session_id,
                event_type=event.event_type,
                occurred_at=event.occurred_at,
                received_at=datetime.now(timezone.utc),
                app_version=event.app_version,
                platform=event.platform,
                entry_source=event.entry_source,
                content_type=event.content_type,
                provider=event.provider,
                isbn13=event.isbn13,
                isbn10=event.isbn10,
                source_item_id=event.source_item_id,
                title=event.title,
                author=event.author,
                displayed_price=event.displayed_price,
                original_price=event.original_price,
                was_lowest_price=event.was_lowest_price,
                selected_format=event.selected_format,
                source_screen=event.source_screen,
                destination_type=event.destination_type,
                event_metadata=_sanitize_metadata(event.metadata),
            )
        )
        existing.add(event.event_id)
        accepted += 1
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        accepted = 0
        duplicates = len(payload.events)
    return AnalyticsBatchOut(accepted=accepted, duplicates=duplicates)


@router.get("/admin/analytics/overview")
def admin_overview(
    range: str = Query(default="last_7_days"),
    start_date: str | None = None,
    end_date: str | None = None,
    x_admin_token: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    _require_admin(x_admin_token)
    start, end = _date_window(range, start_date, end_date)
    base = _filtered(db, start, end)
    by_event = _count_by(base, AnalyticsEvent.event_type)
    return {
        "range": {"start": start.isoformat(), "end": end.isoformat()},
        "total_events": base.count(),
        "unique_installs": base.with_entities(
            func.count(func.distinct(AnalyticsEvent.anonymous_install_id))
        ).scalar()
        or 0,
        "by_event_type": by_event,
        "by_content_type": _count_by(base, AnalyticsEvent.content_type),
        "by_entry_source": _count_by(base, AnalyticsEvent.entry_source),
    }


@router.get("/admin/analytics/providers")
def admin_providers(
    range: str = Query(default="last_7_days"),
    start_date: str | None = None,
    end_date: str | None = None,
    x_admin_token: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    _require_admin(x_admin_token)
    start, end = _date_window(range, start_date, end_date)
    base = _filtered(db, start, end).filter(
        AnalyticsEvent.event_type.in_(["outbound_store_click", "lowest_price_click"])
    )
    rows = (
        base.with_entities(
            AnalyticsEvent.provider,
            AnalyticsEvent.content_type,
            func.count(AnalyticsEvent.id),
        )
        .group_by(AnalyticsEvent.provider, AnalyticsEvent.content_type)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .all()
    )
    return {
        "range": {"start": start.isoformat(), "end": end.isoformat()},
        "providers": [
            {"provider": provider, "content_type": content_type, "clicks": count}
            for provider, content_type, count in rows
        ],
    }


@router.get("/admin/analytics/books")
def admin_books(
    range: str = Query(default="last_7_days"),
    start_date: str | None = None,
    end_date: str | None = None,
    limit: int = Query(default=30, ge=1, le=100),
    x_admin_token: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    _require_admin(x_admin_token)
    start, end = _date_window(range, start_date, end_date)
    key = func.coalesce(
        func.nullif(AnalyticsEvent.isbn13, ""),
        func.nullif(AnalyticsEvent.isbn10, ""),
        func.nullif(AnalyticsEvent.source_item_id, ""),
        AnalyticsEvent.title,
    )
    rows = (
        _filtered(db, start, end)
        .filter(AnalyticsEvent.title != "")
        .with_entities(
            key.label("book_key"),
            func.max(AnalyticsEvent.title),
            func.max(AnalyticsEvent.author),
            func.max(AnalyticsEvent.content_type),
            func.count(AnalyticsEvent.id),
            func.sum(
                case(
                    (
                        AnalyticsEvent.event_type.in_(
                            ["outbound_store_click", "lowest_price_click"]
                        ),
                        1,
                    ),
                    else_=0,
                )
            ),
        )
        .group_by(key)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .limit(limit)
        .all()
    )
    books = []
    for book_key, title, author, content_type, events, outbound_clicks in rows:
        books.append(
            {
                "book_key": book_key,
                "title": title,
                "author": author,
                "content_type": content_type,
                "events": events,
                "outbound_clicks": int(outbound_clicks or 0),
            }
        )
    return {"range": {"start": start.isoformat(), "end": end.isoformat()}, "books": books}


@router.get("/admin/analytics/funnel")
def admin_funnel(
    range: str = Query(default="last_7_days"),
    start_date: str | None = None,
    end_date: str | None = None,
    x_admin_token: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    _require_admin(x_admin_token)
    start, end = _date_window(range, start_date, end_date)
    base = _filtered(db, start, end)
    counts = _count_by(base, AnalyticsEvent.event_type)
    return {
        "range": {"start": start.isoformat(), "end": end.isoformat()},
        "steps": [
            {"event_type": "home_book_open", "events": counts.get("home_book_open", 0)},
            {"event_type": "bestseller_book_open", "events": counts.get("bestseller_book_open", 0)},
            {"event_type": "purchase_search_result_open", "events": counts.get("purchase_search_result_open", 0)},
            {"event_type": "purchase_detail_open", "events": counts.get("purchase_detail_open", 0)},
            {"event_type": "alternate_format_candidate_open", "events": counts.get("alternate_format_candidate_open", 0)},
            {
                "event_type": "outbound_store_click",
                "events": counts.get("outbound_store_click", 0)
                + counts.get("lowest_price_click", 0),
            },
        ],
        "note": "Counts represent detail entry and external store click behavior, not completed purchases.",
    }


def _require_admin(token: str | None) -> None:
    settings = get_settings()
    if not settings.admin_token or token != settings.admin_token:
        raise HTTPException(status_code=403, detail="Forbidden")


def _filtered(db: Session, start: datetime, end: datetime):
    return db.query(AnalyticsEvent).filter(
        AnalyticsEvent.occurred_at >= start,
        AnalyticsEvent.occurred_at < end,
    )


def _count_by(query, column) -> dict[str, int]:
    rows = (
        query.with_entities(column, func.count(AnalyticsEvent.id))
        .group_by(column)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .all()
    )
    return {str(name or "unknown"): count for name, count in rows}


def _sanitize_metadata(metadata: dict) -> dict:
    blocked = {"q", "query", "search", "search_text", "raw_search_text", "keyword"}
    return {key: value for key, value in metadata.items() if key not in blocked}


def _date_window(
    range_name: str,
    start_date: str | None,
    end_date: str | None,
) -> tuple[datetime, datetime]:
    if start_date:
        start = datetime.fromisoformat(start_date).replace(tzinfo=timezone.utc)
        end = (
            datetime.fromisoformat(end_date).replace(tzinfo=timezone.utc)
            if end_date
            else datetime.now(timezone.utc)
        )
        return start, end + timedelta(days=1)

    now = datetime.now(timezone.utc)
    today = datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
    if range_name == "today":
        return today, today + timedelta(days=1)
    if range_name == "yesterday":
        return today - timedelta(days=1), today
    if range_name == "last_30_days":
        return now - timedelta(days=30), now
    return now - timedelta(days=7), now
