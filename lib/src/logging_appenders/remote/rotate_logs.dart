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
  static Timer? _timer;
  static bool _running = false;
  static const int intervalSeconds = 10;
  static final List<LogEntry> buffer = [];
  static int bufferSize = 10;

  static late Directory logDir;
  static late File trackerFile;
  static Map<String, dynamic> tracker = {};

  // ---------------- INIT ----------------

  static Future<void> init(Directory logsDirectory) async {
    logDir = logsDirectory;
    trackerFile = File(p.join(logDir.path, 'log_tracker.json'));
    await LogContext.init(logDir);

    if (!trackerFile.existsSync()) {
      trackerFile.writeAsStringSync(jsonEncode({'files': {}}));
    }

    tracker = jsonDecode(await trackerFile.readAsString());
  }

  // ---------------- TIMER ----------------

  static void start(RotatingFileAppender fileAppender, LokiApiAppender lokiAppender) {
    if (_running) return;
    _running = true;

    _timer = Timer.periodic(
      const Duration(seconds: intervalSeconds),
      (_) => _rotate(fileAppender, lokiAppender),
    );
  }

  static void stop() {
    _running = false;
    _timer?.cancel();
  }

  // ---------------- CORE ROTATION ----------------

  static Future<void> _rotate(
    RotatingFileAppender fileAppender, 
    LokiApiAppender lokiAppender,
  ) async {
    final files = fileAppender.getAllLogFiles();

    for (final file in files) {
      await _processFile(file, lokiAppender);
    }

    await _cleanupOldFiles();
  }

  // ---------------- FILE PROCESSING ----------------
  static Future<void> _processFile(File file, LokiApiAppender lokiAppender) async {
    final fileName = p.basename(file.path);
    final stat = await file.stat();
    final entry = _getTrackerEntry(fileName);

    entry['totalSize'] = stat.size;
    entry['syncedSize'] = (entry['syncedSize'] ?? 0) as int;

    // File truncated or replaced
    if (entry['syncedSize'] > stat.size) {
      entry['syncedSize'] = 0;
      entry['status'] = 'pending';
      entry['completedAt'] = null;
    }

    // File grew after completion
    if (entry['status'] == 'completed' &&
        stat.size > entry['syncedSize']) {
      entry['status'] = 'pending';
      entry['completedAt'] = null;
    }

    if (entry['status'] == 'completed') return;

    final raf = await file.open();
    await raf.setPosition(entry['syncedSize']);

    final remaining = stat.size - entry['syncedSize'];
    if (remaining <= 0) {
      await raf.close();
      return;
    }

    final bytes = await raf.read(remaining.toInt());
    final newOffset = raf.positionSync();
    await raf.close();

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

    log('Buffer size: ${buffer.length}');
    log('Buffer capacity: $bufferSize');
    if (buffer.length < bufferSize) {
      log('Buffer is not full');
      return;
    }

    if (LogContext.labels.isEmpty) {
      log('Log context is not ready');
      return;
    }

    final batch = List<LogEntry>.from(buffer.take(bufferSize));

    final success = await lokiAppender.sendLogEventsWithDio(batch)
        .then((_) => true)
        .catchError((_) => false);

    if (!success) {
      log('Failed to send batch');
      return;
    }

    buffer.removeRange(0, bufferSize);

    // Advance offset even if no valid lines parsed
    entry['syncedSize'] = newOffset;
    entry['remainingSize'] = stat.size - newOffset;
    entry['lastSync'] = DateTime.now().toIso8601String();

    if (entry['remainingSize'] <= 0) {
      entry['status'] = 'completed';
      entry['completedAt'] = entry['lastSync'];
    }

    await _saveTracker();
  }


  // Parse the log line into a structured map.
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


  // ---------------- TRACKER HELPERS ----------------

  static Map<String, dynamic> _getTrackerEntry(String name) {
    tracker['files'][name] ??= {
      'totalSize': 0,
      'syncedSize': 0,
      'remainingSize': 0,
      'lastSync': null,
      'status': 'pending',
      'completedAt': null,
    };
    return tracker['files'][name];
  }

  static Future<void> _saveTracker() async {
    await trackerFile.writeAsString(
      jsonEncode(tracker),
      flush: true,
    );
  }

  // ---------------- CLEANUP (30 DAYS) ----------------

  static Future<void> _cleanupOldFiles() async {
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
      await _saveTracker();
    }
  }
}
