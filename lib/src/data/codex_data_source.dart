import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/analytics.dart';

class CodexFolderAccessException implements Exception {
  const CodexFolderAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CodexRootAccess {
  const CodexRootAccess();

  static const channelName = 'com.laurens.codexDashboard/codexRootAccess';
  static const methodName = 'resolveOrRequestCodexRoot';
  static const _channel = MethodChannel(channelName);

  Future<String> resolveOrRequest() async {
    try {
      final root = await _channel.invokeMethod<String>(methodName);
      if (root == null || root.isEmpty) {
        throw const CodexFolderAccessException(
          'Codex folder access is required. Select your ~/.codex folder to continue.',
        );
      }
      return root;
    } on PlatformException catch (error) {
      throw CodexFolderAccessException(
        error.message ??
            'Read-only access to the selected Codex folder could not be granted.',
      );
    } on MissingPluginException {
      throw const CodexFolderAccessException(
        'The macOS Codex folder access service is unavailable.',
      );
    }
  }
}

class CodexDataSource {
  const CodexDataSource({
    this.codexRootOverride,
    this.cachePathOverride,
    this.rootAccess = const CodexRootAccess(),
  });

  final String? codexRootOverride;
  final String? cachePathOverride;
  final CodexRootAccess rootAccess;

  Future<CodexDataset> load({bool forceRefresh = false}) async {
    final root = codexRootOverride ?? await rootAccess.resolveOrRequest();
    final cachePath = cachePathOverride ?? await _defaultCachePath();
    return Isolate.run(
      () => _loadDataset(root, cachePath, forceRefresh: forceRefresh),
      debugName: 'codex-pulse-indexer',
    );
  }

  Future<String> _defaultCachePath() async {
    final support = await getApplicationSupportDirectory();
    return '${support.path}/Codex Pulse/analytics-cache-v4.json';
  }
}

Future<CodexDataset> _loadDataset(
  String rootPath,
  String cachePath, {
  required bool forceRefresh,
}) async {
  final root = Directory(rootPath);
  final historyFile = File('$rootPath/history.jsonl');
  if (!await root.exists() || !await historyFile.exists()) {
    throw FileSystemException(
      'Codex history was not found. Expected a readable history.jsonl file.',
      rootPath,
    );
  }

  final warnings = <String>[];
  final prompts = await _readHistory(historyFile, warnings);
  final historyBySession = <String, List<PromptRecord>>{};
  for (final prompt in prompts) {
    historyBySession.putIfAbsent(prompt.sessionId, () => []).add(prompt);
  }

  final existingCache = forceRefresh
      ? <String, _CachedFile>{}
      : await _readCache(cachePath, warnings);
  final sessionFiles = await _findSessionFiles(
    rootPath,
    historyBySession.keys.toSet(),
  );
  final nextCache = <String, _CachedFile>{};
  final turns = <TurnMetric>[];
  var parsedFileCount = 0;
  var reusedFileCount = 0;
  var sourceBytes = 0;

  for (final entry in sessionFiles.entries) {
    final file = entry.value;
    FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException {
      warnings.add(
        'A session changed while it was being indexed. Refresh to retry.',
      );
      continue;
    }
    sourceBytes += stat.size;
    final cached = existingCache[file.path];
    if (cached != null &&
        cached.size == stat.size &&
        cached.modifiedMs == stat.modified.millisecondsSinceEpoch) {
      turns.addAll(cached.turns);
      nextCache[file.path] = cached;
      reusedFileCount += 1;
      continue;
    }

    try {
      final parsed = await _parseSession(
        file,
        entry.key,
        historyBySession[entry.key]!,
      );
      turns.addAll(parsed);
      nextCache[file.path] = _CachedFile(
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
        turns: parsed,
      );
      parsedFileCount += 1;
    } on FileSystemException {
      warnings.add(
        'A session could not be read. Its prompts are still counted.',
      );
    }
  }

  turns.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  prompts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  await _writeCache(cachePath, nextCache, warnings);

  final missingSessions = historyBySession.length - sessionFiles.length;
  if (missingSessions > 0) {
    warnings.add(
      '$missingSessions prompt session${missingSessions == 1 ? '' : 's'} '
      'had no local rollout file; prompt counts remain available.',
    );
  }

  return CodexDataset(
    prompts: prompts,
    turns: turns,
    loadedAt: DateTime.now(),
    codexRoot: rootPath,
    sourceFileCount: sessionFiles.length,
    parsedFileCount: parsedFileCount,
    reusedFileCount: reusedFileCount,
    sourceBytes: sourceBytes,
    warnings: warnings.toSet().toList(growable: false),
  );
}

Future<List<PromptRecord>> _readHistory(
  File historyFile,
  List<String> warnings,
) async {
  final prompts = <PromptRecord>[];
  var invalidLines = 0;
  await for (final line
      in historyFile
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (line.isEmpty) continue;
    try {
      final json = jsonDecode(line) as Map<String, Object?>;
      final sessionId = json['session_id'] as String?;
      final timestamp = (json['ts'] as num?)?.toInt();
      final text = json['text'] as String?;
      if (sessionId == null || timestamp == null) {
        invalidLines += 1;
        continue;
      }
      prompts.add(
        PromptRecord(
          sessionId: sessionId,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            timestamp * 1000,
            isUtc: true,
          ),
          characterCount: text?.length ?? 0,
        ),
      );
    } on FormatException {
      invalidLines += 1;
    } on TypeError {
      invalidLines += 1;
    }
  }
  if (invalidLines > 0) {
    warnings.add('$invalidLines malformed history records were skipped.');
  }
  return prompts;
}

