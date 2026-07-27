"""Fake openwakeword Model.

Detection is driven by a sentinel sample value rather than by acoustics: a chunk
whose samples all equal OVERHEAR_TEST_CANCEL_MARKER scores 0.9, everything else
scores 0.0. That makes "the cancel word was spoken exactly here" a deterministic
property of the test's audio instead of a probabilistic one.

The chunk must arrive whole — the harness's audio helpers only emit buffers that
are a multiple of the engine's 1280-sample block size, so a marker chunk is never
split across two predict() calls.
"""

import os

import numpy as np

BUILT_IN = {"alexa", "hey_jarvis", "hey_mycroft", "hey_rhasspy"}


class Model:
    def __init__(self, wakeword_models=None, inference_framework=None, **_kwargs):
        self.wakeword_models = list(wakeword_models or [])
        self.inference_framework = inference_framework
        self.reset_count = 0

        marker = float(os.environ.get("OVERHEAR_TEST_CANCEL_MARKER", "0.777"))
        # The engine converts float32 to int16 before calling predict().
        self._marker_int16 = int(marker * 32767)

        for name in self.wakeword_models:
            if name in BUILT_IN:
                continue
            if name.endswith(".onnx") and os.path.exists(name):
                continue
            raise ValueError(f"Could not find pretrained model for {name}")

        self._label = self.wakeword_models[0] if self.wakeword_models else "unknown"

    def predict(self, chunk_int16, **_kwargs):
        arr = np.asarray(chunk_int16)
        hit = arr.size > 0 and bool(np.all(np.abs(arr - self._marker_int16) <= 1))
        return {self._label: 0.9 if hit else 0.0}

    def reset(self):
        self.reset_count += 1
