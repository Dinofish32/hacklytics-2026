"""Websocket bridge between backend runtime and iOS app.

Connection model:
- One active iOS websocket client is tracked (`_client`).
- Backend -> iOS events use `type="caption_event"`.
- iOS -> backend final uploads use `type="meeting_payload"`.

Message contract:
- caption_event:
  {
    "type": "caption_event",
    "t_ms": <epoch_ms>,
    "text": <full_current_chunk_text>,
    "is_final": <bool>,
    "tone": {"label": str, "confidence": float, "color_hex": str},
    "volume": <0..1 float>
  }
- meeting_payload:
  {
    "type": "meeting_payload",
    "started_at_ms": <epoch_ms>,
    "ended_at_ms": <epoch_ms>,
    "transcripts": [...],
    "participants": [...]
  }
"""

import inspect
import json
import logging
import time
from typing import Any, Awaitable, Callable

from websockets.asyncio.server import ServerConnection, serve

logger = logging.getLogger(__name__)

_client: ServerConnection | None = None
_on_meeting_payload: Callable[[dict[str, Any]], Awaitable[None] | None] | None = None

TONE_COLOR_MAP: dict[str, str] = {
    "neutral": "#9CA3AF",
    "happy": "#22C55E",
    "excited": "#F59E0B",
    "calm": "#38BDF8",
    "sad": "#3B82F6",
    "angry": "#EF4444",
    "frustrated": "#F97316",
    "surprised": "#A855F7",
}


def _tone_color_hex(label: str) -> str:
    return TONE_COLOR_MAP.get(label.lower(), TONE_COLOR_MAP["neutral"])


async def _dispatch_meeting_payload(payload: dict[str, Any]) -> None:
    """Forward iOS meeting payload to configured backend handler."""
    if _on_meeting_payload is None:
        logger.info("meeting_payload received with no handler configured")
        return
    try:
        result = _on_meeting_payload(payload)
        if inspect.isawaitable(result):
            await result
    except Exception as exc:
        logger.warning("meeting_payload handler failed: %s", exc)


async def _handler(websocket: ServerConnection) -> None:
    global _client
    _client = websocket
    logger.info("Client connected")
    try:
        async for incoming in websocket:
            if isinstance(incoming, bytes):
                try:
                    incoming_text = incoming.decode("utf-8")
                except UnicodeDecodeError:
                    continue
            else:
                incoming_text = incoming

            try:
                payload = json.loads(incoming_text)
            except (TypeError, json.JSONDecodeError):
                continue

            # iOS final upload route.
            if payload.get("type") == "meeting_payload":
                await _dispatch_meeting_payload(payload)
    except Exception:
        pass
    finally:
        if _client is websocket:
            _client = None
        logger.info("Client disconnected")


async def send_caption(text: str, tone: str, confidence: float, volume: float, is_final: bool) -> None:
    """Send one caption chunk event to iOS."""
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
            "color_hex": _tone_color_hex(tone),
        },
        "volume": round(volume, 3),
    })
    try:
        await _client.send(msg)
    except Exception:
        pass


async def broadcast_caption(
    text: str,
    caption_type: str,
    tone: str,
    confidence: float,
    volume: float,
) -> None:
    """Compatibility wrapper used by main pipeline callback."""
    await send_caption(
        text=text,
        tone=tone,
        confidence=confidence,
        volume=volume,
        is_final=(caption_type == "final"),
    )


def create_server(
    host: str = "0.0.0.0",
    port: int = 8765,
    on_meeting_payload: Callable[[dict[str, Any]], Awaitable[None] | None] | None = None,
):
    """Create websocket server and optionally register meeting payload callback."""
    global _on_meeting_payload
    _on_meeting_payload = on_meeting_payload
    return serve(_handler, host, port)
