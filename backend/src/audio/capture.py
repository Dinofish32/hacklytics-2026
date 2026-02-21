"""Microphone audio capture for real-time STT."""

import base64
import queue
import threading
from typing import Callable, Optional

import numpy as np
import sounddevice as sd

from .volume import compute_rms

SAMPLE_RATE = 16000
CHANNELS = 1
DTYPE = np.int16
# ~40ms per chunk for low latency (640 samples at 16kHz)
CHUNK_SIZE = 640


def capture_audio_loop(
    on_audio_chunk: Callable[[bytes, float], None],
    stop_event: threading.Event,
) -> None:
    """Capture microphone audio and call on_audio_chunk for each chunk.

    Args:
        on_audio_chunk: Callback(chunk_bytes, volume_rms). chunk_bytes is raw PCM.
        stop_event: When set, stop capturing.
    """
    audio_queue: queue.Queue[tuple[np.ndarray, float]] = queue.Queue()

    def stream_callback(
        indata: np.ndarray,
        _frames: int,
        _time_info: object,
        _status: sd.CallbackFlags,
    ) -> None:
        chunk = indata.copy().flatten()
        rms = compute_rms(chunk)
        audio_queue.put((chunk, rms))

    with sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=CHANNELS,
        dtype=DTYPE,
        blocksize=CHUNK_SIZE,
        callback=stream_callback,
    ):
        while not stop_event.is_set():
            try:
                chunk, rms = audio_queue.get(timeout=0.5)
                pcm_bytes = chunk.tobytes()
                on_audio_chunk(pcm_bytes, rms)
            except queue.Empty:
                continue


def pcm_to_base64(pcm_bytes: bytes) -> str:
    """Encode raw PCM bytes as base64 for ElevenLabs API."""
    return base64.b64encode(pcm_bytes).decode("ascii")
