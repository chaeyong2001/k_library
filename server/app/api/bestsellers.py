from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy.orm import Session
from ..config import get_settings
from ..database import get_db
from ..schemas.public import BestsellerItemOut, BestsellerResponse, SourceOut
from ..services.bestseller_service import BestsellerService

router = APIRouter(prefix="/api/v1/bestsellers", tags=["bestsellers"])

@router.get("/sources", response_model=list[SourceOut])
def sources(db: Session = Depends(get_db)):
    service = BestsellerService(db)
    active = set(service.active_sources())
    return [SourceOut(source="yes24", label="YES24 기준", enabled="yes24" in active, categories=service.source_categories("yes24")), SourceOut(source="aladin", label="알라딘 기준", enabled="aladin" in active, categories=service.source_categories("aladin"))]

@router.get("/categories", response_model=list[str])
def categories(db: Session = Depends(get_db)):
    return BestsellerService(db).categories()

@router.get("", response_model=BestsellerResponse)
def list_bestsellers(source: str | None = Query(default=None), category: str | None = Query(default=None), page: int = 1, page_size: int = 30, db: Session = Depends(get_db)):
    service = BestsellerService(db)
    if source and source not in service.active_sources():
        return BestsellerResponse(active_sources=service.active_sources(), selected_source=source, category=category, items=[], safe_message="선택한 베스트셀러 소스가 비활성화되어 있습니다.")
    items = service.list_items(source, category, page, page_size)
    return BestsellerResponse(active_sources=service.active_sources(), selected_source=source, category=category, items=[BestsellerItemOut.model_validate(i, from_attributes=True) for i in items], last_success_at=service.last_success_at(source), cached=True, safe_message="" if items else "베스트셀러 데이터가 없습니다. 서버 갱신을 확인해 주세요.")

@router.get("/{source}", response_model=BestsellerResponse)
def list_by_source(source: str, category: str | None = None, page: int = 1, page_size: int = 30, db: Session = Depends(get_db)):
    return list_bestsellers(source=source, category=category, page=page, page_size=page_size, db=db)

@router.post("/refresh")
async def refresh(x_admin_token: str | None = Header(default=None), source: str | None = None, db: Session = Depends(get_db)):
    settings = get_settings()
    if settings.admin_token and x_admin_token != settings.admin_token:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await BestsellerService(db).refresh(source)


