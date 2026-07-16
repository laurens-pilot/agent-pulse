enum DatePreset {
  oneDay('1 day', 1),
  sevenDays('7 days', 7),
  thirtyDays('30 days', 30),
  ninetyDays('90 days', 90),
  allTime('All time', null),
  custom('Custom', null);

  const DatePreset(this.label, this.days);

  final String label;
  final int? days;
}

class DashboardDateRange {
  const DashboardDateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class PromptRecord {
  const PromptRecord({
    required this.sessionId,
    required this.timestamp,
    required this.characterCount,
  });

  final String sessionId;
  final DateTime timestamp;
  final int characterCount;
}

class TurnMetric {
  const TurnMetric({
    required this.sessionId,
    required this.timestamp,
    required this.model,
    required this.reasoningEffort,
    required this.cwd,
    required this.source,
    required this.status,
    required this.firstResponseMs,
    required this.durationMs,
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.outputTokens,
    required this.reasoningTokens,
    required this.totalTokens,
    required this.toolCalls,
    required this.patchApplications,
    required this.webSearches,
  });

  final String sessionId;
  final DateTime timestamp;
  final String? model;
  final String? reasoningEffort;
  final String? cwd;
  final String? source;
  final String status;
  final int? firstResponseMs;
  final int? durationMs;
  final int? inputTokens;
  final int? cachedInputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? totalTokens;
  final int toolCalls;
  final int patchApplications;
  final int webSearches;

  bool get isCompleted => status == 'completed';
  bool get isAborted => status == 'aborted';

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'model': model,
    'reasoningEffort': reasoningEffort,
    'cwd': cwd,
    'source': source,
    'status': status,
    'firstResponseMs': firstResponseMs,
    'durationMs': durationMs,
    'inputTokens': inputTokens,
    'cachedInputTokens': cachedInputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'totalTokens': totalTokens,
    'toolCalls': toolCalls,
    'patchApplications': patchApplications,
    'webSearches': webSearches,
  };

  factory TurnMetric.fromJson(Map<String, Object?> json) => TurnMetric(
    sessionId: json['sessionId']! as String,
    timestamp: DateTime.parse(json['timestamp']! as String),
    model: json['model'] as String?,
    reasoningEffort: json['reasoningEffort'] as String?,
    cwd: json['cwd'] as String?,
    source: json['source'] as String?,
    status: json['status']! as String,
    firstResponseMs: (json['firstResponseMs'] as num?)?.toInt(),
    durationMs: (json['durationMs'] as num?)?.toInt(),
    inputTokens: (json['inputTokens'] as num?)?.toInt(),
    cachedInputTokens: (json['cachedInputTokens'] as num?)?.toInt(),
    outputTokens: (json['outputTokens'] as num?)?.toInt(),
    reasoningTokens: (json['reasoningTokens'] as num?)?.toInt(),
    totalTokens: (json['totalTokens'] as num?)?.toInt(),
    toolCalls: (json['toolCalls'] as num?)?.toInt() ?? 0,
    patchApplications: (json['patchApplications'] as num?)?.toInt() ?? 0,
    webSearches: (json['webSearches'] as num?)?.toInt() ?? 0,
  );
}

class CodexDataset {
  const CodexDataset({
    required this.prompts,
    required this.turns,
    required this.loadedAt,
    required this.codexRoot,
    required this.sourceFileCount,
    required this.parsedFileCount,
    required this.reusedFileCount,
    required this.sourceBytes,
    required this.warnings,
  });

  final List<PromptRecord> prompts;
  final List<TurnMetric> turns;
  final DateTime loadedAt;
  final String codexRoot;
  final int sourceFileCount;
  final int parsedFileCount;
  final int reusedFileCount;
  final int sourceBytes;
  final List<String> warnings;
}

class DayBucket {
  const DayBucket(this.day, this.value);

  final DateTime day;
  final int value;
}

class CategoryMetric {
  const CategoryMetric(this.label, this.value, {this.secondaryValue});

  final String label;
  final int value;
  final int? secondaryValue;
}

class LatencyBucket {
  const LatencyBucket(this.label, this.count);

  final String label;
  final int count;
}

class DashboardSlice {
  const DashboardSlice({
    required this.preset,
    required this.start,
    required this.end,
    required this.prompts,
    required this.turns,
    required this.previousPromptCount,
    required this.activeDays,
    required this.sessions,
    required this.currentStreak,
    required this.runTimeMs,
    required this.averageFirstResponseMs,
    required this.averageCompletionMs,
    required this.medianCompletionMs,
    required this.p90CompletionMs,
    required this.completionRate,
    required this.totalTokens,
    required this.cachedInputTokens,
    required this.averagePromptCharacters,
    required this.busiestHour,
    required this.dailyPrompts,
    required this.hourlyHeatmap,
    required this.modelMix,
    required this.reasoningMix,
    required this.workspaceMix,
    required this.sourceMix,
    required this.latencyDistribution,
    required this.toolCalls,
    required this.patchApplications,
    required this.webSearches,
    required this.latencyCoverage,
    required this.tokenCoverage,
  });

  final DatePreset preset;
  final DateTime start;
  final DateTime end;
  final List<PromptRecord> prompts;
  final List<TurnMetric> turns;
  final int previousPromptCount;
  final int activeDays;
  final int sessions;
  final int currentStreak;
  final int runTimeMs;
  final int? averageFirstResponseMs;
  final int? averageCompletionMs;
  final int? medianCompletionMs;
  final int? p90CompletionMs;
  final double? completionRate;
  final int totalTokens;
  final int cachedInputTokens;
  final int averagePromptCharacters;
  final int? busiestHour;
  final List<DayBucket> dailyPrompts;
  final List<List<int>> hourlyHeatmap;
  final List<CategoryMetric> modelMix;
  final List<CategoryMetric> reasoningMix;
  final List<CategoryMetric> workspaceMix;
  final List<CategoryMetric> sourceMix;
  final List<LatencyBucket> latencyDistribution;
  final int toolCalls;
  final int patchApplications;
  final int webSearches;
  final double latencyCoverage;
  final double tokenCoverage;

  int get promptCount => prompts.length;

  double? get promptChange {
    if (previousPromptCount == 0) return null;
    return (promptCount - previousPromptCount) / previousPromptCount;
  }
}
