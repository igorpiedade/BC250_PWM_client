"""PWR BC250 client API.

Exposes:
  GET  /autodiscover - announce the local machine IP (same-subnet only)
  POST /powermgt     - power off or restart the machine (same-subnet only)
"""

from __future__ import annotations

import logging
from typing import Literal

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request, status
from pydantic import BaseModel

from app.network import get_primary_ipv4, is_same_subnet
from app.power import execute_action

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("pwr-client")

app = FastAPI(title="PWR BC250 Client", version="1.0.0")


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
