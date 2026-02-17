import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import '../base_remote_appender.dart';

class LokiApiAppender {
  LokiApiAppender({
    required this.server,
    required this.username,
    required this.password,
    required Map<String, String> labels,
  })  : defaultLabels = labels,
        authHeader = 'Basic ${base64.encode(utf8.encode([
          username,
          password
        ].join(':')))}';

  final String server;
  final String username;
  final String password;
  final String authHeader;
  final Map<String, String> defaultLabels;

  Future<bool> sendLogEventsWithDio(List<LogEntry> entries, Map<String, String> runtimeLabels) async {
    if (entries.isEmpty) return true;
    final Map<Map<String, String>, List<List<String>>> streams = {};

    for (final entry in entries) {

      final labels = {
        ...defaultLabels,
        ...runtimeLabels,
        ...entry.lineLabels,
      };

      streams.putIfAbsent(labels, () => []);
      streams[labels]!.add([
        toNano(entry.ts),
        entry.line,
        entry.logLevel.name,
      ]);
    }

    final payload = {
      "streams": streams.entries.map((e) => {
        "stream": e.key,
        "values": e.value,
      }).toList()
    };
    log('sending log to loki: $payload');
    try {
      final response = await Dio().post('http://$server/loki/api/v1/push',
        data: jsonEncode(payload),
        options: Options(
          headers: <String, String>{HttpHeaders.authorizationHeader: authHeader},
          contentType: ContentType.json.value,
        ),
      );
      log('log sent to loki successfully : $response');
      return response.statusCode == 204;
    } catch (e, stackTrace) {
      log('failed to send log to loki: $e, $stackTrace');
      return false;
    }
  }

  String toNano(DateTime dt) {
    return (dt.toUtc().microsecondsSinceEpoch * 1000).toString();
  }

  String buildLabelString(Map<String, String> merged) {
    return '{${merged.entries.map((e) => '${e.key}="${e.value}"').join(',')}}';
  }
}