"""Execution of power management commands."""

from __future__ import annotations

import logging
import os
import shlex
import subprocess

logger = logging.getLogger(__name__)

_COMMANDS = {
    "poweroff": ["poweroff"],
    "restart": ["reboot"],
}


def execute_action(action: str) -> None:
    """Run the system command mapped to *action*.

    The command runs detached and with a short delay so the HTTP response
    reaches the client before the machine goes down. Set PWR_DRY_RUN=1 to
    log the action instead of executing it (useful for development).
    """
    command = _COMMANDS[action]
    if os.getenv("PWR_DRY_RUN", "").lower() in {"1", "true", "yes"}:
        logger.info("DRY-RUN: would execute %s", command)
        return
    shell_cmd = f"sleep 1 && {shlex.join(command)}"
    logger.info("Executing power action %r (%s)", action, shell_cmd)
    subprocess.Popen(  # noqa: S603 - fixed, internally-defined command
        ["sh", "-c", shell_cmd],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