Future<Map<String, File>> _findSessionFiles(
  String rootPath,
  Set<String> wantedSessionIds,
) async {
  final result = <String, File>{};
  final locations = <Directory>[
    Directory('$rootPath/sessions'),
    Directory('$rootPath/archived_sessions'),
  ];
  final idPattern = RegExp(
    r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$',
  );
  for (final location in locations) {
    if (!await location.exists()) continue;
    await for (final entity in location.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final match = idPattern.firstMatch(entity.path);
      final sessionId = match?.group(1);
      if (sessionId != null && wantedSessionIds.contains(sessionId)) {
        result.putIfAbsent(sessionId, () => entity);
      }
    }
  }
  return result;
}

Future<List<TurnMetric>> _parseSession(
  File file,
  String sessionId,
  List<PromptRecord> manualPrompts,
) async {
  final manualBySecond = <int, PromptRecord>{
    for (final prompt in manualPrompts)
      prompt.timestamp.millisecondsSinceEpoch ~/ 1000: prompt,
  };
  final claimedSeconds = <int>{};
  final turns = <TurnMetric>[];
  String? cwd;
  String? source;
  String? currentModel;
  String? currentEffort;
  DateTime? pendingTaskStart;
  _TokenSnapshot? latestTokens;
  _TokenSnapshot? pendingTokenBaseline;
  _TurnBuilder? active;

  void finishActive(
    String status,
    DateTime timestamp,
    Map<String, Object?> payload,
  ) {
    final builder = active;
    if (builder == null) return;
    builder.status = status;
    builder.durationMs =
        _int(payload['duration_ms']) ??
        timestamp
            .difference(builder.taskStartedAt ?? builder.timestamp)
            .inMilliseconds;
    builder.firstResponseMs ??= _int(payload['time_to_first_token_ms']);
    turns.add(builder.build());
    active = null;
    pendingTaskStart = null;
    pendingTokenBaseline = null;
  }

  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (line.isEmpty) continue;
    Map<String, Object?> record;
    try {
      record = jsonDecode(line) as Map<String, Object?>;
    } on FormatException {
      continue;
    } on TypeError {
      continue;
    }
    final type = record['type'] as String?;
    final timestampText = record['timestamp'] as String?;
    final timestamp = timestampText == null
        ? null
        : DateTime.tryParse(timestampText)?.toUtc();
    final rawPayload = record['payload'];
    final payload = rawPayload is Map
        ? rawPayload.cast<String, Object?>()
        : <String, Object?>{};
    final payloadType = payload['type'] as String?;

    if (type == 'session_meta') {
      cwd = payload['cwd'] as String?;
      final rawSource = payload['source'];
      source = rawSource is String
          ? rawSource
          : rawSource == null
          ? null
          : jsonEncode(rawSource);
      continue;
    }

    if (type == 'turn_context') {
      currentModel = payload['model'] as String? ?? currentModel;
      currentEffort = payload['effort'] as String? ?? currentEffort;
      active?.model ??= currentModel;
      active?.reasoningEffort ??= currentEffort;
      continue;
    }

    if (type == 'event_msg' && payloadType == 'task_started') {
      if (active != null) {
        turns.add(active!.build());
        active = null;
      }
      pendingTaskStart = timestamp;
      pendingTokenBaseline = latestTokens;
      continue;
    }

    if (type == 'event_msg' &&
        payloadType == 'user_message' &&
        timestamp != null) {
      final second = timestamp.millisecondsSinceEpoch ~/ 1000;
      final manual = _nearestManualPrompt(
        manualBySecond,
        claimedSeconds,
        second,
      );
      if (manual != null) {
        if (active != null) turns.add(active!.build());
        claimedSeconds.add(manual.timestamp.millisecondsSinceEpoch ~/ 1000);
        active = _TurnBuilder(
          sessionId: sessionId,
          timestamp: manual.timestamp,
          taskStartedAt: pendingTaskStart,
          model: currentModel,
          reasoningEffort: currentEffort,
          cwd: cwd,
          source: source,
          tokenBaseline: pendingTokenBaseline ?? latestTokens,
        );
      }
      continue;
    }

    if (type == 'event_msg' && payloadType == 'token_count') {
      final info = payload['info'];
      if (info is Map) {
        final usage = info['total_token_usage'];
        if (usage is Map) {
          final snapshot = _TokenSnapshot.fromJson(
            usage.cast<String, Object?>(),
          );
          latestTokens = snapshot;
          active?.updateTokens(snapshot);
        }
      }
      continue;
    }

    if (active == null || timestamp == null) continue;

    if (type == 'event_msg' && payloadType == 'agent_message') {
      active!.firstResponseMs ??= timestamp
          .difference(active!.timestamp)
          .inMilliseconds;
    } else if (type == 'response_item' &&
        payloadType == 'message' &&
        payload['role'] == 'assistant') {
      active!.firstResponseMs ??= timestamp
          .difference(active!.timestamp)
          .inMilliseconds;
    } else if (type == 'response_item' &&
        const <String>{
          'function_call',
          'custom_tool_call',
          'mcp_tool_call',
          'tool_search_call',
        }.contains(payloadType)) {
      active!.toolCalls += 1;
    } else if (type == 'event_msg' && payloadType == 'patch_apply_end') {
      active!.patchApplications += 1;
    } else if (type == 'event_msg' && payloadType == 'web_search_end') {
      active!.webSearches += 1;
    } else if (type == 'event_msg' && payloadType == 'task_complete') {
      finishActive('completed', timestamp, payload);
    } else if (type == 'event_msg' && payloadType == 'turn_aborted') {
      finishActive('aborted', timestamp, payload);
    }
  }

  if (active != null) turns.add(active!.build());
  return turns;
}

