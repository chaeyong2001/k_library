from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from ..database import get_db
from ..schemas.public import OfferOut, OfferResponse
from ..services.purchase_service import PurchaseService

router = APIRouter(prefix="/api/v1/purchase", tags=["purchase"])

@router.get("/offers", response_model=OfferResponse)
async def offers(isbn13: str = "", isbn10: str = "", title: str = "", author: str = "", db: Session = Depends(get_db)):
    result, cached, stale, message = await PurchaseService(db).offers(isbn13=isbn13, isbn10=isbn10, title=title, author=author)
    return OfferResponse(query={"isbn13": isbn13, "isbn10": isbn10, "title": title, "author": author}, offers=[OfferOut(**offer.__dict__) for offer in result], cached=cached, stale=stale, safe_message=message)

@router.get("/search", response_model=OfferResponse)
async def search(q: str = Query(default=""), db: Session = Depends(get_db)):
    result, cached, stale, message = await PurchaseService(db).offers(title=q)
    return OfferResponse(query={"title": q}, offers=[OfferOut(**offer.__dict__) for offer in result], cached=cached, stale=stale, safe_message=message)
