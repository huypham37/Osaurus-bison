"""
LLM Rotation Proxy Server
OpenAI-compatible API proxy with automatic provider rotation
"""

import logging
import os
import sys
from typing import Optional, Dict, Any
from datetime import datetime

from fastapi import FastAPI, Request, HTTPException, status
from fastapi.responses import JSONResponse, StreamingResponse
import httpx
import yaml
import uvicorn
from dotenv import load_dotenv

from providers import load_providers_from_config, ProviderRegistry, Provider

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="LLM Rotation Proxy",
    description="OpenAI-compatible API proxy with automatic provider rotation",
    version="1.0.0"
)

# Global registry
registry: Optional[ProviderRegistry] = None


def parse_retry_after(headers: httpx.Headers) -> Optional[int]:
    """
    Parse retry-after header from response
    Returns seconds to wait
    """
    # Try retry-after-ms first (milliseconds)
    if "retry-after-ms" in headers:
        try:
            ms = int(headers["retry-after-ms"])
            return ms // 1000  # Convert to seconds
        except ValueError:
            pass

    # Try retry-after (seconds)
    if "retry-after" in headers:
        try:
            return int(headers["retry-after"])
        except ValueError:
            pass

    return None


async def make_request_to_provider(
    provider: Provider,
    endpoint: str,
    json_data: Dict[str, Any],
    stream: bool = False
) -> httpx.Response:
    """
    Make a request to a specific provider
    """
    # Use endpoint_override if provided, otherwise use default endpoint
    final_endpoint = provider.endpoint_override if provider.endpoint_override else endpoint
    url = f"{provider.base_url.rstrip('/')}/{final_endpoint.lstrip('/')}"

    headers = {
        "Authorization": f"Bearer {provider.api_key}",
        "Content-Type": "application/json"
    }

    # Override model if specified in provider config
    if "model" not in json_data or json_data["model"] == "default":
        json_data["model"] = provider.model

    logger.info(f"Making request to {provider.name}: {url}")
    logger.debug(f"Request payload: {json_data}")

    async with httpx.AsyncClient(timeout=60.0) as client:
        if stream:
            response = await client.post(url, json=json_data, headers=headers)
            return response
        else:
            response = await client.post(url, json=json_data, headers=headers)
            return response


async def try_providers_in_order(
    endpoint: str,
    json_data: Dict[str, Any],
    stream: bool = False
) -> tuple[Optional[httpx.Response], Optional[Provider]]:
    """
    Try providers in priority order until one succeeds
    Returns (response, provider) tuple
    """
    available_providers = registry.get_available_providers()

    if not available_providers:
        logger.error("No providers available!")
        return None, None

    for provider in available_providers:
        try:
            # Increment request counter
            provider.increment_request_count()

            # Make request
            response = await make_request_to_provider(provider, endpoint, json_data, stream)

            # Check for rate limiting (429)
            if response.status_code == 429:
                logger.warning(f"{provider.name}: Rate limited (429)")

                # Parse retry-after header
                retry_after = parse_retry_after(response.headers)
                provider.mark_rate_limited(retry_after)

                # Try next provider
                continue

            # Check for other errors
            if response.status_code >= 400:
                error_text = response.text[:200]  # First 200 chars
                logger.warning(f"{provider.name}: Error {response.status_code}: {error_text}")
                provider.mark_error(f"HTTP {response.status_code}: {error_text}")

                # For 5xx errors, try next provider
                if response.status_code >= 500:
                    continue

                # For 4xx errors (except 429), return the error to client
                return response, provider

            # Success!
            provider.mark_success()
            logger.info(f"{provider.name}: Request successful (status {response.status_code})")

            # Track token usage if available
            if response.status_code == 200:
                try:
                    response_json = response.json()
                    if "usage" in response_json and "total_tokens" in response_json["usage"]:
                        tokens = response_json["usage"]["total_tokens"]
                        provider.total_tokens_used += tokens
                        logger.debug(f"{provider.name}: Used {tokens} tokens (total: {provider.total_tokens_used})")
                except Exception as e:
                    logger.debug(f"Could not parse token usage: {e}")

            return response, provider

        except httpx.TimeoutException as e:
            logger.error(f"{provider.name}: Timeout - {e}")
            provider.mark_error(f"Timeout: {e}")
            continue

        except httpx.ConnectError as e:
            logger.error(f"{provider.name}: Connection error - {e}")
            provider.mark_error(f"Connection error: {e}")
            continue

        except Exception as e:
            logger.error(f"{provider.name}: Unexpected error - {e}")
            provider.mark_error(f"Unexpected error: {e}")
            continue

    # All providers failed
    logger.error("All providers failed or are rate limited")
    return None, None