PromptRecord? _nearestManualPrompt(
  Map<int, PromptRecord> bySecond,
  Set<int> claimed,
  int eventSecond,
) {
  for (final offset in const <int>[0, -1, 1, -2, 2]) {
    final candidateSecond = eventSecond + offset;
    if (!claimed.contains(candidateSecond) &&
        bySecond.containsKey(candidateSecond)) {
      return bySecond[candidateSecond];
    }
  }
  return null;
}

int? _int(Object? value) => (value as num?)?.toInt();

class _TurnBuilder {
  _TurnBuilder({
    required this.sessionId,
    required this.timestamp,
    required this.taskStartedAt,
    required this.model,
    required this.reasoningEffort,
    required this.cwd,
    required this.source,
    required this.tokenBaseline,
  });

  final String sessionId;
  final DateTime timestamp;
  final DateTime? taskStartedAt;
  String? model;
  String? reasoningEffort;
  final String? cwd;
  final String? source;
  final _TokenSnapshot? tokenBaseline;
  String status = 'unknown';
  int? firstResponseMs;
  int? durationMs;
  int? inputTokens;
  int? cachedInputTokens;
  int? outputTokens;
  int? reasoningTokens;
  int? totalTokens;
  int toolCalls = 0;
  int patchApplications = 0;
  int webSearches = 0;

