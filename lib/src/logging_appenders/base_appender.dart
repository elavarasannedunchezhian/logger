import 'dart:async';

import 'package:meta/meta.dart';
import '../logging/log_record.dart';
import '../logging/logger.dart';

import 'logrecord_formatter.dart';

typedef LogRecordListener = void Function(LogRecord rec);

abstract class BaseLogAppender {
  BaseLogAppender(LogRecordFormatter? formatter)
      : formatter = formatter ?? const DefaultLogRecordFormatter();

  final LogRecordFormatter formatter;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  @protected
  @visibleForTesting
  void handle(LogRecord record);

  @protected
  LogRecordListener logListener() => (LogRecord record) => handle(record);

  void attachToLogger(Logger logger) {
    _subscriptions.add(logger.onRecord.listen(logListener()));
  }

  Future<void> detachFromLoggers() async {
    await _cancelSubscriptions();
  }

  void call(LogRecord record) => handle(record);

  @mustCallSuper
  Future<void> dispose() async {
    await _cancelSubscriptions();
  }

  Future<void> _cancelSubscriptions() async {
    final futures =
        _subscriptions.map((sub) => sub.cancel()).toList(growable: false);
    _subscriptions.clear();
    await Future.wait<dynamic>(futures);
  }
}
