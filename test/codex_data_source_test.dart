import 'dart:convert';
import 'dart:io';

import 'package:codex_dashboard/src/data/codex_data_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'requests the sandbox-approved Codex root through the platform',
    () async {
      const channel = MethodChannel(CodexRootAccess.channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, CodexRootAccess.methodName);
            return '/tmp/approved/.codex';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      expect(
        await const CodexRootAccess().resolveOrRequest(),
        '/tmp/approved/.codex',
      );
    },
  );

  test('reports when sandbox folder access is cancelled', () async {
    const channel = MethodChannel(CodexRootAccess.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(
      const CodexRootAccess().resolveOrRequest(),
      throwsA(isA<CodexFolderAccessException>()),
    );
  });

  test('counts history prompts and never caches chat text', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'codex-pulse-test-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final root = Directory('${temporary.path}/.codex');
    final sessions = Directory('${root.path}/sessions/2026/07/15');
    await sessions.create(recursive: true);
    const sessionId = '019f6689-040f-7db1-8a17-729f39f9ce54';
    final sentAt = DateTime.utc(2026, 7, 15, 10);
    final secondPrompt = sentAt.add(const Duration(minutes: 5));
    const secret = 'TOP SECRET PROMPT TEXT';
    await File('${root.path}/history.jsonl').writeAsString(
      [
        jsonEncode({
          'session_id': sessionId,
          'ts': sentAt.millisecondsSinceEpoch ~/ 1000,
          'text': secret,
        }),
        jsonEncode({
          'session_id': sessionId,
          'ts': secondPrompt.millisecondsSinceEpoch ~/ 1000,
          'text': 'a second manual prompt',
        }),
      ].join('\n'),
    );
    final rollout = File(
      '${sessions.path}/rollout-2026-07-15T10-00-00-$sessionId.jsonl',
    );
    await rollout.writeAsString(
      [
        _event(sentAt.subtract(const Duration(seconds: 2)), 'session_meta', {
          'id': sessionId,
          'cwd': '/tmp/project',
          'source': 'cli',
        }),
        _event(sentAt.subtract(const Duration(seconds: 1)), 'event_msg', {
          'type': 'task_started',
        }),
        _event(
          sentAt.subtract(const Duration(milliseconds: 500)),
          'turn_context',
          {'model': 'gpt-test', 'effort': 'high'},
        ),
        _event(sentAt.subtract(const Duration(minutes: 10)), 'event_msg', {
          'type': 'user_message',
          'message': 'injected context that must not count',
        }),
        _event(sentAt, 'event_msg', {
          'type': 'user_message',
          'message': secret,
        }),
        _event(sentAt.add(const Duration(seconds: 1)), 'event_msg', {
          'type': 'agent_message',
          'message': 'private response text',
        }),
        _event(sentAt.add(const Duration(seconds: 2)), 'response_item', {
          'type': 'function_call',
          'name': 'read_file',
        }),
        _event(sentAt.add(const Duration(seconds: 3)), 'event_msg', {
          'type': 'patch_apply_end',
        }),
        _event(sentAt.add(const Duration(seconds: 4)), 'event_msg', {
          'type': 'token_count',
          'info': {
            'total_token_usage': {
              'input_tokens': 100,
              'cached_input_tokens': 50,
              'output_tokens': 20,
              'reasoning_output_tokens': 10,
              'total_tokens': 120,
            },
          },
        }),
        _event(sentAt.add(const Duration(seconds: 5)), 'event_msg', {
          'type': 'task_complete',
          'duration_ms': 6000,
        }),
        _event(secondPrompt.subtract(const Duration(seconds: 1)), 'event_msg', {
          'type': 'task_started',
        }),
        _event(secondPrompt, 'event_msg', {
          'type': 'user_message',
          'message': 'a second manual prompt',
        }),
        _event(secondPrompt.add(const Duration(seconds: 1)), 'event_msg', {
          'type': 'agent_message',
          'message': 'another private response',
        }),
        _event(secondPrompt.add(const Duration(seconds: 2)), 'event_msg', {
          'type': 'token_count',
          'info': {
            'total_token_usage': {
              'input_tokens': 250,
              'cached_input_tokens': 120,
              'output_tokens': 50,
              'reasoning_output_tokens': 20,
              'total_tokens': 300,
            },
          },
        }),
        _event(secondPrompt.add(const Duration(seconds: 3)), 'event_msg', {
          'type': 'task_complete',
          'duration_ms': 4000,
        }),
      ].join('\n'),
    );
    final cache = File('${temporary.path}/cache/analytics.json');
    final dataset = await CodexDataSource(
      codexRootOverride: root.path,
      cachePathOverride: cache.path,
    ).load();

    expect(dataset.prompts, hasLength(2));
    expect(dataset.turns, hasLength(2));
    expect(dataset.turns.first.model, 'gpt-test');
    expect(dataset.turns.first.durationMs, 6000);
    expect(dataset.turns.first.toolCalls, 1);
    expect(dataset.turns.first.patchApplications, 1);
    expect(dataset.turns.first.totalTokens, 120);
    expect(dataset.turns.last.totalTokens, 180);
    expect(
      dataset.turns.fold<int>(0, (sum, turn) => sum + (turn.totalTokens ?? 0)),
      300,
    );
    final cacheContents = await cache.readAsString();
    expect(cacheContents, contains('"version":4'));
    expect(cacheContents, contains('"containsChatText":false'));
    expect(cacheContents, isNot(contains(secret)));
    expect(cacheContents, isNot(contains('private response text')));
    expect(cacheContents, isNot(contains('injected context')));
  });
}

String _event(DateTime timestamp, String type, Map<String, Object?> payload) =>
    jsonEncode({
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'payload': payload,
    });
