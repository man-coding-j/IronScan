# IronScan local engineering dashboard

This optional FastAPI service stores anonymous synthetic engineering results and short-lived debug artifacts. The iOS app performs all model inference locally and does not require the server.

## Docker

```bash
docker compose -f Server/docker-compose.yml up --build
```

Open <http://127.0.0.1:8000/dashboard>. Compose applies the Alembic migration and inserts deterministic synthetic scans before starting the server. The published Docker port is restricted to host loopback.

## Local Python

```bash
uv sync --project Server --all-groups
uv run --project Server alembic -c Server/migrations/alembic.ini upgrade head
uv run --project Server ironscan-seed
uv run --project Server ironscan-debug-server
```

The launcher binds to `127.0.0.1`, disables access logging, and stores SQLite data in `ironscan_debug.sqlite3`. Override storage with `IRONSCAN_DATABASE_URL` and `IRONSCAN_ARTIFACT_ROOT`.

## Simulator

The iOS Simulator can reach the dashboard API at `http://127.0.0.1:8000`. Server use must remain explicitly Developer Mode-only; production inference and raw captures remain local.

## Physical device

Physical-device access is opt-in:

```bash
export IRONSCAN_LAN_MODE=true
export IRONSCAN_API_TOKEN='generate-a-long-random-development-token'
uv run ironscan-debug-server
```

Use the Mac's LAN address and send `Authorization: Bearer <token>`. Do not place tokens in URLs or logs. The provided launcher does not record access logs or client IP addresses. Keep `DEBUG_IMAGE_UPLOADS=false` unless an approved Developer Mode workflow explicitly requires short-lived non-synthetic artifacts.

## Retention and privacy

- Synthetic fixture uploads are enabled by default; unsupported fields and personal-data field names are rejected.
- Non-synthetic image uploads require `DEBUG_IMAGE_UPLOADS=true`.
- Artifact checksums and filenames are validated before files are stored beneath the configured artifact root.
- Retention defaults to seven days and can be set from one to 30 days with `IRONSCAN_ARTIFACT_RETENTION_DAYS`.
- Run `POST /api/v1/maintenance/purge-expired` to remove expired files and rows.

Never submit names, emails, dates of birth, addresses, participant identifiers, medical-record identifiers, laboratory reports, or private datasets.
