"""Fetches the OpenCV YuNet face detector used by the eval oracle.

Source: OpenCV Zoo (https://github.com/opencv/opencv_zoo), model
`face_detection_yunet/face_detection_yunet_2023mar.onnx`, MIT licensed.
The file is cached under tools/models/ and is not committed.

Run: python tools/fetch_yunet.py
"""
from pathlib import Path
from urllib.request import urlopen

MODEL_URL = (
    "https://github.com/opencv/opencv_zoo/raw/main/models/"
    "face_detection_yunet/face_detection_yunet_2023mar.onnx"
)
ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "tools" / "models" / "face_detection_yunet_2023mar.onnx"


def main():
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    if TARGET.exists() and TARGET.stat().st_size > 100_000:
        print(f"cached: {TARGET} ({TARGET.stat().st_size} bytes)")
        return
    print(f"downloading {MODEL_URL}")
    with urlopen(MODEL_URL, timeout=120) as response:
        data = response.read()
    if len(data) < 100_000:
        raise SystemExit(f"download too small: {len(data)} bytes")
    TARGET.write_bytes(data)
    print(f"wrote {TARGET} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
