from __future__ import annotations

import os

import uvicorn

from Server.app.config import Settings


def main() -> None:
    settings = Settings.from_env()
    port = int(os.getenv("IRONSCAN_PORT", "8000"))
    uvicorn.run(
        "Server.app.main:app",
        host=settings.host,
        port=port,
        access_log=False,
        proxy_headers=False,
    )


if __name__ == "__main__":
    main()
