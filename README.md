# Codex Pulse

Codex Pulse is a private, local-first macOS dashboard for personal Codex usage.
It turns the files already stored in `~/.codex` into interactive prompt trends,
day/hour patterns, latency distributions, model and reasoning mix, workspace
activity, tokens, tool calls, patches, and streaks. The dashboard supports
today, 7-day, 30-day, 90-day, all-time, and custom date windows.

## Run it

```sh
flutter run -d macos
```

Or open the most recent debug build directly:

```sh
open "build/macos/Build/Products/Debug/Codex Pulse.app"
```

Build a release app with:

```sh
flutter build macos --release
```

## Data safety

- `~/.codex/history.jsonl` is the source of truth for prompts you explicitly
  sent.
- Matching session JSONL files provide model, timing, token, tool, patch, and
  workspace metadata.
- Codex Pulse opens those source files as read-only streams. It does not modify,
  move, migrate, or delete Codex data.
- The app writes a small derived cache only under its own macOS Application
  Support directory. The cache includes numeric metrics and source metadata,
  but never prompt text, response text, tool input, or tool output.
- The macOS app sandbox is intentionally disabled because this personal app
  needs to read `~/.codex` without a file picker. No network dependency is used
  by the dashboard.

See [docs/metrics.md](docs/metrics.md) for exact definitions and known limits.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build macos --debug
```
