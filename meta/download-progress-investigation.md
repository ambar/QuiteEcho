# Model download progress: investigation and non-implementation

QuiteEcho's `ASRBridge` emits a `.loading` state for the entire fetch+load
cycle when selecting a new model. `State` also defines a `.downloading(Double)`
case, and `ModelsView` has a fully-wired progress-bar UI for it — but nothing
emits that state. This document explains why: **real byte-level download
progress is not achievable with the current dependency chain without
forking swift-huggingface**, and every user-space workaround was empirically
verified to fail.

## What was tried

### Approach 1 — directory size polling

`ASRBridge.start()` would poll `AppConfig.modelCacheDir(modelId)` every
~400 ms, compare the directory size against a hardcoded expected total,
and emit `.downloading(bytes / total * 100)`.

Expected to work because bytes should land in the destination dir as the
download progresses.

### Approach 2 — HubClient.downloadSnapshot with progressHandler

Add `swift-huggingface` as a direct dependency, call
`HubClient.downloadSnapshot(to:..., progressHandler:)` ourselves before
`Qwen3ASRModel.fromPretrained`. mlx-audio-swift already does this
internally and would find the populated cache on the subsequent
`fromPretrained` call. `progressHandler` fires every 100 ms with a
`Progress` whose `fractionCompleted` should reflect bytes downloaded.

## Empirical verification

Wired up a `--download-test` mode in `scripts/asr-memprobe/` that runs
both signals in parallel during a real fresh download of
`mlx-community/Qwen3-ASR-0.6B-4bit` (680 MB, ~74 s through the HF mirror).
Both caches (`~/.cache/huggingface/hub/models--...` and the mlx-audio
subdir) were cleared beforehand to force a real LFS fetch.

The run logs the two signals side-by-side at 1 s intervals:

```
  [dir-poll]  on-disk=    0.0 MB   elapsed=0.0s
  [hf-prog]     0.0%      0.0 /   679.8 MB   elapsed=0.7s
  [dir-poll]  on-disk=    0.1 MB   elapsed=2.0s
  [hf-prog]     0.0%      0.1 /   679.8 MB   elapsed=2.1s
  [dir-poll]  on-disk=    4.3 MB   elapsed=4.0s
  [hf-prog]     0.6%      4.3 /   679.8 MB   elapsed=4.0s
  ... [both stuck here for ~70 seconds] ...
  [dir-poll]  on-disk=    4.3 MB   elapsed=73.6s
  [hf-prog]     0.6%      4.3 /   679.8 MB   elapsed=73.6s

✅ downloaded in 74.0s
```

Both signals climb to 4.3 MB / 0.6% in the first 4 seconds as the small
metadata files (config.json, tokenizer.json, generation_config.json,
vocab, merges) land. Then **both stay frozen for 70 seconds while the
680 MB safetensors file streams**. At completion, both jump to 100 % at
the same instant.

The two independent signals tell the same story because they have the
same root cause.

## Root cause

HuggingFace stores large model weights as **LFS objects**. When
`swift-huggingface`'s `downloadSnapshot` fetches an LFS file, it hands
`URLSession.download(for:delegate:)` a `DownloadProgressDelegate` that
updates an `NSProgress` child via `urlSession(_:downloadTask:didWriteData:...)`.

Two problems compound:

1. **URLSession streams LFS downloads to its own temporary directory**,
   not to the destination URL we passed. Only after the download
   completes is the file moved into the blob cache, and then separately
   copied into our destination subdir. So
   `FileManager.default.enumerator(atPath: destinationDir)` sees zero
   bytes until the very end — directory polling (approach 1) is
   fundamentally unable to observe the LFS file at all.

