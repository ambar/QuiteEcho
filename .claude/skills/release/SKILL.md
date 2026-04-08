---
name: release
description: Bump version, commit, tag, and push to trigger the GitHub Actions release workflow. Supports beta pre-releases.
disable-model-invocation: true
argument-hint: "[beta] [patch|minor|major|x.y.z]"
---

Follow these steps to release a new version of QuiteEcho:

## 1. Ask release type if no arguments

If `$ARGUMENTS` is empty, ask the user:

```
Release type?
1. beta — pre-release (no version bump)
2. release — normal release (patch bump by default)
```

Wait for the user to answer before proceeding. Use their answer as the argument for the next steps.

## 2. Read current version

Read `Resources/Info.plist` and extract the current `CFBundleShortVersionString` value.

## 3. Determine release type

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

## 4. Generate changelog

Find the previous release tag:

```bash
git tag -l "v*" --sort=-v:refname | grep -v beta | head -1
```

Generate a list of commits since that tag:

```bash
git log {prev_tag}..HEAD --pretty=format:"%s" --no-merges
```

Classify each commit by its semantic meaning into these categories (judge by the full message, not just prefix):

- **Features** — new functionality, new support, additions (e.g. "Add ...", "Support ...", "Implement ...")
- **Bug Fixes** — fixes, corrections (e.g. "Fix ...", "Resolve ...", "Correct ...")
- **Other** — refactors, CI changes, docs, chores, style tweaks, etc.

Format the changelog with category headers. Omit empty categories:

```
### Features
- Add beta pre-release support and annotated tags

### Bug Fixes
- Fix AudioRecorder crash: use per-session AVAudioEngine

### Other
- Update release.yml
```

Show the formatted changelog to the user.

## 5. Confirm with user

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

## 6. Bump version (normal release only)

Skip this step for beta releases.

Run:

```bash
bash scripts/bump-version.sh {new_version}
```

This updates `Resources/Info.plist` and `pyproject.toml`.

## 7. Commit (normal release only)

Skip this step for beta releases.

```bash
git add Resources/Info.plist pyproject.toml
git commit -m "Release v{new_version}"
```

## 8. Tag

Create an **annotated** tag with the changelog as the message. Use `--cleanup=verbatim` to preserve `#` lines (git strips them as comments by default):

```bash
cat <<'EOF' > /tmp/tag-message.txt
{changelog}
EOF
git tag -a v{tag_version} -F /tmp/tag-message.txt --cleanup=verbatim
```

## 9. Ask about push

Ask the user whether to push now. Explain that pushing will trigger the GitHub Actions workflow to build a DMG and create a GitHub Release.

If the user confirms:

```bash
git push && git push --tags
```
