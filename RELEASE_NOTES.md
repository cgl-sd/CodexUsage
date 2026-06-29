# CodexUsage Release Notes

## v0.1.4 - 2026-06-29

Energy usage optimization for background log monitoring.

### Changes

- Track per-file scan positions for local Codex jsonl logs.
- Keep startup and manual refresh as full scans for correctness.
- Change background refresh to read only newly appended log bytes instead of rescanning all historical session logs.
- Fall back to a full rescan if a log file is removed or truncated.
- Show the refresh completion time in the popover footer.
- Keep the refresh icon spinning until the active refresh finishes.

## v0.1.3 - 2026-06-25

Usage display refinement for cached token accounting.

### Changes

- Add a "without cache" daily usage value in the main popover.
- Keep daily goal progress based on total tokens, including cached input tokens.
- Compute the without-cache estimate as `total_tokens - cached_input_tokens`.
- Make token count parsing more tolerant of missing fields in local Codex logs, treating missing token counters as zero.

## v0.1.2 - 2026-06-25

Settings and documentation polish for the next version.

### Changes

- Compact the Settings window from `420 x 420` to `360 x 368`.
- Remove the account ID row from the Local Account section.
- Move the local refresh action into the Local Account header and tighten the Local Account and Daily Goal sections.
- Show Data Source as two concise local path rows instead of one long paragraph.
- Resolve Data Source paths from the current macOS user's home directory:
  - Usage and quota data: `$HOME/.codex/sessions`
  - Account metadata: `$HOME/.codex/auth.json`
- Render local paths as verbatim text to avoid accidental Markdown-style formatting, such as strikethrough around `~`.
- Improve update checking by resolving the GitHub Releases `latest` redirect instead of relying on the GitHub API, reducing false failures caused by API rate limits.
- Add bilingual README navigation with English and Simplified Chinese documentation.

### Notes

- Account IDs, usernames, and absolute local paths are not hardcoded.
- The app reads data from each user's own local Codex directory on the Mac where it is running.

## v0.1.1

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
