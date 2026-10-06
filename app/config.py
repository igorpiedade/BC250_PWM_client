"""Loading of the power controller configuration (config.cfg)."""

from __future__ import annotations

import configparser
import logging
import os
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)

# config.cfg lives next to the app package: <install-dir>/config.cfg,
# which is the project root in development and /opt/pwr-bc250-client
# when installed by deploy/install.sh.
DEFAULT_CONFIG_FILE = Path(__file__).resolve().parent.parent / "config.cfg"

SECTION = "power-controller"


@dataclass(frozen=True)
class ControllerConfig:
    """Settings used to reach the power controller."""

    controller_ip: str
    api_key: str


def _config_path() -> Path:
    override = os.getenv("PWR_CONFIG_FILE", "").strip()
    return Path(override) if override else DEFAULT_CONFIG_FILE


def load_controller_config() -> ControllerConfig | None:
    """Read config.cfg and return the controller settings.

    Returns None (and logs why) when the file is missing or incomplete --
    power management must keep working even without controller registration.
    """
    path = _config_path()
    if not path.is_file():
        logger.warning(
            "Config file %s not found - skipping power controller registration. "
            "Run deploy/install.sh or create it manually.",
            path,
        )
        return None

    parser = configparser.ConfigParser()
    try:
        parser.read(path)
    except configparser.Error as exc:
        logger.warning("Could not parse %s: %s - skipping registration.", path, exc)
        return None

    controller_ip = parser.get(SECTION, "ip", fallback="").strip()
    api_key = parser.get(SECTION, "api-key", fallback="").strip()
    if not controller_ip or not api_key:
        logger.warning(
            "%s is missing 'ip' or 'api-key' in [%s] - skipping registration.",
            path,
            SECTION,
        )
        return None

    return ControllerConfig(controller_ip=controller_ip, api_key=api_key)
