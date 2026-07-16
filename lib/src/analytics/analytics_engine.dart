import 'dart:math' as math;

import '../models/analytics.dart';

class AnalyticsEngine {
  const AnalyticsEngine();

  DashboardSlice slice(
    CodexDataset dataset,
    DatePreset preset, {
    DateTime? now,
    DashboardDateRange? customRange,
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final earliest = dataset.prompts.isEmpty
        ? _day(localNow)
        : _day(
            dataset.prompts
                .map((prompt) => prompt.timestamp.toLocal())
                .reduce((a, b) => a.isBefore(b) ? a : b),
          );
    final effectiveCustomRange = preset == DatePreset.custom
        ? customRange ?? DashboardDateRange(start: localNow, end: localNow)
        : null;
    final start = effectiveCustomRange != null
        ? _day(effectiveCustomRange.start.toLocal())
        : preset == DatePreset.allTime
        ? earliest
        : _day(localNow).subtract(Duration(days: preset.days! - 1));
    final requestedEnd = effectiveCustomRange == null
        ? localNow
        : _endOfDay(effectiveCustomRange.end.toLocal());
    final end = requestedEnd.isAfter(localNow) ? localNow : requestedEnd;
    final prompts = dataset.prompts
        .where((prompt) => _inside(prompt.timestamp.toLocal(), start, end))
        .toList(growable: false);
    final turns = dataset.turns
        .where((turn) => _inside(turn.timestamp.toLocal(), start, end))
        .toList(growable: false);

    final previousPromptCount = preset == DatePreset.allTime
        ? 0
        : _previousPromptCount(dataset.prompts, start, end);
    final activeDates = prompts
        .map((prompt) => _day(prompt.timestamp.toLocal()))
        .toSet();
    final durations =
        turns
            .where((turn) => turn.isCompleted && turn.durationMs != null)
            .map((turn) => turn.durationMs!)
            .toList()
          ..sort();
    final firstResponses = turns
        .where((turn) => turn.firstResponseMs != null)
        .map((turn) => turn.firstResponseMs!)
        .toList(growable: false);
    final completed = turns.where((turn) => turn.isCompleted).length;
    final aborted = turns.where((turn) => turn.isAborted).length;
    final tokenTurns = turns.where((turn) => turn.totalTokens != null).toList();
    final totalTokens = tokenTurns.fold<int>(
      0,
      (sum, turn) => sum + turn.totalTokens!,
    );
    final cachedTokens = tokenTurns.fold<int>(
      0,
      (sum, turn) => sum + (turn.cachedInputTokens ?? 0),
    );

    return DashboardSlice(
      preset: preset,
      start: start,
      end: end,
      prompts: prompts,
      turns: turns,
      previousPromptCount: previousPromptCount,
      activeDays: activeDates.length,
      sessions: prompts.map((prompt) => prompt.sessionId).toSet().length,
      currentStreak: _currentStreak(activeDates, localNow),
      runTimeMs: turns.fold<int>(
        0,
        (sum, turn) => sum + (turn.durationMs ?? 0),
      ),
      averageFirstResponseMs: firstResponses.isEmpty
          ? null
          : firstResponses.reduce((a, b) => a + b) ~/ firstResponses.length,
      averageCompletionMs: durations.isEmpty
          ? null
          : durations.reduce((a, b) => a + b) ~/ durations.length,
      medianCompletionMs: _percentile(durations, 0.5),
      p90CompletionMs: _percentile(durations, 0.9),
      completionRate: completed + aborted == 0
          ? null
          : completed / (completed + aborted),
      totalTokens: totalTokens,
      cachedInputTokens: cachedTokens,
      averagePromptCharacters: prompts.isEmpty
          ? 0
          : prompts.fold<int>(0, (sum, p) => sum + p.characterCount) ~/
                prompts.length,
      busiestHour: _busiestHour(prompts),
      dailyPrompts: _dailyBuckets(prompts, start, end),
      hourlyHeatmap: _heatmap(prompts),
      modelMix: _group(turns, (turn) => turn.model ?? 'Unknown'),
      reasoningMix: _group(
        turns,
        (turn) => _displayReasoning(turn.reasoningEffort),
      ),
      workspaceMix: _group(turns, (turn) => _workspace(turn.cwd)),
      sourceMix: _group(turns, (turn) => _source(turn.source)),
      latencyDistribution: _latencyBuckets(durations),
      toolCalls: turns.fold<int>(0, (sum, turn) => sum + turn.toolCalls),
      patchApplications: turns.fold<int>(
        0,
        (sum, turn) => sum + turn.patchApplications,
      ),
      webSearches: turns.fold<int>(0, (sum, turn) => sum + turn.webSearches),
      latencyCoverage: prompts.isEmpty
          ? 0
          : math.min(1, durations.length / prompts.length),
      tokenCoverage: prompts.isEmpty
          ? 0
          : math.min(1, tokenTurns.length / prompts.length),
    );
  }

  int _previousPromptCount(
    List<PromptRecord> allPrompts,
    DateTime start,
    DateTime end,
  ) {
    final period = end.difference(start) + const Duration(microseconds: 1);
    final previousStart = start.subtract(period);
    return allPrompts.where((prompt) {
      final local = prompt.timestamp.toLocal();
      return !local.isBefore(previousStart) && local.isBefore(start);
    }).length;
  }

  List<DayBucket> _dailyBuckets(
    List<PromptRecord> prompts,
    DateTime start,
    DateTime end,
  ) {
    final counts = <DateTime, int>{};
    for (final prompt in prompts) {
      final day = _day(prompt.timestamp.toLocal());
      counts[day] = (counts[day] ?? 0) + 1;
    }
    final output = <DayBucket>[];
    var cursor = _day(start);
    final finalDay = _day(end);
    while (!cursor.isAfter(finalDay)) {
      output.add(DayBucket(cursor, counts[cursor] ?? 0));
      cursor = cursor.add(const Duration(days: 1));
    }
    return output;
  }

  List<List<int>> _heatmap(List<PromptRecord> prompts) {
    final output = List.generate(7, (_) => List.filled(24, 0));
    for (final prompt in prompts) {
      final local = prompt.timestamp.toLocal();
      output[local.weekday - 1][local.hour] += 1;
    }
    return output;
  }

  List<CategoryMetric> _group(
    List<TurnMetric> turns,
    String Function(TurnMetric turn) label,
  ) {
    final counts = <String, int>{};
    final tokens = <String, int>{};
    for (final turn in turns) {
      final key = label(turn);
      counts[key] = (counts[key] ?? 0) + 1;
      tokens[key] = (tokens[key] ?? 0) + (turn.totalTokens ?? 0);
    }
    final output =
        counts.entries
            .map(
              (entry) => CategoryMetric(
                entry.key,
                entry.value,
                secondaryValue: tokens[entry.key],
              ),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return output;
  }

  List<LatencyBucket> _latencyBuckets(List<int> durations) {
    final counts = List.filled(5, 0);
    for (final duration in durations) {
      final seconds = duration / 1000;
      if (seconds < 30) {
        counts[0] += 1;
      } else if (seconds < 60) {
        counts[1] += 1;
      } else if (seconds < 180) {
        counts[2] += 1;
      } else if (seconds < 600) {
        counts[3] += 1;
      } else {
        counts[4] += 1;
      }
    }
    const labels = <String>['<30s', '30–60s', '1–3m', '3–10m', '10m+'];
    return List.generate(
      labels.length,
      (index) => LatencyBucket(labels[index], counts[index]),
    );
  }

  int _currentStreak(Set<DateTime> activeDates, DateTime now) {
    if (activeDates.isEmpty) return 0;
    var cursor = _day(now);
    if (!activeDates.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!activeDates.contains(cursor)) return 0;
    }
    var streak = 0;
    while (activeDates.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int? _busiestHour(List<PromptRecord> prompts) {
    if (prompts.isEmpty) return null;
    final hours = List.filled(24, 0);
    for (final prompt in prompts) {
      hours[prompt.timestamp.toLocal().hour] += 1;
    }
    var best = 0;
    for (var index = 1; index < hours.length; index += 1) {
      if (hours[index] > hours[best]) best = index;
    }
    return best;
  }

  int? _percentile(List<int> values, double percentile) {
    if (values.isEmpty) return null;
    final index = ((values.length - 1) * percentile).round();
    return values[index];
  }

  String _workspace(String? cwd) {
    if (cwd == null || cwd.isEmpty) return 'Unknown';
    final normalized = cwd.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? cwd : parts.last;
  }

  String _source(String? source) {
    if (source == null || source.isEmpty) return 'Unknown';
    final lower = source.toLowerCase();
    if (lower.contains('vscode')) return 'VS Code';
    if (lower == 'cli') return 'CLI';
    if (lower.contains('subagent')) return 'Subagent';
    if (lower.contains('exec')) return 'Exec';
    return source.length > 24 ? 'Other' : source;
  }

  String _displayReasoning(String? effort) {
    if (effort == null || effort.isEmpty) return 'Unspecified';
    return switch (effort.toLowerCase()) {
      'xhigh' => 'Extra high',
      'high' => 'High',
      'medium' => 'Medium',
      'low' => 'Low',
      _ => effort,
    };
  }

  bool _inside(DateTime value, DateTime start, DateTime end) =>
      !value.isBefore(start) && !value.isAfter(end);

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) => _day(
    value,
  ).add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
}
