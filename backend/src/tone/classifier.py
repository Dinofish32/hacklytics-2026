"""Tone classifier - placeholder for text sentiment + prosody fusion."""

from typing import Optional


def classify_tone(
    text: str,
    volume: Optional[float] = None,
) -> tuple[str, float]:
    """Return tone label and confidence (placeholder: neutral, 1.0).

    Args:
        text: Transcribed text.
        volume: Optional RMS volume for future prosody fusion.

    Returns:
        (tone, confidence). tone is one of neutral, positive, negative, etc.
    """
    # Placeholder: always return neutral with full confidence
    return ("neutral", 1.0)
