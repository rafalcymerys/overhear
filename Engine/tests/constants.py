"""Constants shared between the test harness and the engine under test.

These mirror values in Engine/dictation_engine.py. If the engine changes one of
them, the corresponding assertion here should be updated deliberately — that is
the point of duplicating rather than importing them.
"""

SAMPLE_RATE = 16000
CHUNK_SAMPLES = 1280
CHUNK_DURATION = CHUNK_SAMPLES / SAMPLE_RATE  # 80ms
SILENCE_THRESHOLD = 0.008
SILENCE_DURATION = 1.5
MAX_BATCH_DURATION = 30

# Number of consecutive silent chunks that close a batch. int() truncation in
# the engine makes this 18, not 19.
SILENCE_CHUNKS_NEEDED = int(SILENCE_DURATION / CHUNK_DURATION)

# Sentinel sample value the fake openwakeword model recognizes as "the cancel
# word was spoken". Any chunk whose samples are all this value scores above the
# detection threshold. Passed to the engine subprocess as an env var so there is
# a single source of truth.
CANCEL_MARKER = 0.777
