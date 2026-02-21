"""RMS loudness calculation per audio chunk."""

import numpy as np


def compute_rms(audio_chunk: np.ndarray) -> float:
    """Compute RMS (root mean square) of audio chunk.

    Args:
        audio_chunk: PCM int16 mono audio samples.

    Returns:
        Normalized volume in 0-1 range for UI display.
    """
    if audio_chunk.size == 0:
        return 0.0
    # Convert int16 to float in [-1, 1]
    samples = audio_chunk.astype(np.float32) / 32768.0
    rms = np.sqrt(np.mean(samples**2))
    # Normalize: typical speech RMS ~0.01-0.3, clamp to 0-1
    normalized = min(1.0, rms * 5.0)  # Scale for visibility
    return float(normalized)
