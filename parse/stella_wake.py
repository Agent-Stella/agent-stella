#!/usr/bin/env python3
"""Wake-word detection sidecar for Stella using openwakeword.

Reads raw 16-bit mono PCM at 16 kHz from stdin in fixed-size frames.
Emits one line per event on stdout:
  READY                       — sidecar finished initialising
  WAKE <model> <score>        — wake word detected
  ERROR <message>             — recoverable error worth logging

Stderr is forwarded as log output by the parent.

Models can be either bundled openwakeword names (e.g. "hey_jarvis") or
filesystem paths to .onnx/.tflite custom models. Mixed lists are allowed.
"""
import argparse
import os
import sys
import time
import traceback


def emit(line: str) -> None:
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def emit_stats(predicts: int, total_predict_ms: float, window_s: float) -> None:
    """Periodic throughput summary on stderr.

    The Go side forwards stderr to the meeting log, so this surfaces inside
    the same log stream as bus drop warnings — making it easy to correlate
    'subscriber falling behind' with actual sidecar processing latency.
    """
    avg = total_predict_ms / predicts if predicts else 0.0
    sys.stderr.write(
        f"[stats] predicts={predicts} avg_predict_ms={avg:.1f} "
        f"window_s={window_s:.1f} eff_fps={predicts / window_s:.1f}\n"
    )
    sys.stderr.flush()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--models",
        default="hey_jarvis",
        help="comma-separated list of openwakeword model names or file paths",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.5,
        help="confidence threshold (0..1) — emit WAKE only when score >= threshold",
    )
    parser.add_argument(
        "--frame-bytes",
        type=int,
        default=3200,
        help="size in bytes of each PCM read from stdin (must be even; 3200 = 100 ms @ 16 kHz s16le)",
    )
    parser.add_argument(
        "--inference-framework",
        default="onnx",
        choices=["onnx", "tflite"],
        help="openwakeword inference framework (onnx is the default; tflite is faster on Pi)",
    )
    args = parser.parse_args()

    if args.frame_bytes <= 0 or args.frame_bytes % 2 != 0:
        emit(f"ERROR invalid --frame-bytes {args.frame_bytes}")
        return 2

    try:
        import numpy as np
        from openwakeword.model import Model
    except Exception as exc:
        emit(f"ERROR import failed: {exc}")
        sys.stderr.write(traceback.format_exc())
        return 1

    model_specs = [m.strip() for m in args.models.split(",") if m.strip()]
    name_models, path_models = [], []
    for spec in model_specs:
        if os.path.exists(spec):
            path_models.append(spec)
        else:
            name_models.append(spec)

    try:
        kwargs = {"inference_framework": args.inference_framework}
        if name_models:
            kwargs["wakeword_models"] = name_models
        if path_models:
            kwargs.setdefault("wakeword_models", []).extend(path_models)
        model = Model(**kwargs)
    except Exception as exc:
        emit(f"ERROR model init failed: {exc}")
        sys.stderr.write(traceback.format_exc())
        return 1

    emit("READY")

    stdin = sys.stdin.buffer
    threshold = args.threshold
    frame_bytes = args.frame_bytes

    predict_count = 0
    predict_total_ms = 0.0
    stats_window_start = time.monotonic()
    stats_interval_s = 10.0

    while True:
        chunk = stdin.read(frame_bytes)
        if not chunk:
            break
        if len(chunk) < frame_bytes:
            # pad short tail to a whole sample, then exit on next iter (EOF).
            if len(chunk) % 2 != 0:
                chunk = chunk + b"\x00"

        try:
            audio = np.frombuffer(chunk, dtype=np.int16)
            t0 = time.monotonic()
            preds = model.predict(audio)
            predict_total_ms += (time.monotonic() - t0) * 1000.0
            predict_count += 1
        except Exception as exc:
            emit(f"ERROR predict failed: {exc}")
            sys.stderr.write(traceback.format_exc())
            continue

        for name, score in preds.items():
            try:
                s = float(score)
            except (TypeError, ValueError):
                continue
            if s >= threshold:
                emit(f"WAKE {name} {s:.4f}")

        now = time.monotonic()
        if now - stats_window_start >= stats_interval_s:
            emit_stats(predict_count, predict_total_ms, now - stats_window_start)
            predict_count = 0
            predict_total_ms = 0.0
            stats_window_start = now

    return 0


if __name__ == "__main__":
    sys.exit(main())
