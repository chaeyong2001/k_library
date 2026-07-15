from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from ..database import get_db
from ..schemas.public import FormatCandidateOut, FormatCandidateResponse, OfferOut, OfferResponse, PurchaseSearchResultOut, PurchaseSearchResultResponse
from ..services.purchase_service import PurchaseService

router = APIRouter(prefix="/api/v1/purchase", tags=["purchase"])

@router.get("/offers", response_model=OfferResponse)
async def offers(isbn13: str = "", isbn10: str = "", title: str = "", author: str = "", content_type: str = "physical_book", source_item_id: str = "", db: Session = Depends(get_db)):
    result, cached, stale, message = await PurchaseService(db).offers(isbn13=isbn13, isbn10=isbn10, title=title, author=author, content_type=content_type, source_item_id=source_item_id)
    return OfferResponse(query={"isbn13": isbn13, "isbn10": isbn10, "title": title, "author": author, "content_type": content_type, "source_item_id": source_item_id}, offers=[OfferOut(**offer.__dict__) for offer in result], cached=cached, stale=stale, safe_message=message)

@router.get("/search", response_model=OfferResponse)
async def search(q: str = Query(default=""), content_type: str = "physical_book", db: Session = Depends(get_db)):
    result, cached, stale, message = await PurchaseService(db).offers(title=q, content_type=content_type)
    return OfferResponse(query={"title": q, "content_type": content_type}, offers=[OfferOut(**offer.__dict__) for offer in result], cached=cached, stale=stale, safe_message=message)


@router.get("/search-results", response_model=PurchaseSearchResultResponse)
async def search_results(
    q: str = Query(default=""),
    isbn13: str = "",
    isbn10: str = "",
    content_type: str = "physical_book",
    limit: int = Query(default=20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    results, message = await PurchaseService(db).search_results(
        query=q,
        isbn13=isbn13,
        isbn10=isbn10,
        content_type=content_type,
        limit=limit,
    )
    return PurchaseSearchResultResponse(
        query={"content_type": content_type, "isbn13": isbn13, "isbn10": isbn10},
        results=[PurchaseSearchResultOut(**item) for item in results],
        safe_message=message,
    )


@router.get("/format-candidates", response_model=FormatCandidateResponse)
async def format_candidates(
    target_content_type: str = "physical_book",
    title: str = "",
    author: str = "",
    publisher: str = "",
    isbn13: str = "",
    isbn10: str = "",
    source_item_id: str = "",
    db: Session = Depends(get_db),
):
    query_title, normalized_title, candidates, message = await PurchaseService(db).format_candidates(
        title=title,
        author=author,
        publisher=publisher,
        target_content_type=target_content_type,
    )
    return FormatCandidateResponse(
        query_title=query_title,
        normalized_title=normalized_title,
        target_content_type=target_content_type,
        candidates=[FormatCandidateOut(**candidate) for candidate in candidates],
        safe_message=message,
    )
