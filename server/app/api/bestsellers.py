from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy.orm import Session
from ..config import get_settings
from ..database import get_db
from ..schemas.public import BestsellerItemOut, BestsellerResponse, SourceOut
from ..services.bestseller_service import BestsellerService

router = APIRouter(prefix="/api/v1/bestsellers", tags=["bestsellers"])


@router.get("/sources", response_model=list[SourceOut])
def sources(content_type: str = "physical_book", db: Session = Depends(get_db)):
    service = BestsellerService(db)
    active = set(service.active_sources(content_type))
    entries = [
        SourceOut(source="yes24", label="YES24 기준", enabled="yes24" in active, categories=service.source_categories("yes24", content_type), reader_targets=service.source_reader_targets("yes24", content_type)),
        SourceOut(source="aladin", label="알라딘 기준", enabled="aladin" in active, categories=service.source_categories("aladin", content_type), reader_targets=service.source_reader_targets("aladin", content_type)),
    ]
    return [entry for entry in entries if entry.enabled]


@router.get("/categories", response_model=list[str])
def categories(source: str | None = None, content_type: str = "physical_book", db: Session = Depends(get_db)):
    return BestsellerService(db).categories(source=source, content_type=content_type)


@router.get("/reader-targets", response_model=list[str])
def reader_targets(db: Session = Depends(get_db)):
    return BestsellerService(db).reader_targets()


@router.get("", response_model=BestsellerResponse)
def list_bestsellers(
    source: str | None = Query(default=None),
    content_type: str = Query(default="physical_book"),
    category: str | None = Query(default=None),
    reader_target: str | None = Query(default=None),
    page: int = 1,
    page_size: int = 30,
    db: Session = Depends(get_db),
):
    service = BestsellerService(db)
    if source and source not in service.active_sources(content_type):
        return BestsellerResponse(active_sources=service.active_sources(content_type), selected_source=source, content_type=content_type, category=category, reader_target=reader_target, items=[], safe_message="선택한 베스트셀러 소스가 비활성화되어 있습니다.")
    items = service.list_items(source, content_type, category, reader_target, page, page_size)
    return BestsellerResponse(active_sources=service.active_sources(content_type), selected_source=source, content_type=content_type, category=category, reader_target=reader_target, items=[BestsellerItemOut.model_validate(i, from_attributes=True) for i in items], last_success_at=service.last_success_at(source, content_type), cached=True, safe_message="" if items else "베스트셀러 데이터가 없습니다. 서버 갱신을 확인해 주세요.")


@router.get("/{source}", response_model=BestsellerResponse)
def list_by_source(source: str, content_type: str = "physical_book", category: str | None = None, reader_target: str | None = None, page: int = 1, page_size: int = 30, db: Session = Depends(get_db)):
    return list_bestsellers(source=source, content_type=content_type, category=category, reader_target=reader_target, page=page, page_size=page_size, db=db)


@router.post("/refresh")
async def refresh(x_admin_token: str | None = Header(default=None), source: str | None = None, content_type: str | None = None, db: Session = Depends(get_db)):
    settings = get_settings()
    if settings.admin_token and x_admin_token != settings.admin_token:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await BestsellerService(db).refresh(source, content_type)
