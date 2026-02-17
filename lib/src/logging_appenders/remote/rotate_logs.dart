import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:log/logging.dart';
import 'package:log/src/logging_appenders/remote/loki_appender.dart';
import 'package:log/src/logging_appenders/rotating_file_appender.dart';
import '../base_remote_appender.dart';
import 'package:path/path.dart' as p;

class RotateLogs {
  static Timer? timer;
  static bool running = false;
  static const int intervalSeconds = 10;
  static final List<LogEntry> buffer = [];
  static int bufferSize = 10;

  static late Directory logDir;
  static late File trackerFile;
  static Map<String, dynamic> tracker = {};

  static Future<void> init(Directory logsDirectory) async {
    logDir = logsDirectory;
    trackerFile = File(p.join(logDir.path, 'log_tracker.json'));
    await LogContext.init(logDir);

    if (!trackerFile.existsSync()) {
      trackerFile.writeAsStringSync(jsonEncode({'files': {}}));
    }

    tracker = jsonDecode(await trackerFile.readAsString());
  }

  static void start(RotatingFileAppender fileAppender, LokiApiAppender lokiAppender) {
    if (running) return;
    running = true;

    timer = Timer.periodic(
      const Duration(seconds: intervalSeconds),
      (_) => rotate(fileAppender, lokiAppender),
    );
  }

  static void stop() {
    running = false;
    timer?.cancel();
  }

  static Future<void> rotate(
    RotatingFileAppender fileAppender, 
    LokiApiAppender lokiAppender,
  ) async {
    final files = fileAppender.getAllLogFiles();

    for (final file in files) {
      await processFile(file, lokiAppender);
    }

    await cleanupOldFiles();
  }

  static Future<void> processFile(File file, LokiApiAppender lokiAppender) async {
    final fileName = p.basename(file.path);
    final stat = await file.stat();
    final entry = getTrackerEntry(fileName);

    entry['readSize'] = (entry['readSize'] ?? entry['syncedSize'] ?? 0) as int;
    entry['syncedSize'] = (entry['syncedSize'] ?? 0) as int;
    entry['totalSize'] = stat.size;

    if (entry['readSize'] > stat.size) {
      entry['readSize'] = 0;
      entry['syncedSize'] = 0;
      entry['status'] = 'pending';
      entry['completedAt'] = null;
      await saveTracker();
    }

    if (stat.size <= entry['readSize']) return;

    final raf = await file.open();
    await raf.setPosition(entry['readSize']);

    final remaining = stat.size - entry['readSize'];
    final bytes = await raf.read(remaining.toInt());
    final newOffset = raf.positionSync();
    await raf.close();

    entry['readSize'] = newOffset;
    await saveTracker();

    final lines = utf8.decode(bytes).split('\n');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final parsed = parseLogLine(line);
      if (parsed == null) continue;

      buffer.add(
        LogEntry(
          ts: parsed['time'],
          logLevel: parsed['level'],
          line: parsed['message'],
          lineLabels: {
            'app': parsed['loggerName'],
          },
        ),
      );
    }

    log('Buffer size: ${buffer.length} / $bufferSize');

    if (LogContext.labels.isEmpty) {
      log('Context not ready → holding logs in buffer');
      return;
    }

    while (buffer.length >= bufferSize) {

      final batch = List<LogEntry>.from(buffer.take(bufferSize));

      final success = await lokiAppender
          .sendLogEventsWithDio(batch, LogContext.labels)
          .then((_) => true)
          .catchError((_) => false);

      if (!success) {
        log('Loki unreachable → will retry later');
        return;
      }

      buffer.removeRange(0, bufferSize);

      log('Batch uploaded: ${batch.length}');
    }

    if (buffer.isEmpty) {
      entry['syncedSize'] = entry['readSize'];
      entry['lastSync'] = DateTime.now().toIso8601String();
      entry['remainingSize'] = stat.size - entry['syncedSize'];
    }

    if (entry['remainingSize'] == 0) {
      entry['status'] = 'completed';
      entry['completedAt'] = entry['lastSync'];
    } else {
      entry['status'] = 'pending';
    }

    await saveTracker();
  }

  static Map<String, dynamic>? parseLogLine(String logLine) {
    try {
      final regex = RegExp(
        r'^(?<time>\d{4}-\d{2}-\d{2} '
        r'\d{2}:\d{2}:\d{2}\.\d{6}) '
        r'(?<level>[a-z]+) '
        r'(?<loggerName>[^\s]+) - '
        r'(?<message>.+)$',
      );

      final match = regex.firstMatch(logLine);
      if (match == null) return null;

      final time = DateTime.parse(match.namedGroup('time')!);

      final levelName = match.namedGroup('level')!;
      final level = Level.LEVELS.firstWhere(
        (l) => l.name == levelName,
        orElse: () => Level.INFO,
      );

      return {
        'time': time,
        'level': level,
        'message': match.namedGroup('message')!,
        'loggerName': match.namedGroup('loggerName')!,
      };
    } catch (e) {
      log('Failed to parse log line: $logLine\nError: $e');
      return null;
    }
  }

  static Map<String, dynamic> getTrackerEntry(String name) {
    tracker['files'][name] ??= {
      'totalSize': 0,
      'readSize': 0,
      'syncedSize': 0,
      'remainingSize': 0,
      'lastSync': null,
      'status': 'pending',
      'completedAt': null,
    };
    return tracker['files'][name];
  }

  static Future<void> saveTracker() async {
    await trackerFile.writeAsString(
      jsonEncode(tracker),
      flush: true,
    );
  }

  static Future<void> cleanupOldFiles() async {
    final now = DateTime.now();

    for (final entry in tracker['files'].entries.toList()) {
      final data = entry.value;

      if (data['status'] != 'completed') continue;

      final completedAt = DateTime.parse(data['completedAt']);
      if (now.difference(completedAt).inDays < 30) continue;

      final file = File(p.join(logDir.path, entry.key));
      if (file.existsSync()) {
        await file.delete();
      }

      tracker['files'].remove(entry.key);
      await saveTracker();
    }
  }
}
