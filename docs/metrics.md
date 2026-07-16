# Codex Pulse metric model

Codex Pulse is a local, personal monitoring dashboard. It reads Codex data and
stores only derived analytics in its own Application Support directory. It
never writes to `~/.codex` and never stores prompt or response text in its
cache.

## Source hierarchy

1. `~/.codex/history.jsonl` is authoritative for prompts explicitly sent by the
   user. This avoids counting developer instructions, restored context,
   subagent prompts, and other injected messages as personal prompts.
2. `~/.codex/sessions/**/rollout-*.jsonl` and
   `~/.codex/archived_sessions/rollout-*.jsonl` provide turn context and runtime
   events. Session events are joined to history by session id and prompt time.
3. The app's private cache records file size, modification time, and derived
   turn metrics so unchanged multi-gigabyte session logs are not rescanned.

## Headline metrics

All windows use local time. **1 day** means local midnight through now. Custom
ranges include both selected calendar dates; when the end date is today, it
stops at the current time. Every window except all-time compares against the
immediately preceding window of equal length.

- **Prompts**: history records in the selected local-time window.
- **Sessions**: distinct session ids represented by those prompts.
- **Active days**: local calendar days with at least one prompt.
- **Run time**: sum of completed/aborted task durations. Parallel tasks can
  overlap, so this is machine run time rather than elapsed wall-clock time.
- **First response**: time from a sent prompt to the first agent message for
  matched turns. This is not raw API time-to-first-token.
- **Mean completion**: arithmetic mean of completed task durations in the
  selected window. Median and p90 are displayed alongside it to show skew.
- **Completion time**: task duration reported by Codex, with event timestamp
  difference as a fallback.
- **Tokens**: per-turn token deltas derived from Codex's cumulative usage
  events. Input, cached input, output, and reasoning output are retained
  separately.
- **Completion rate**: completed tasks divided by completed plus aborted tasks.

## Diagnostic views

| View | Question | Form |
|---|---|---|
| Prompt activity | How has prompting changed across the selected period? | Daily line/area trend |
| Weekly rhythm | When during the working day do prompts happen? | 7 by 16 local-time heatmap, 6am–10pm |
| Model mix | Which models handle the work? | Ranked horizontal bars |
| Reasoning mix | Which reasoning-effort levels handle the work? | Ranked horizontal bars |
| Completion time | How variable is the wait for completed work? | Histogram |
| Workspaces | Which local projects receive the most prompts? | Ranked bars |
| Activity mix | How much tool, patch, and web activity happens? | Compact scorecard |

## Known limits

- Older Codex log versions may not emit every latency or token field. Coverage
  is shown in the dashboard and missing values are excluded from averages.
- Prompt timestamps are stored at one-second precision in `history.jsonl`.
- Prompt length is calculated in memory and cached only as a character count;
  prompt text is never persisted by this app.
- A task may contain a steering follow-up. Prompt counts remain accurate, while
  a single task duration is associated with only one matched turn.
