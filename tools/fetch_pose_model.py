"""Fetches the MediaPipe PoseLandmarker task model used by both runtimes.

Source: https://storage.googleapis.com/mediapipe-models/pose_landmarker/
(`pose_landmarker_lite/float16/1`), Apache-2.0. The same .task file is bundled
in the Android app and loaded by the Python oracle, so both sides see identical
landmarks.

Run: python tools/fetch_pose_model.py
"""
from pathlib import Path
from urllib.request import urlopen

URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_lite/float16/1/pose_landmarker_lite.task"
)
ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "tools" / "models" / "pose_landmarker_lite.task"


def main():
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    if TARGET.exists() and TARGET.stat().st_size > 1_000_000:
        print(f"cached: {TARGET} ({TARGET.stat().st_size} bytes)")
        return
    print(f"downloading {URL}")
    with urlopen(URL, timeout=180) as response:
        data = response.read()
    if len(data) < 1_000_000:
        raise SystemExit(f"download too small: {len(data)} bytes")
    TARGET.write_bytes(data)
    print(f"wrote {TARGET} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
