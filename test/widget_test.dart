import 'package:codex_dashboard/main.dart';
import 'package:codex_dashboard/src/models/analytics.dart';
import 'package:codex_dashboard/src/ui/dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the dashboard from a local dataset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    final dataset = CodexDataset(
      prompts: [
        PromptRecord(sessionId: 'one', timestamp: now, characterCount: 42),
        PromptRecord(
          sessionId: 'older',
          timestamp: now.subtract(const Duration(days: 6)),
          characterCount: 24,
        ),
      ],
      turns: [
        TurnMetric(
          sessionId: 'one',
          timestamp: now,
          model: 'gpt-test',
          reasoningEffort: 'high',
          cwd: '/tmp/project',
          source: 'cli',
          status: 'completed',
          firstResponseMs: 1200,
          durationMs: 4200,
          inputTokens: 100,
          cachedInputTokens: 50,
          outputTokens: 20,
          reasoningTokens: 10,
          totalTokens: 120,
          toolCalls: 2,
          patchApplications: 1,
          webSearches: 0,
        ),
      ],
      loadedAt: now,
      codexRoot: '/tmp/.codex',
      sourceFileCount: 1,
      parsedFileCount: 1,
      reusedFileCount: 0,
      sourceBytes: 1024,
      warnings: const [],
    );

    await tester.pumpWidget(
      CodexDashboardApp(home: DashboardPage(initialDataset: dataset)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your Codex rhythm'), findsOneWidget);
    expect(find.text('Prompt activity'), findsOneWidget);
    expect(find.text('Reasoning mix'), findsOneWidget);
    expect(find.text('Source mix'), findsOneWidget);
    expect(find.text('Private by construction'), findsOneWidget);
    expect(find.text('gpt-test'), findsOneWidget);
    expect(find.text('1 day'), findsWidgets);
    expect(find.text('Custom'), findsWidgets);
    expect(
      find.text('Prompt concentration by weekday, 6am–10pm local time'),
      findsOneWidget,
    );
    expect(find.byTooltip('Mon 6a · 0 prompts'), findsOneWidget);
    expect(find.byTooltip('Mon 5a · 0 prompts'), findsNothing);
    expect(find.byTooltip('Mon 10p · 0 prompts'), findsNothing);

    final promptsMetric = tester.getRect(
      find.byKey(const ValueKey('metric-prompts')),
    );
    final completionMetric = tester.getRect(
      find.byKey(const ValueKey('metric-mean-completion')),
    );
    final promptActivity = tester.getRect(
      find.byKey(const ValueKey('prompt-activity-card')),
    );
    final modelMix = tester.getRect(
      find.byKey(const ValueKey('model-mix-card')),
    );
    final reasoningMix = tester.getRect(
      find.byKey(const ValueKey('reasoning-mix-card')),
    );
    expect(promptActivity.left, closeTo(promptsMetric.left, 0.1));
    expect(modelMix.left, closeTo(completionMetric.left, 0.1));
    expect(promptActivity.bottom, closeTo(reasoningMix.bottom, 0.1));

    await tester.tap(find.text('Custom').first);
    await tester.pumpAndSettle();
    expect(find.text('Custom period'), findsOneWidget);
    expect(find.text('Single day'), findsOneWidget);
    expect(find.text('Date range'), findsOneWidget);

    await tester.tap(find.text('Single day'));
    await tester.pumpAndSettle();
    expect(find.text('Choose one day'), findsOneWidget);
    expect(find.text('Use day'), findsOneWidget);

    await tester.tap(find.text('Use day'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('range-custom-selected')), findsOneWidget);

    await tester.tap(find.text('Custom').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date range'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a Codex activity window'), findsOneWidget);
    expect(find.text('Apply range'), findsOneWidget);
  });
}
