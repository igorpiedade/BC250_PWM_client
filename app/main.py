"""PWR BC250 client API.

Exposes:
  GET  /autodiscover - announce the local machine IP (same-subnet only)
  POST /powermgt     - power off or restart the machine (same-subnet only)

On startup the service also registers the local machine IP with the power
controller configured in config.cfg.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Literal

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request, status
from pydantic import BaseModel

from app.config import load_controller_config
from app.controller import report_ip_to_controller
from app.network import get_primary_ipv4, is_same_subnet
from app.power import execute_action

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("pwr-client")

# Keep strong references to fire-and-forget tasks so they are not GC'd.
_background_tasks: set[asyncio.Task[bool]] = set()


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    """Announce this machine's IP to the power controller on startup.

    Runs in the background: the API must come up even when the controller
    (or the config) is not available yet.
    """
    config = load_controller_config()
    if config is not None:
        local_ip = get_primary_ipv4()
        task = asyncio.create_task(report_ip_to_controller(config, local_ip))
        _background_tasks.add(task)
        task.add_done_callback(_background_tasks.discard)
    yield


app = FastAPI(title="PWR BC250 Client", version="1.0.0", lifespan=lifespan)


def require_same_subnet(request: Request) -> None:
    """FastAPI dependency: only allow clients from the local subnet."""
    client = request.client.host if request.client else None
    if not client or not is_same_subnet(client):
        logger.warning("Rejected request from %s (outside local subnet)", client)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: client outside the local subnet",
        )


class PowerRequest(BaseModel):
    action: Literal["poweroff", "restart"]


@app.get("/autodiscover", dependencies=[Depends(require_same_subnet)])
def autodiscover() -> dict[str, str]:
    """Return 200 OK and this machine's local IP address."""
    return {"status": "ok", "ip": get_primary_ipv4()}


@app.post("/powermgt", dependencies=[Depends(require_same_subnet)])
def powermgt(payload: PowerRequest) -> dict[str, str]:
    """Power off or restart the machine, depending on the payload."""
    logger.info("Power action requested: %s", payload.action)
    execute_action(payload.action)
    return {"status": "ok", "action": payload.action}


if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8765)
