"""
Provider Registry and Configuration
Manages LLM provider details and priority ordering
"""

from typing import List, Dict, Optional
from dataclasses import dataclass, field
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


@dataclass
class Provider:
    """Represents an LLM API provider"""
    name: str
    priority: int
    base_url: str
    api_key: str
    model: str

    # Rate limiting state
    is_rate_limited: bool = False
    rate_limited_until: Optional[datetime] = None

    # Request tracking
    request_count: int = 0
    last_reset: Optional[str] = None  # Date string (YYYY-MM-DD)

    # Error tracking
    consecutive_errors: int = 0
    last_error: Optional[str] = None

    # Optional tracking
    total_tokens_used: int = 0

    def increment_request_count(self):
        """Increment the request counter"""
        today = datetime.now().strftime("%Y-%m-%d")

        # Reset counter if it's a new day
        if self.last_reset != today:
            self.request_count = 0
            self.last_reset = today

        self.request_count += 1
        logger.debug(f"{self.name}: Request count = {self.request_count}")

    def mark_rate_limited(self, retry_after_seconds: Optional[int] = None):
        """Mark provider as rate limited"""
        self.is_rate_limited = True

        if retry_after_seconds:
            from datetime import timedelta
            self.rate_limited_until = datetime.now() + timedelta(seconds=retry_after_seconds)
            logger.warning(f"{self.name}: Rate limited for {retry_after_seconds}s until {self.rate_limited_until}")
        else:
            # Default: wait 60 seconds
            from datetime import timedelta
            self.rate_limited_until = datetime.now() + timedelta(seconds=60)
            logger.warning(f"{self.name}: Rate limited (default 60s cooldown)")

    def check_if_available(self) -> bool:
        """Check if provider is available (not rate limited)"""
        if not self.is_rate_limited:
            return True

        # Check if cooldown period has passed
        if self.rate_limited_until and datetime.now() >= self.rate_limited_until:
            self.is_rate_limited = False
            self.rate_limited_until = None
            self.consecutive_errors = 0
            logger.info(f"{self.name}: Rate limit cooldown expired, provider available")
            return True

        return False

    def mark_success(self):
        """Reset error counters on successful request"""
        self.consecutive_errors = 0
        self.last_error = None

    def mark_error(self, error_message: str):
        """Track errors"""
        self.consecutive_errors += 1
        self.last_error = error_message
        logger.error(f"{self.name}: Error ({self.consecutive_errors} consecutive): {error_message}")

    def to_dict(self) -> Dict:
        """Convert to dictionary for status reporting"""
        return {
            "name": self.name,
            "priority": self.priority,
            "model": self.model,
            "is_rate_limited": self.is_rate_limited,
            "rate_limited_until": self.rate_limited_until.isoformat() if self.rate_limited_until else None,
            "request_count": self.request_count,
            "last_reset": self.last_reset,
            "consecutive_errors": self.consecutive_errors,
            "last_error": self.last_error,
            "total_tokens_used": self.total_tokens_used
        }


class ProviderRegistry:
    """Manages the collection of LLM providers"""

    def __init__(self, providers: List[Provider]):
        self.providers = sorted(providers, key=lambda p: p.priority)
        logger.info(f"Initialized registry with {len(self.providers)} providers")

    def get_available_providers(self) -> List[Provider]:
        """Get list of providers that are currently available (not rate limited)"""
        available = [p for p in self.providers if p.check_if_available()]
        logger.debug(f"Available providers: {[p.name for p in available]}")
        return available

    def get_next_provider(self) -> Optional[Provider]:
        """Get the next available provider by priority"""
        available = self.get_available_providers()
        if available:
            provider = available[0]
            logger.info(f"Selected provider: {provider.name} (priority {provider.priority})")
            return provider

        logger.warning("No providers available!")
        return None

    def get_provider_by_name(self, name: str) -> Optional[Provider]:
        """Get a specific provider by name"""
        for provider in self.providers:
            if provider.name.lower() == name.lower():
                return provider
        return None

    def get_all_stats(self) -> Dict:
        """Get statistics for all providers"""
        return {
            "providers": [p.to_dict() for p in self.providers],
            "total_providers": len(self.providers),
            "available_providers": len(self.get_available_providers())
        }


def load_providers_from_config(config: Dict) -> ProviderRegistry:
    """Load providers from configuration dictionary"""
    providers = []

    for provider_config in config.get("providers", []):
        provider = Provider(
            name=provider_config["name"],
            priority=provider_config["priority"],
            base_url=provider_config["base_url"],
            api_key=provider_config["api_key"],
            model=provider_config["model"]
        )
        providers.append(provider)
        logger.info(f"Loaded provider: {provider.name} (priority {provider.priority})")

    return ProviderRegistry(providers)
