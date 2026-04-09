# Qwen3-ASR memory profiling

Measured peak unified-memory footprint of all Qwen3-ASR variants, to
ground sizing advice and UI copy in real numbers.

## Methodology

- Standalone SwiftPM probe at `scripts/asr-memprobe/`, depending on the
  same `mlx-audio-swift` revision (`fcbd04d`) as the QuiteEcho target. It
  is a nested SwiftPM package so `swift build` at the repo root never
  triggers it — invoke via `make memprobe`.
- One subprocess per model. Isolation is required because MLX does not
  release weight buffers back to the OS when the Swift reference is dropped,
  so a single long-lived process accumulates allocations across runs and
  produces contaminated baselines (and eventually segfaults).
- Each subprocess:
  1. Samples `phys_footprint` via `task_info(TASK_VM_INFO)` — this matches
     the "Memory" column in Activity Monitor.
  2. Loads the model via `Qwen3ASRModel.fromPretrained(...)`.
  3. Runs a single forward pass over 1 s of synthetic silence @ 16 kHz.
     This is enough to allocate the audio encoder activations and KV cache,
     which dominate inference memory.
  4. Samples `phys_footprint` again for the peak figure.
  5. Emits a CSV line and exits.
- Parent process spawns children sequentially and aggregates the results.

`phys_footprint` was chosen over `resident_size` (classic RSS) because RSS
drops as the kernel reclaims clean pages under memory pressure, understating
the actual working set; `phys_footprint` stays accurate under pressure.

## Raw results (measured)

All values from a single run on an Apple Silicon machine, models served from
the local HuggingFace cache.

| Model           | Loaded   | Peak     | Inference Δ | Load time |
|-----------------|----------|----------|-------------|-----------|
| 0.6B-bf16       | 1644 MB  | 2427 MB  | +783 MB     | 0.7 s     |
| 0.6B-8bit       | 1113 MB  | 1875 MB  | +763 MB     | 0.6 s     |
| 0.6B-6bit       |  971 MB  | 1723 MB  | +752 MB     | 0.5 s     |
| 0.6B-5bit       |  900 MB  | 1658 MB  | +758 MB     | 0.5 s     |
| 0.6B-4bit       |  829 MB  | 1592 MB  | +763 MB     | 0.5 s     |
| 1.7B-bf16       | 4043 MB  | 5043 MB  | +1000 MB    | 0.9 s     |
| 1.7B-8bit       | 2506 MB  | 3499 MB  | +993 MB     | 0.9 s     |
| 1.7B-6bit       | 2092 MB  | 3076 MB  | +984 MB     | 0.7 s     |
| 1.7B-5bit       | 1883 MB  | 2873 MB  | +990 MB     | 0.6 s     |
| 1.7B-4bit       | 1685 MB  | 2674 MB  | +989 MB     | 0.5 s     |

## Key findings

### 1. Inference activation is a near-constant overhead, independent of quantization

For the 0.6B family, the delta between "model loaded" and "after one forward
pass" is consistently **760 ± 15 MB** across all five quantizations. For the
1.7B family it is **~1000 MB**. This is the audio encoder feature buffers
and KV cache, all of which stay at fp16 or fp32 regardless of how the
weights are quantized.

**Implication:** you cannot shrink the inference working set by quantizing
weights more aggressively — you can only shrink the weights themselves. For
short utterances the activation overhead is a floor you cannot get under.

### 2. Quantization savings are much smaller than weight-file size would suggest

Going from `bf16` to `4bit` on the 0.6B family:

- Weight file shrinks from ~1.5 GB on disk to ~680 MB (55% reduction)
- Peak memory shrinks from 2.4 GB to 1.6 GB (**34% reduction**)

The gap between "disk size ratio" and "peak memory ratio" is entirely
explained by finding #1: the constant activation overhead doesn't shrink, so
the relative savings are diluted.

### 3. The intermediate quantizations (6bit, 5bit) are essentially indistinguishable

Peak memory for the 0.6B family clusters tightly below 8bit:

```
bf16  →  8bit   = -552 MB   (meaningful)
8bit  →  6bit   = -152 MB
6bit  →  5bit   =  -65 MB
5bit  →  4bit   =  -66 MB
```

6bit saves 152 MB over 8bit. 5bit saves 65 MB over 6bit. For a speech app
that is triggered on demand and holds one model in RAM, these differences
are below the noise floor of "what fits on this machine". The only
quantizations with a meaningful memory story are **bf16, 8bit, and 4bit**.

### 4. Machine sizing

- **8 GB**: `0.6B-8bit` (1.9 GB peak) is the safe pick. `1.7B-4bit` (2.6
  GB) works with nothing else heavy running. Avoid 1.7B-8bit and above.
- **16 GB**: comfortable up to `1.7B-8bit` (3.5 GB peak). `1.7B-bf16` (5.0
  GB) is tight once a browser and IDE are in play.
- **24 GB+**: all variants are fine, including `1.7B-bf16`.

## Recommendations

1. **Surface measured numbers in the Models tab.** Done in
   `ModelsView.swift` — the ⓘ popover next to each family's variant
   picker shows measured peak memory for all 10 variants.

2. **Keep `0.6B-8bit` as the default.** At 1.9 GB peak it runs comfortably
   on 8 GB and leaves headroom on 16 GB machines for the browser/IDE that
   are usually open alongside. Bumping the default to the 1.7B family would
   push 8 GB users into swap.

3. **Re-run the probe if mlx-audio-swift is upgraded.** The activation
   buffer layout and KV cache behavior are determined by the library; any
   future refactor there could shift these numbers significantly.

## Probe source

Lives at `scripts/asr-memprobe/` as a nested SwiftPM package. The `make
memprobe` target builds it, copies the main project's `mlx.metallib` next
to the resulting binary (MLX Swift's metallib resolution for bare
executables is fragile, so colocation is the reliable path), and runs it.

```sh
make memprobe                                                       # cached models only
make memprobe ARGS=--all                                            # all 10 variants (triggers ~4 GB of downloads if uncached)
make memprobe ARGS="--one mlx-community/Qwen3-ASR-1.7B-4bit"        # single model
```

The probe's `Package.swift` pins the same `mlx-audio-swift` revision as
the main project. If you bump the dependency in the main `Package.swift`,
bump it here too — otherwise the colocated `mlx.metallib` (built from the
main project's mlx-swift checkout) will mismatch the Metal symbols the
probe expects and model loading will fail.
