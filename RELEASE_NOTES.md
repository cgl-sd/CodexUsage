# CodexUsage v0.1.1

Patch release with UI polish and update-check improvements.

## Changes

- Fix daily rollover behavior so the daily usage view recomputes after midnight even when no new Codex log is written.
- Add in-app update checking from GitHub Releases.
- Show explicit update results for latest version, network failure, and newer version availability.
- Add a DMG download flow for newer releases.
- Refine the popover layout, account plan badge, spacing, and darker background.
- Keep usage scanning on a background task to avoid UI stalls.

## Installation

1. Download `CodexUsage.dmg`.
2. Open the DMG.
3. Drag `CodexUsage.app` into `Applications`.
4. Open CodexUsage from Applications.

If macOS says the developer cannot be verified, right-click `CodexUsage.app`, choose **Open**, then confirm **Open**.

## Artifacts

- `CodexUsage.dmg`
- `CodexUsage.zip`
