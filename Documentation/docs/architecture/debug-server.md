# Local engineering debug server

The IronScan debug server is an optional development and validation tool. It stores anonymous engineering metrics and short-lived debug artifacts. It is never part of the iOS inference path; segmentation, calibration, and risk inference remain on-device.

## Network boundary

The server binds to `127.0.0.1` by default. Binding to a LAN interface requires `IRONSCAN_LAN_MODE=true` and a non-empty `IRONSCAN_API_TOKEN`. LAN clients send `Authorization: Bearer <token>`. The provided Compose profile explicitly binds inside its container while publishing only to host `127.0.0.1`. The application disables uvicorn access logging so client IP addresses and authorization headers are not written by the provided launcher.

## Privacy boundary

API schemas reject unsupported fields and field names associated with names, email, date of birth, addresses, participant identifiers, and medical-record identifiers. Notes reject common personal-data labels and email-shaped content. Fixture identifiers are anonymous slugs. Debug artifacts default to synthetic fixtures; non-synthetic uploads require `DEBUG_IMAGE_UPLOADS=true`. Raw participant data must not be used as seed or test data.

Artifacts are stored beneath `IRONSCAN_ARTIFACT_ROOT` using server-generated paths. Client filenames are validated and never become storage paths. SHA-256 is checked before persistence. Retention defaults to seven days and is bounded to 30 days. Purging removes both expired files and database rows.

## Data and migrations

SQLAlchemy maps test runs, scans, and artifacts to SQLite. `(test_run_id, anonymous_fixture_id)` is unique, so duplicate fixtures produce a deterministic conflict. Alembic owns schema creation; application startup does not silently mutate the database.

## Dashboard

Jinja2 renders test-run, scan-table, and scan-detail pages. HTMX performs partial run-list refreshes. Plotly renders score, latency, calibration, rejection, device, expected-result, and model-version diagnostics from aggregate endpoints. Artifact content is served only after resolving its database path beneath the configured artifact root.
