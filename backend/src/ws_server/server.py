"""Minimal WebSocket server: streams caption data to a single iOS client."""

import asyncio
import json
import logging
import time

from websockets.asyncio.server import ServerConnection, serve

logger = logging.getLogger(__name__)

_client: ServerConnection | None = None

# Label → hex colour for the iOS tone badge
TONE_COLORS: dict[str, str] = {
    "positive":  "#34D399",
    "negative":  "#F87171",
    "neutral":   "#9CA3AF",
    "angry":     "#EF4444",
    "sad":       "#60A5FA",
    "happy":     "#FBBF24",
    "calm":      "#A78BFA",
    "excited":   "#F59E0B",
    "frustrated":"#FB923C",
    "surprised": "#E879F9",
}


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


async def send_caption(
    text: str,
    tone: str,
    confidence: float,
    volume: float,
    is_final: bool,
) -> None:
    """Send a caption event formatted for the iOS CaptionEvent Codable model."""
    if _client is None:
        return
    msg = json.dumps({
        "type": "caption_event",
        "t_ms": int(time.time() * 1000),
        "text": text,
        "is_final": is_final,
        "tone": {
            "label": tone,
            "confidence": round(confidence, 3),
            "color_hex": TONE_COLORS.get(tone, "#9CA3AF"),
        },
        "volume": round(min(max(volume, 0.0), 1.0), 3),
    })
    try:
        await _client.send(msg)
    except Exception:
        pass


def create_server(host: str = "0.0.0.0", port: int = 8765):
    return serve(_handler, host, port)
