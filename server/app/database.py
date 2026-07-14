from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from .config import get_settings

settings = get_settings()
connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, pool_pre_ping=True, pool_size=3, max_overflow=3, connect_args=connect_args)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    from .models import db_models  # noqa: F401

    Base.metadata.create_all(bind=engine)
    _ensure_bestseller_reader_target_column()


def _ensure_bestseller_reader_target_column() -> None:
    inspector = inspect(engine)
    if not inspector.has_table("kl_bestseller_items"):
        return
    columns = {column["name"] for column in inspector.get_columns("kl_bestseller_items")}
    dialect = engine.dialect.name
    with engine.begin() as conn:
        if "reader_target" not in columns:
            if dialect == "postgresql":
                conn.execute(text("ALTER TABLE kl_bestseller_items ADD COLUMN IF NOT EXISTS reader_target VARCHAR(40) DEFAULT '미분류'"))
            else:
                conn.execute(text("ALTER TABLE kl_bestseller_items ADD COLUMN reader_target VARCHAR(40) DEFAULT '미분류'"))
        conn.execute(text("UPDATE kl_bestseller_items SET reader_target = '어린이' WHERE category = '어린이' AND (reader_target IS NULL OR reader_target = '미분류' OR reader_target = '')"))
        conn.execute(text("UPDATE kl_bestseller_items SET reader_target = '청소년' WHERE category = '청소년' AND (reader_target IS NULL OR reader_target = '미분류' OR reader_target = '')"))
        conn.execute(text("UPDATE kl_bestseller_items SET reader_target = '성인' WHERE reader_target IS NULL OR reader_target = '미분류' OR reader_target = ''"))
        if dialect == "postgresql":
            conn.execute(text("ALTER TABLE kl_bestseller_items DROP CONSTRAINT IF EXISTS uq_kl_best_rank"))
            conn.execute(text("DROP INDEX IF EXISTS ix_kl_best_source_category_rank"))
            conn.execute(text("ALTER TABLE kl_bestseller_items ADD CONSTRAINT uq_kl_best_rank UNIQUE (source, category, reader_target, ranking_date, rank)"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_kl_best_source_category_reader_rank ON kl_bestseller_items (source, category, reader_target, ranking_date, rank)"))