@app.on_event("startup")
async def startup_event():
    """Load configuration on startup"""
    global registry

    try:
        # Load config file
        config_path = os.path.join(os.path.dirname(__file__), "config.yaml")
        with open(config_path, "r") as f:
            config = yaml.safe_load(f)

        # Initialize provider registry
        registry = load_providers_from_config(config)
        logger.info("Proxy server started successfully")

    except FileNotFoundError:
        logger.error("config.yaml not found! Please create configuration file.")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Failed to start server: {e}")
        sys.exit(1)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "providers_loaded": len(registry.providers) if registry else 0
    }


@app.get("/status")
async def get_status():
    """Get current status of all providers"""
    if not registry:
        raise HTTPException(status_code=503, detail="Registry not initialized")

    return registry.get_all_stats()


@app.get("/stats")
async def get_stats():
    """Get statistics (alias for status)"""
    return await get_status()


@app.post("/reload")
async def reload_config():
    """Reload configuration from file"""
    global registry

    try:
        with open("/home/user/Osaurus-bison/llm-proxy/config.yaml", "r") as f:
            config = yaml.safe_load(f)

        registry = load_providers_from_config(config)
        logger.info("Configuration reloaded")

        return {
            "status": "success",
            "message": "Configuration reloaded",
            "providers_loaded": len(registry.providers)
        }

    except Exception as e:
        logger.error(f"Failed to reload config: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to reload: {str(e)}")


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """
    OpenAI-compatible chat completions endpoint
    Handles both streaming and non-streaming requests
    """
    if not registry:
        raise HTTPException(status_code=503, detail="Service not initialized")

    # Parse request body
    try:
        json_data = await request.json()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {str(e)}")

    # Check if streaming is requested
    stream = json_data.get("stream", False)

    # Try providers
    response, provider = await try_providers_in_order(
        endpoint="/v1/chat/completions",
        json_data=json_data,
        stream=stream
    )

    if response is None:
        raise HTTPException(
            status_code=503,
            detail="All providers are currently unavailable or rate limited"
        )

    # Return response
    if stream:
        # For streaming, we need to pass through the response
        return StreamingResponse(
            response.aiter_bytes(),
            media_type="text/event-stream",
            headers={
                "X-Provider": provider.name,
                "X-Model": provider.model
            }
        )
    else:
        # For non-streaming, return JSON
        return JSONResponse(
            content=response.json(),
            status_code=response.status_code,
            headers={
                "X-Provider": provider.name,
                "X-Model": provider.model
            }
        )


@app.post("/v1/completions")
async def completions(request: Request):
    """
    OpenAI-compatible completions endpoint (legacy)
    """
    if not registry:
        raise HTTPException(status_code=503, detail="Service not initialized")

    try:
        json_data = await request.json()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {str(e)}")

    stream = json_data.get("stream", False)

    response, provider = await try_providers_in_order(
        endpoint="/v1/completions",
        json_data=json_data,
        stream=stream
    )

    if response is None:
        raise HTTPException(
            status_code=503,
            detail="All providers are currently unavailable or rate limited"
        )

    if stream:
        return StreamingResponse(
            response.aiter_bytes(),
            media_type="text/event-stream",
            headers={"X-Provider": provider.name}
        )
    else:
        return JSONResponse(
            content=response.json(),
            status_code=response.status_code,
            headers={"X-Provider": provider.name}
        )


@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": "LLM Rotation Proxy",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "health": "/health",
            "status": "/status",
            "stats": "/stats",
            "reload": "/reload (POST)",
            "chat": "/v1/chat/completions (POST)",
            "completions": "/v1/completions (POST)"
        }
    }


if __name__ == "__main__":
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=8000,
        log_level="info"
    )
