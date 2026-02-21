"""Minimal WebSocket server: streams caption data to a single iOS client."""

import asyncio
import json
import logging
import time

from websockets.asyncio.server import ServerConnection, serve

logger = logging.getLogger(__name__)

_client: ServerConnection | None = None


async def _handler(websocket: ServerConnection) -> None:
    global _client
    _client = websocket
    logger.info("Client connected")
    try:
        async for _ in websocket:
            pass
    except Exception:
        pass
    finally:
        if _client is websocket:
            _client = None
        logger.info("Client disconnected")


async def send_caption(text: str, tone: str, volume: float) -> None:
    if _client is None:
        return
    msg = json.dumps({
        "t_ms": int(time.time() * 1000),
        "text": text,
        "tone": tone,
        "volume": round(volume, 3),
    })
    try:
        await _client.send(msg)
    except Exception:
        pass


def create_server(host: str = "0.0.0.0", port: int = 8765):
    return serve(_handler, host, port)
