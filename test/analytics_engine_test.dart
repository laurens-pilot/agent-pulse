import 'package:codex_dashboard/src/analytics/analytics_engine.dart';
import 'package:codex_dashboard/src/models/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a local-time dashboard slice with comparison metrics', () {
    final now = DateTime(2026, 7, 15, 18);
    final prompts = <PromptRecord>[
      PromptRecord(
        sessionId: 'a',
        timestamp: DateTime(2026, 7, 15, 9).toUtc(),
        characterCount: 100,
      ),
      PromptRecord(
        sessionId: 'a',
        timestamp: DateTime(2026, 7, 14, 9).toUtc(),
        characterCount: 200,
      ),
      PromptRecord(
        sessionId: 'old',
        timestamp: DateTime(2026, 7, 7, 9).toUtc(),
        characterCount: 50,
      ),
    ];
    final turns = <TurnMetric>[
      _turn(prompts.first.timestamp, durationMs: 2000),
      _turn(prompts[1].timestamp, durationMs: 6000),
    ];
    final dataset = CodexDataset(
      prompts: prompts,
      turns: turns,
      loadedAt: now,
      codexRoot: '/tmp/.codex',
      sourceFileCount: 1,
      parsedFileCount: 1,
      reusedFileCount: 0,
      sourceBytes: 100,
      warnings: const [],
    );

    final result = const AnalyticsEngine().slice(
      dataset,
      DatePreset.sevenDays,
      now: now,
    );

    expect(result.promptCount, 2);
    expect(result.previousPromptCount, 1);
    expect(result.activeDays, 2);
    expect(result.sessions, 1);
    expect(result.averageCompletionMs, 4000);
    expect(result.medianCompletionMs, anyOf(2000, 6000));
    expect(result.totalTokens, 240);
    expect(result.dailyPrompts.length, 7);

    final oneDay = const AnalyticsEngine().slice(
      dataset,
      DatePreset.oneDay,
      now: now,
    );
    expect(oneDay.promptCount, 1);
    expect(oneDay.dailyPrompts, hasLength(1));

    final custom = const AnalyticsEngine().slice(
      dataset,
      DatePreset.custom,
      now: now,
      customRange: DashboardDateRange(
        start: DateTime(2026, 7, 7),
        end: DateTime(2026, 7, 7),
      ),
    );
    expect(custom.promptCount, 1);
    expect(custom.dailyPrompts, hasLength(1));
  });
}

TurnMetric _turn(DateTime timestamp, {required int durationMs}) => TurnMetric(
  sessionId: 'a',
  timestamp: timestamp,
  model: 'gpt-test',
  reasoningEffort: 'high',
  cwd: '/tmp/project',
  source: 'cli',
  status: 'completed',
  firstResponseMs: 1000,
  durationMs: durationMs,
  inputTokens: 100,
  cachedInputTokens: 40,
  outputTokens: 20,
  reasoningTokens: 10,
  totalTokens: 120,
  toolCalls: 1,
  patchApplications: 1,
  webSearches: 0,
);
