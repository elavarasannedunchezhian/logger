import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
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

  static final DateFormat _dateFormat =
      DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

  static String _encodeLineLabelValue(String value) {
    if (value.contains(' ')) {
      return json.encode(value);
    }
    return value;
  }

  Future<bool> sendLogEventsWithDio(
    List<LogEntry> entries, 
    Map<String, String> runtimeLabels,
  ) async {
    if (entries.isEmpty) return true;
    final streams = <Map<String, dynamic>>[];
    final Map<String, List<LogEntry>> grouped = {};

    for (final entry in entries) {
      final mergedLabels = {
        ...defaultLabels,
        ...runtimeLabels,
        ...entry.lineLabels,
      };

      final labelString = buildLabelString(mergedLabels);

      grouped.putIfAbsent(labelString, () => []).add(entry);
    }

    for (final group in grouped.entries) {
      streams.add({
        "stream": _parseLabelString(group.key),
        "values": group.value
            .map((e) => [e.ts.toString(), e.line])
            .toList(),
      });
    }

    final body = jsonEncode({"streams": streams});
    try {
      final response = await Dio().post('http://$server/api/prom/push',
        data: body,
        options: Options(
          headers: <String, String>{HttpHeaders.authorizationHeader: authHeader},
          contentType: ContentType.json.value,
        ),
      );

      print('Response: $response');
      return response.statusCode == 204;
    } catch (e, st) {
      print('Error while sending logs to Loki: $e $st');
      return false;
    }
  }

  String buildLabelString(Map<String, String> merged) {
    return '{${merged.entries.map((e) => '${e.key}="${e.value}"').join(',')}}';
  }

  Map<String, String> _parseLabelString(String labelString) {
    final content = labelString.substring(1, labelString.length - 1);
    final parts = content.split(',');

    final map = <String, String>{};

    for (final p in parts) {
      final kv = p.split('=');
      if (kv.length == 2) {
        map[kv[0]] = kv[1].replaceAll('"', '');
      }
    }
    return map;
  }

  dynamic logEntryToJson(dynamic obj) {
    if (obj is LogEntry) {
      return {
          'ts': _dateFormat.format(obj.ts.toUtc()),
          'line': [
            'level=${obj.logLevel.name}',
            obj.lineLabels.entries
                .map((entry) =>
                    '${entry.key}=${_encodeLineLabelValue(entry.value)}')
                .join(' '),
            obj.line,
          ].join(' - ')
        };
    }
  }
}

class LokiPushBody {
  LokiPushBody(this.streams);

  final List<LokiStream> streams;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'streams':
            streams.map((stream) => stream.toJson()).toList(growable: false),
      };
}

class LokiStream {
  LokiStream(this.labels, this.entries);

  final String labels;
  final List<LogEntry> entries;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'labels': labels, 'entries': entries};
}