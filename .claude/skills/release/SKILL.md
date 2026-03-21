---
name: release
description: Bump version, commit, tag, and push to trigger the GitHub Actions release workflow. Supports beta pre-releases.
disable-model-invocation: true
argument-hint: "[beta] [patch|minor|major|x.y.z]"
---

Follow these steps to release a new version of QuiteEcho:

## 1. Read current version

Read `pyproject.toml` and extract the current `version = "..."` value.

## 2. Determine release type

Look at `$ARGUMENTS`:

**Pre-release (beta):** If the arguments contain `beta`:
- Determine the base version from the remaining argument (patch/minor/major/explicit), same rules as normal release below.
- Find the latest existing beta tag for that base version: `git tag -l "v{base}-beta.*" | sort -V | tail -1`
- If none exists, use `-beta.1`. Otherwise increment the beta number (e.g. `-beta.1` → `-beta.2`).
- The final tag is `v{base}-beta.{N}`. Do NOT bump the version in source files — beta tags are metadata only.

**Normal release:** If no `beta` in arguments:
- **No argument or `patch`**: bump the patch component (e.g. `0.1.0` → `0.1.1`)
- **`minor`**: bump minor, reset patch (e.g. `0.1.3` → `0.2.0`)
- **`major`**: bump major, reset minor and patch (e.g. `0.1.3` → `1.0.0`)
- **Explicit semver (e.g. `1.0.0`)**: use it as-is

## 3. Generate changelog

Find the previous release tag:

```bash
git tag -l "v*" --sort=-v:refname | grep -v beta | head -1
```

Generate a changelog of commits since that tag:

```bash
git log {prev_tag}..HEAD --pretty=format:"- %s" --no-merges
```

Show the changelog to the user.

## 4. Confirm with user

For **normal release**, show:

```
Release: v{current} → v{new}

Changelog:
{changelog}
```

For **beta release**, show:

```
Pre-release: v{new_tag}

Changelog:
{changelog}
```

Wait for the user to confirm before proceeding. Do NOT continue without confirmation.

## 5. Bump version (normal release only)

Skip this step for beta releases.

Run:

```bash
bash scripts/bump-version.sh {new_version}
```

This updates `Resources/Info.plist`, `Sources/QuiteEcho/MainWindow.swift`, and `pyproject.toml`.

## 6. Commit (normal release only)

Skip this step for beta releases.

```bash
git add Resources/Info.plist Sources/QuiteEcho/MainWindow.swift pyproject.toml
git commit -m "Release v{new_version}"
```

## 7. Tag

Create an **annotated** tag with the changelog as the message. Use a heredoc to pass the message:

```bash
git tag -a v{tag_version} -m "$(cat <<'EOF'
{changelog}
EOF
)"
```

## 8. Ask about push

Ask the user whether to push now. Explain that pushing will trigger the GitHub Actions workflow to build a DMG and create a GitHub Release.

If the user confirms:

```bash
git push && git push --tags
```
