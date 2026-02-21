"""WebSocket server for streaming caption events to iPhone clients."""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Set

from websockets.asyncio.server import ServerConnection, serve

logger = logging.getLogger(__name__)

# Connected iPhone clients
_clients: Set[ServerConnection] = set()


def _get_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


async def _handler(websocket: ServerConnection) -> None:
    _clients.add(websocket)
    logger.info("Client connected; total=%d", len(_clients))
    try:
        async for _ in websocket:
            # Optionally handle incoming messages (e.g. ping, control)
            pass
    except Exception as e:
        logger.debug("Client disconnect: %s", e)
    finally:
        _clients.discard(websocket)
        logger.info("Client disconnected; total=%d", len(_clients))


async def broadcast_caption(
    text: str,
    caption_type: str,
    tone: str,
    tone_confidence: float,
    volume: float,
) -> None:
    """Broadcast a caption event to all connected clients."""
    payload = {
        "type": "caption",
        "text": text,
        "caption_type": caption_type,
        "tone": tone,
        "tone_confidence": tone_confidence,
        "volume": volume,
        "timestamp": _get_timestamp(),
    }
    msg = json.dumps(payload)
    if not _clients:
        logger.debug("No clients connected; caption not broadcast")
        return
    results = await asyncio.gather(
        *[ws.send(msg) for ws in _clients],
        return_exceptions=True,
    )
    for ws, r in zip(_clients, results):
        if isinstance(r, Exception):
            logger.warning("Broadcast failed to one client: %s", r)
        if ws.closed:
            _clients.discard(ws)


def create_server(host: str = "0.0.0.0", port: int = 8765):
    """Create WebSocket server. Use with: async with create_server() as server: await server.serve_forever()."""
    return serve(_handler, host, port)
