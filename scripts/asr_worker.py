#!/usr/bin/env python3
"""QuiteEcho ASR worker — persistent process for speech recognition.

Protocol (JSON lines over stdin/stdout):

  → {"cmd": "transcribe", "audio": "/path/to/file.wav"}
  ← {"text": "transcribed text"}

  → {"cmd": "reload", "model": "Qwen/Qwen3-ASR-1.7B"}
  ← {"status": "loading"}
  ← {"status": "ready"}

  ← {"status": "downloading", "progress": 42.5}
"""

import json
import os
import signal
import sys


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


# ---------------------------------------------------------------------------
# Monkey-patch tqdm BEFORE importing anything that uses huggingface_hub,
# so download progress is emitted as JSON instead of terminal bars.
# ---------------------------------------------------------------------------

class _JsonTqdm:
    """Drop-in tqdm replacement that emits JSON progress."""

    def __init__(self, iterable=None, *args, **kwargs):
        self.iterable = iterable
        self.total = kwargs.get("total") or 0
        self.n = 0
        self.disable = kwargs.get("disable", False)
        self._last_pct = -1
        if iterable is not None:
            try:
                self.total = len(iterable)
            except TypeError:
                pass

    def __iter__(self):
        if self.iterable is not None:
            for item in self.iterable:
                yield item
                self.update(1)

    def update(self, n=1):
        self.n += n
        if self.total > 0 and not self.disable:
            pct = round(min(self.n / self.total * 100, 100), 1)
            # Throttle: only emit when percentage changes by >=1
            if int(pct) != self._last_pct:
                self._last_pct = int(pct)
                emit({"status": "downloading", "progress": pct})

    def close(self):
        pass

    def reset(self, total=None):
        self.n = 0
        if total is not None:
            self.total = total

    def set_description(self, *a, **kw): pass
    def set_description_str(self, *a, **kw): pass
    def set_postfix(self, *a, **kw): pass
    def set_postfix_str(self, *a, **kw): pass
    def refresh(self, *a, **kw): pass
    def clear(self, *a, **kw): pass
    def display(self, *a, **kw): pass
    def __enter__(self): return self
    def __exit__(self, *a): self.close()
    def __len__(self): return self.total


# Patch all common tqdm entry points
import tqdm  # noqa: E402
import tqdm.auto  # noqa: E402

tqdm.tqdm = _JsonTqdm
tqdm.auto.tqdm = _JsonTqdm
tqdm.std.tqdm = _JsonTqdm

# ---------------------------------------------------------------------------


def is_model_cached(model_name: str) -> bool:
    dir_name = f"models--{model_name.replace('/', '--')}"
    cache_path = os.path.join(
        os.path.expanduser("~"), ".cache", "huggingface", "hub", dir_name, "snapshots"
    )
    return os.path.isdir(cache_path)


def load_model(model_name: str):
    import torch
    from qwen_asr import Qwen3ASRModel

    if not is_model_cached(model_name):
        emit({"status": "downloading", "progress": 0})

    if torch.cuda.is_available():
        device, dtype = "cuda:0", torch.bfloat16
    elif torch.backends.mps.is_available():
        device, dtype = "mps", torch.float16
    else:
        device, dtype = "cpu", torch.float32

    model = Qwen3ASRModel.from_pretrained(
        model_name,
        dtype=dtype,
        device_map=device if device.startswith("cuda") else None,
    )

    if not device.startswith("cuda"):
        try:
            model.model.to(device)
        except Exception:
            pass

    return model


def main() -> None:
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))

    model_name = sys.argv[1] if len(sys.argv) > 1 else "Qwen/Qwen3-ASR-0.6B"

    emit({"status": "loading"})
    model = load_model(model_name)
    emit({"status": "ready"})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            emit({"error": "invalid JSON"})
            continue

        cmd = req.get("cmd", "transcribe")

        if cmd == "transcribe":
            try:
                results = model.transcribe(
                    audio=req["audio"],
                    language=req.get("language") or None,
                )
                text = results[0].text if results else ""
                emit({"text": text})
            except Exception as e:
                emit({"error": str(e)})

        elif cmd == "reload":
            new_model = req.get("model", model_name)
            valid_models = {"Qwen/Qwen3-ASR-0.6B", "Qwen/Qwen3-ASR-1.7B"}
            if new_model not in valid_models:
                emit({"error": f"Unknown model: {new_model}"})
                continue
            emit({"status": "loading"})
            try:
                model = load_model(new_model)
                model_name = new_model
                emit({"status": "ready"})
            except Exception as e:
                emit({"error": str(e)})

        elif cmd == "ping":
            emit({"status": "ready"})


if __name__ == "__main__":
    main()
