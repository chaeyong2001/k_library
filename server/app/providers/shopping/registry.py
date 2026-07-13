from dataclasses import dataclass
from typing import Literal
from .base import ShoppingProvider
from .aladin import AladinOfferProvider
from .links import KyoboLinkProvider, Yes24LinkProvider
from .naver import NaverApiHubShoppingProvider

ProviderRole = Literal["priced", "external_link"]


@dataclass(frozen=True)
class ShoppingProviderMeta:
    provider_id: str
    display_name: str
    offer_type: str
    role: ProviderRole
    description: str
    action_label: str
    enabled: bool = True


@dataclass(frozen=True)
class ShoppingProviderEntry:
    meta: ShoppingProviderMeta
    provider: ShoppingProvider


class ShoppingProviderRegistry:
    """Creates active shopping providers in a single, ordered place."""

    def __init__(self, settings):
        self.settings = settings

    def active_entries(self) -> list[ShoppingProviderEntry]:
        entries: list[ShoppingProviderEntry] = []
        if self.settings.enable_aladin_purchase:
            entries.append(
                ShoppingProviderEntry(
                    meta=ShoppingProviderMeta(
                        provider_id="aladin",
                        display_name="알라딘",
                        offer_type="priced_offer",
                        role="priced",
                        description="알라딘 Open API에서 제공되는 범위의 판매가와 상품 정보를 표시합니다.",
                        action_label="상품 보기",
                    ),
                    provider=AladinOfferProvider(
                        self.settings.aladin_ttb_key,
                        timeout=self.settings.request_timeout_seconds,
                    ),
                )
            )
        if self.settings.enable_naver_shopping:
            entries.append(
                ShoppingProviderEntry(
                    meta=ShoppingProviderMeta(
                        provider_id="naver_api_hub",
                        display_name="네이버 쇼핑",
                        offer_type="priced_offer",
                        role="priced",
                        description="향후 공식 상품 가격 API 확인 시 연결할 확장 Provider입니다.",
                        action_label="상품 보기",
                    ),
                    provider=NaverApiHubShoppingProvider(),
                )
            )
        if self.settings.enable_yes24_link:
            entries.append(
                ShoppingProviderEntry(
                    meta=ShoppingProviderMeta(
                        provider_id="yes24",
                        display_name="YES24",
                        offer_type="external_link",
                        role="external_link",
                        description="YES24 검색 페이지로 이동합니다. 가격은 판매처에서 확인합니다.",
                        action_label="YES24에서 찾기",
                    ),
                    provider=Yes24LinkProvider(),
                )
            )
        if self.settings.enable_kyobo_link:
            entries.append(
                ShoppingProviderEntry(
                    meta=ShoppingProviderMeta(
                        provider_id="kyobo",
                        display_name="교보문고",
                        offer_type="external_link",
                        role="external_link",
                        description="교보문고 검색 페이지로 이동합니다. 가격은 판매처에서 확인합니다.",
                        action_label="교보문고에서 찾기",
                    ),
                    provider=KyoboLinkProvider(),
                )
            )
        return entries

    def priced_entries(self) -> list[ShoppingProviderEntry]:
        return [entry for entry in self.active_entries() if entry.meta.role == "priced"]

    def external_link_entries(self) -> list[ShoppingProviderEntry]:
        return [entry for entry in self.active_entries() if entry.meta.role == "external_link"]
