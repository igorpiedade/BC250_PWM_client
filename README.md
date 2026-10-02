# PWR BC250 Client

Small FastAPI service that lets apps on the same LAN discover this machine
and trigger power actions on it.

## Routes

| Method | Path           | Description                                  |
| ------ | -------------- | -------------------------------------------- |
| GET    | /autodiscover  | Returns `200 OK` and the local machine IP.   |
| POST   | /powermgt      | Runs `poweroff` or `reboot` on this machine. |

Both routes only answer requests coming from the same local subnet
(loopback is always allowed); anything else gets `403 Forbidden`.

### GET /autodiscover

Response:

```json
{ "status": "ok", "ip": "192.168.1.50" }
```

### POST /powermgt

Payload:

```json
{ "action": "poweroff" }
```

or

```json
{ "action": "restart" }
```

- `poweroff` -> runs the Linux `poweroff` command
- `restart`  -> runs the Linux `reboot` command

Response:

```json
{ "status": "ok", "action": "poweroff" }
```

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Run

```bash
python -m app.main          # listens on 0.0.0.0:8765
```

Dry-run mode (logs the action instead of shutting down -- useful in dev):

```bash
PWR_DRY_RUN=1 python -m app.main
```

`poweroff`/`reboot` require root, so on the target machine either run the
service as root (see deploy/pwr-bc250-client.service) or grant passwordless
sudo for those two commands.

## API request examples

Discover the machine:

```bash
curl http://<machine-ip>:8765/autodiscover
```

Response:

```json
{ "status": "ok", "ip": "192.168.1.50" }
```

Power off the machine:

```bash
curl -X POST http://<machine-ip>:8765/powermgt \
     -H "Content-Type: application/json" \
     -d '{"action": "poweroff"}'
```

Restart the machine:

```bash
curl -X POST http://<machine-ip>:8765/powermgt \
     -H "Content-Type: application/json" \
     -d '{"action": "restart"}'
```

Response to either:

```json
{ "status": "ok", "action": "poweroff" }
```

Notes:

- The payload must contain exactly `"action": "poweroff"` or
  `"action": "restart"` -- anything else returns `422 Unprocessable Entity`.
- The machine powers off / reboots about 1 second after the `200 OK`
  response is sent.
- Requests from outside the local subnet are rejected with `403 Forbidden`.

## Deploy (systemd)

Copy the project to the target Linux machine, then run the installer as root:

```bash
sudo ./deploy/install.sh
```

The script:

1. Installs the app to /opt/pwr-bc250-client and creates a venv there.
2. Installs and enables the pwr-bc250-client systemd service (runs as root,
   which poweroff/reboot require).
3. Opens port 8765/tcp in the firewall (firewalld, ufw, or raw iptables,
   whichever is active).

## Update

On the target machine, pull the latest version from GitHub and restart the
service with:

```bash
sudo ./deploy/update.sh          # latest default branch
sudo ./deploy/update.sh v1.2.3   # or a specific tag/branch/commit
```

The script downloads the repo tarball, replaces /opt/pwr-bc250-client/app,
reinstalls dependencies into the existing venv, refreshes the systemd unit,
and restarts the service.

Manual alternative:

```bash
sudo cp -r app requirements.txt /opt/pwr-bc250-client/
sudo python3 -m venv /opt/pwr-bc250-client/.venv
sudo /opt/pwr-bc250-client/.venv/bin/pip install -r /opt/pwr-bc250-client/requirements.txt
sudo cp deploy/pwr-bc250-client.service /etc/systemd/system/
sudo systemctl enable --now pwr-bc250-client
```