  void updateTokens(_TokenSnapshot usage) {
    inputTokens = _tokenDelta(usage.input, tokenBaseline?.input);
    cachedInputTokens = _tokenDelta(
      usage.cachedInput,
      tokenBaseline?.cachedInput,
    );
    outputTokens = _tokenDelta(usage.output, tokenBaseline?.output);
    reasoningTokens = _tokenDelta(usage.reasoning, tokenBaseline?.reasoning);
    totalTokens = _tokenDelta(usage.total, tokenBaseline?.total);
  }

  TurnMetric build() => TurnMetric(
    sessionId: sessionId,
    timestamp: timestamp,
    model: model,
    reasoningEffort: reasoningEffort,
    cwd: cwd,
    source: source,
    status: status,
    firstResponseMs: firstResponseMs,
    durationMs: durationMs,
    inputTokens: inputTokens,
    cachedInputTokens: cachedInputTokens,
    outputTokens: outputTokens,
    reasoningTokens: reasoningTokens,
    totalTokens: totalTokens,
    toolCalls: toolCalls,
    patchApplications: patchApplications,
    webSearches: webSearches,
  );
}

class _TokenSnapshot {
  const _TokenSnapshot({
    required this.input,
    required this.cachedInput,
    required this.output,
    required this.reasoning,
    required this.total,
  });

  final int? input;
  final int? cachedInput;
  final int? output;
  final int? reasoning;
  final int? total;

  factory _TokenSnapshot.fromJson(Map<String, Object?> json) => _TokenSnapshot(
    input: _int(json['input_tokens']),
    cachedInput: _int(json['cached_input_tokens']),
    output: _int(json['output_tokens']),
    reasoning: _int(json['reasoning_output_tokens']),
    total: _int(json['total_tokens']),
  );
}

int? _tokenDelta(int? current, int? baseline) {
  if (current == null) return null;
  if (baseline == null || current < baseline) return current;
  return current - baseline;
}

class _CachedFile {
  const _CachedFile({
    required this.size,
    required this.modifiedMs,
    required this.turns,
  });

  final int size;
  final int modifiedMs;
  final List<TurnMetric> turns;

  Map<String, Object?> toJson() => <String, Object?>{
    'size': size,
    'modifiedMs': modifiedMs,
    'turns': turns.map((turn) => turn.toJson()).toList(growable: false),
  };

  factory _CachedFile.fromJson(Map<String, Object?> json) => _CachedFile(
    size: (json['size'] as num).toInt(),
    modifiedMs: (json['modifiedMs'] as num).toInt(),
    turns: (json['turns'] as List<Object?>? ?? const <Object?>[])
        .map(
          (turn) => TurnMetric.fromJson((turn! as Map).cast<String, Object?>()),
        )
        .toList(growable: false),
  );
}

Future<Map<String, _CachedFile>> _readCache(
  String cachePath,
  List<String> warnings,
) async {
  final file = File(cachePath);
  if (!await file.exists()) return <String, _CachedFile>{};
  try {
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    if (decoded['version'] != 4) return <String, _CachedFile>{};
    final files = (decoded['files']! as Map).cast<String, Object?>();
    return files.map(
      (path, value) => MapEntry(
        path,
        _CachedFile.fromJson((value! as Map).cast<String, Object?>()),
      ),
    );
  } on Object {
    warnings.add('The analytics cache was rebuilt because it was unreadable.');
    return <String, _CachedFile>{};
  }
}

Future<void> _writeCache(
  String cachePath,
  Map<String, _CachedFile> cache,
  List<String> warnings,
) async {
  final file = File(cachePath);
  final temporary = File('$cachePath.tmp');
  try {
    await file.parent.create(recursive: true);
    final contents = jsonEncode(<String, Object?>{
      'version': 4,
      'containsChatText': false,
      'files': cache.map((path, entry) => MapEntry(path, entry.toJson())),
    });
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(cachePath);
  } on FileSystemException {
    warnings.add('The private analytics cache could not be saved.');
    if (await temporary.exists()) await temporary.delete();
  }
}
