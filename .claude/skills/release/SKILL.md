---
name: release
description: Bump version, commit, tag, and push to trigger the GitHub Actions release workflow.
disable-model-invocation: true
argument-hint: "[version, e.g. 1.0.0]"
---

Follow these steps to release a new version of QuiteEcho:

## 1. Read current version

Read `pyproject.toml` and extract the current `version = "..."` value.

## 2. Determine new version

Look at `$ARGUMENTS`:

- **No argument or `patch`**: bump the patch component (e.g. `0.1.0` → `0.1.1`)
- **`minor`**: bump minor, reset patch (e.g. `0.1.3` → `0.2.0`)
- **`major`**: bump major, reset minor and patch (e.g. `0.1.3` → `1.0.0`)
- **Explicit semver (e.g. `1.0.0`)**: use it as-is

## 3. Confirm with user

Show the user:

```
Release: v{current} → v{new}
```

Wait for the user to confirm before proceeding. Do NOT continue without confirmation.

## 4. Bump version

Run:

```bash
bash scripts/bump-version.sh {new_version}
```

This updates `Resources/Info.plist`, `Sources/QuiteEcho/MainWindow.swift`, and `pyproject.toml`.

## 5. Commit

```bash
git add Resources/Info.plist Sources/QuiteEcho/MainWindow.swift pyproject.toml
git commit -m "Release v{new_version}"
```

## 6. Tag

```bash
git tag v{new_version}
```

## 7. Ask about push

Ask the user whether to push now. Explain that pushing will trigger the GitHub Actions workflow to build a DMG and create a GitHub Release.

If the user confirms:

```bash
git push && git push --tags
```
