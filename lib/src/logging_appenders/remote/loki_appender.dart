import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../base_remote_appender.dart';

class LokiApiAppender {
  LokiApiAppender({
    required this.server,
    required this.username,
    required this.password,
    required this.labels,
  })  : labelsString =
            '{${labels.entries.map((entry) => '${entry.key}="${entry.value}"').join(',')}}',
        authHeader = 'Basic ${base64.encode(utf8.encode([
          username,
          password
        ].join(':')))}';

  final String server;
  final String username;
  final String password;
  final String authHeader;
  final Map<String, String> labels;
  final String labelsString;

  static final DateFormat _dateFormat =
      DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

  static String _encodeLineLabelValue(String value) {
    if (value.contains(' ')) {
      return json.encode(value);
    }
    return value;
  }

  Future<bool> sendLogEventsWithDio(List<LogEntry> entries) async {
    final jsonObject = LokiPushBody([LokiStream(labelsString, entries)]).toJson();
    final jsonBody = json.encode(jsonObject, toEncodable: _logEntryToJson);
    log('jsonBody: $jsonBody');
    try {
      final response = await Dio().post('http://$server/api/prom/push',
        data: jsonBody,
        options: Options(
          headers: <String, String>{HttpHeaders.authorizationHeader: authHeader},
          contentType: ContentType.json.value,
        ),
      );
      log('log sent to loki successfully : $response');
      return response.statusCode == 200;
    } catch (e, stackTrace) {
      log('failed to send log to loki: $e, $stackTrace');
      return false;
    }
  }

  dynamic _logEntryToJson(dynamic obj) {
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