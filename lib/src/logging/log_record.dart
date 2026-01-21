import 'dart:async';

import 'level.dart';

class LogRecord {
  final Level level;
  final String message;
  final Object? object;
  final String loggerName;
  final DateTime time;
  final int sequenceNumber;
  static int _nextNumber = 0;
  final Object? error;
  final StackTrace? stackTrace;
  final Zone? zone;

  LogRecord(
    this.level,
    this.message,
    this.loggerName, [
    this.error,
    this.stackTrace,
    this.zone,
    this.object,
  ])  : time = DateTime.now(),
        sequenceNumber = LogRecord._nextNumber++;

  @override
  String toString() => '[${level.name}] $loggerName: $message';
}