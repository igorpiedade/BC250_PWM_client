"""Registration of this machine's IP address with the power controller."""

from __future__ import annotations

import asyncio
import logging
import urllib.error
import urllib.parse
import urllib.request

from app.config import ControllerConfig

logger = logging.getLogger(__name__)

_ENDPOINT = "setosaddress"
_TIMEOUT_S = 5.0
_ATTEMPTS = 3
_RETRY_DELAY_S = 5.0


def _post_ip(config: ControllerConfig, local_ip: str) -> int:
    """Send one registration request; returns the HTTP status code."""
    query = urllib.parse.urlencode({"ip": local_ip})
    url = f"http://{config.controller_ip}/{_ENDPOINT}?{query}"
    request = urllib.request.Request(
        url,
        data=b"",
        method="POST",
        headers={"Authorization": f"Bearer {config.api_key}"},
    )
    with urllib.request.urlopen(request, timeout=_TIMEOUT_S) as response:
        return int(response.status)


async def report_ip_to_controller(config: ControllerConfig, local_ip: str) -> bool:
    """POST *local_ip* to the power controller, retrying a few times.

    The blocking HTTP call runs in a worker thread so the event loop (and
    the API startup) is not delayed. Returns True when the controller
    acknowledges the registration with a 2xx response.
    """
    for attempt in range(1, _ATTEMPTS + 1):
        try:
            status_code = await asyncio.to_thread(_post_ip, config, local_ip)
            if 200 <= status_code < 300:
                logger.info(
                    "Registered local IP %s with power controller %s (HTTP %d).",
                    local_ip,
                    config.controller_ip,
                    status_code,
                )
                return True
            reason = f"HTTP {status_code}"
        except urllib.error.HTTPError as exc:
            reason = f"HTTP {exc.code}"
        except OSError as exc:  # includes URLError, timeouts, refused, ...
            reason = str(exc)
        logger.warning(
            "Controller registration attempt %d/%d failed: %s",
            attempt,
            _ATTEMPTS,
            reason,
        )
        if attempt < _ATTEMPTS:
            await asyncio.sleep(_RETRY_DELAY_S)
    logger.error(
        "Could not register local IP %s with power controller %s after %d attempts.",
        local_ip,
        config.controller_ip,
        _ATTEMPTS,
    )
    return False
