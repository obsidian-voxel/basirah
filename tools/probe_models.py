"""Probe .tflite model inputs/outputs with ai_edge_litert; keeps MODEL_IO.md truthful."""
import sys
from pathlib import Path

sys.path.insert(0, r"C:\tf")
from ai_edge_litert.interpreter import Interpreter

MODELS = [
    "pose_detection.tflite",
    "pose_landmarks_detector.tflite",
    "blaze_face_short_range.tflite",
    "selfie_multiclass_256x256.tflite",
]

def probe(path):
    interp = Interpreter(model_path=str(path))
    inp = interp.get_input_details()
    out = interp.get_output_details()
    print(f"== {path.name}")
    print(f"  inputs : {[(d['name'], d['shape'], d['dtype']) for d in inp]}")
    print(f"  outputs: {[(d['name'], d['shape'], d['dtype']) for d in out]}")
    del interp

def main():
    models_dir = Path("assets/models")
    for name in MODELS:
        probe(models_dir / name)

if __name__ == "__main__":
    main()
