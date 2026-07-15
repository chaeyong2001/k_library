from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import get_settings
from .database import init_db
from .api.bestsellers import router as bestsellers_router
from .api.purchase import router as purchase_router
from .api.analytics import router as analytics_router

settings = get_settings()
app = FastAPI(title="K Library Purchase API", version="0.1.0")

origins = ["*"] if settings.cors_origins == "*" else [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["GET", "POST"], allow_headers=["*"])

@app.on_event("startup")
def on_startup():
    init_db()

@app.get("/health")
def health():
    return {"ok": True, "enabled_sources": settings.enabled_sources, "naver_shopping": settings.enable_naver_shopping}

app.include_router(bestsellers_router)
app.include_router(purchase_router)
app.include_router(analytics_router)
