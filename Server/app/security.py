from __future__ import annotations

import secrets

from fastapi import Request
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp, Receive, Scope, Send

from Server.app.config import Settings


class LanTokenMiddleware:
    def __init__(self, app: ASGIApp, settings: Settings) -> None:
        self.app = app
        self.settings = settings

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if scope.get("type") != "http" or not self.settings.lan_mode:
            await self.app(scope, receive, send)
            return
        request = Request(scope)
        authorization = request.headers.get("authorization", "")
        expected = f"Bearer {self.settings.api_token}"
        if not secrets.compare_digest(authorization, expected):
            response: Response = JSONResponse({"detail": "Unauthorized"}, status_code=401)
            await response(scope, receive, send)
            return
        await self.app(scope, receive, send)
