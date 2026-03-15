# Development

## Install

```sh
git clone https://github.com/user/QuiteEcho.git
cd QuiteEcho
make build
open QuiteEcho.app
```

On first launch, the app automatically sets up the runtime environment and downloads the model (~1.5GB total).

## Build & run

```sh
make build   # release build + assemble .app bundle
make run     # build + open
make dev     # debug build + run directly
make clean   # clean build artifacts
```
