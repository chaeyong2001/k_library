from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "sqlite:///./k_library_dev.db"
    cors_origins: str = "*"
    enable_yes24_bestseller: bool = False
    enable_aladin_bestseller: bool = True
    enable_aladin_purchase: bool = True
    enable_yes24_link: bool = True
    enable_kyobo_link: bool = True
    enable_naver_shopping: bool = False
    bestseller_refresh_hours: int = 72
    purchase_cache_ttl_hours: int = 12
    offer_cache_ttl_hours: int = 12
    aladin_ttb_key: str = ""
    admin_sync_key: str = ""
    admin_refresh_token: str = ""
    request_timeout_seconds: float = 12.0
    max_page_size: int = 50

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def enabled_sources(self) -> list[str]:
        sources: list[str] = []
        if self.enable_yes24_bestseller:
            sources.append("yes24")
        if self.enable_aladin_bestseller:
            sources.append("aladin")
        return sources

    @property
    def admin_token(self) -> str:
        return self.admin_sync_key or self.admin_refresh_token


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    if settings.purchase_cache_ttl_hours == 12 and settings.offer_cache_ttl_hours != 12:
        settings.purchase_cache_ttl_hours = settings.offer_cache_ttl_hours
    return settings