2. **`swift-huggingface`'s parent-to-child Progress aggregation
   under-reports LFS progress.** The parent `Progress` object gets its
   `totalUnitCount` from `snapshotWeight(for:)`, which uses
   `entry.size` from the Git tree listing. For LFS entries that size
   may reflect the pointer file (a few hundred bytes), not the actual
   blob, so the child's pending unit count is tiny relative to the real
   download. As the URLSession delegate saturates the child's
   `completedUnitCount`, the parent's `fractionCompleted` barely moves.
   The final jump to 100% comes from an explicit
   `progress.completedUnitCount = progress.totalUnitCount` assignment
   after the file is in place, not from byte-level observation.

The net effect: `HubClient.downloadSnapshot`'s `progressHandler`
(approach 2) is also fundamentally unable to report byte-level progress
for LFS files, at least as of the pinned swift-huggingface revision
(`0.8.1`).

## Related upstream issue and partial fix

The problem is tracked upstream as
[huggingface/swift-huggingface#48](https://github.com/huggingface/swift-huggingface/issues/48)
— "downloadSnapshot(...) Does not report per file progress". The
symptom described by the reporter ("stuck at 1% for a few minutes then
jumps to 100%") is exactly what we observed. As of swift-huggingface
0.9.0 (the latest release at time of writing) the issue is still OPEN.
The Apple Developer thread it links to
([738541](https://developer.apple.com/forums/thread/738541)) points at
an AppKit/URLSession bug where `URLSessionDownloadDelegate`'s
`urlSession(_:downloadTask:didWriteData:...)` callbacks are batched or
delayed, so the official delegate-based progress path doesn't actually
animate.

The reporter (`iSapozhnik`) merged a workaround into their own fork:
[iSapozhnik/swift-huggingface PR #1](https://github.com/iSapozhnik/swift-huggingface/pull/1).
It replaces `session.download(for:delegate:)` with a custom
`asyncDownloadWithProgress` that polls `URLSessionDownloadTask.progress`
via KVO instead of relying on the delegate callbacks, dodging the Apple
bug.

### We verified the fork end-to-end

Switched `scripts/asr-memprobe/Package.swift` to point at the fork
(pinned to commit `c782dcff00484fb4d7e1340afbc8012facc64564`) and ran a
fresh 680 MB download of `mlx-community/Qwen3-ASR-0.6B-4bit` through
the HF mirror. Progress now animates linearly:

```
 0.0% →  1.9% → 10.1% → 20.3% → 30.1% → 50.2% → 80.5% → 99.4%
  0.5s     2.5s     8.1s    14.5s    20.6s    33.5s    52.6s    65.1s
 done at 65.4s
```

About 0.8 % per 500 ms — exactly what a `.downloading(pct)` UI would
need. Read `progress.fractionCompleted`, not
`progress.completedUnitCount / totalUnitCount` — NSProgress parent/child
aggregation updates `fractionCompleted` from children but does not
update the parent's own `completedUnitCount`, which stays at the bytes
written directly to the parent.

### Caveat: xet path is still broken

The fork fixes the URLSession LFS delegate path, not the xet path.
Which one a download hits depends on the endpoint:

- **`hf-mirror.com`** proxies the actual bytes (it 302-redirects to
  `cas-bridge.xethub.hf.co`, the same CDN as the official endpoint)
  but **strips the `X-Xet-Hash` response header** on the HEAD
  request. `XetFileMetadata.init?` reads that header to decide
  whether to take the xet transport path, so missing ⇒ fallback to
  URLSession LFS. Mirror users go through the LFS path and get the
  fork's fix.
- **`huggingface.co`** returns `X-Xet-Hash`, so safetensors >16 MiB
  go into `downloadFileWithXet`, which contains the unfixed code:

  ```swift
  _ = try await Xet.withDownloader(...) { downloader in
      try await downloader.download(fileID, to: destination)
  }
  progress?.totalUnitCount = 100
  progress?.completedUnitCount = 100   // only after the entire download
  ```

  No progress hook is wired into `Xet.download`, so xet-served
  downloads still jump 0 % → 100 % at the end.

Empirical check — HEAD the same file against both endpoints and
compare headers:

```
$ curl -sIL 'https://hf-mirror.com/.../model.safetensors' | grep -i xet
                                           (nothing)
$ curl -sIL 'https://huggingface.co/.../model.safetensors' | grep -i xet
x-xet-hash: 1a3f5ab2aa1c0aa7a727010dea7f887158d235b1e704cc2127b271609d450a97
```

Fully closing both gaps requires one of:

1. **Adopt the fork + disable the `Xet` trait.** swift-huggingface 0.9.0
   added a package trait (`Xet`, default-on) that gates the swift-xet
   dependency and falls back to LFS. Setting it off in our
   `Package.swift` forces every download through the URLSession LFS
   path on both mirror and hf.co, where the fork's polling delegate
   fix applies. Complete user-space fix with no further upstream
   patching. Cost: losing xet's content-addressable blob reuse,
   which is essentially zero for a QuiteEcho install that only ever
   pulls the Qwen3-ASR family.

2. **Adopt the fork and also add a progress hook to `swift-xet`'s
   `Xet.download(_:byteRange:to:)`.** The write loop already tracks
   `totalWritten`; it just needs a closure parameter. Two upstream
   patches instead of one, but keeps xet's optimizations.



- **Fork swift-huggingface and fix the LFS aggregation.** The child
  Progress could be initialized with the *true* file size (fetchable
  from an LFS HEAD request before starting the download). This gives
  smooth progress but means carrying a fork and keeping it in sync with
  upstream. For a cosmetic improvement to a cold-start progress bar,
  not worth the maintenance burden.

- **Poll URLSession's internal temp file.** It lives under
  `NSTemporaryDirectory()/NSURLSessionDownloadXXXX.tmp` during the
  transfer. The filename is a private implementation detail and finding
  the right file by PID or fd would be ugly and brittle. Rejected.

- **Roll our own `URLSession.downloadTask` that writes to a file under
  our control.** This means re-implementing the LFS resolve flow
  (pointer → blob URL, commit hash resolution, resume, mirror handling,
  retries) that swift-huggingface already does correctly. A lot of code
  to duplicate for a progress bar.

## Decision

Currently: **do nothing**. `ASRBridge.start()` calls
`Qwen3ASRModel.fromPretrained` directly and stays in `.loading` for the
whole fetch+load cycle. `ModelsView` shows the existing "Loading"
spinner. The `.downloading(Double)` state and its UI branch are kept
as dead code.

The fork experiment proves a smooth progress bar is achievable for
QuiteEcho's common case (hf-mirror users), with a ~20-line change to
`ASRBridge` to call `HubClient.downloadSnapshot` with a progressHandler
before `fromPretrained`. The trade-off is carrying a dependency on a
personal fork pinned by commit hash, versus waiting for upstream to
merge the fix.

If/when upstream swift-huggingface ships a fix for issue #48, the
`.downloading(pct)` wire-up becomes a clean upstream-only change with
no fork dependency.

## Side-find: models are stored on disk twice

HubClient's internal cache keeps its own copy under
`~/.cache/huggingface/hub/models--mlx-community--MODEL/` (HF's
canonical `models--<org>--<name>` layout with `blobs/`, `refs/`,
`snapshots/`). mlx-audio-swift's `ModelUtils.resolveOrDownloadModel`
then copies (not hardlinks — verified by inode) the files into its
own `~/.cache/huggingface/hub/mlx-audio/mlx-community_MODEL/` subdir.
This roughly doubles the disk footprint per model. Not fixed in this
round — it would require patching mlx-audio-swift to symlink or
hardlink, and is out of scope for the progress investigation.

`AppConfig.modelCacheDir` is deliberately left pointing at the HF
classic path rather than the `mlx-audio/` subdir. The classic layout
is the stable upstream convention (used by Python `huggingface_hub`
too) and will be populated as a side effect of any future download
path, whereas the `mlx-audio/` subdir is an implementation detail of
the current mlx-audio-swift version and could disappear if upstream
switches to hardlinks or collapses the duplication.
