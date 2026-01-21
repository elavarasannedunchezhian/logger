import 'exception_chain.dart';
import '../logging/log_record.dart';

abstract class LogRecordFormatter {
  const LogRecordFormatter();

  StringBuffer formatToStringBuffer(LogRecord rec, StringBuffer sb);

  String format(LogRecord rec) =>
      formatToStringBuffer(rec, StringBuffer()).toString();
}

class BlockFormatter extends LogRecordFormatter {
  BlockFormatter._(this.block);

  BlockFormatter.formatRecord(String Function(LogRecord rec) formatter)
      : this._((rec, sb) => sb.write(formatter(rec)));

  final void Function(LogRecord rec, StringBuffer sb) block;

  @override
  StringBuffer formatToStringBuffer(LogRecord rec, StringBuffer sb) {
    block(rec, sb);
    return sb;
  }
}

class DefaultLogRecordFormatter extends LogRecordFormatter {
  const DefaultLogRecordFormatter();

  @override
  StringBuffer formatToStringBuffer(LogRecord rec, StringBuffer sb) {
    sb.write('${rec.time} ${rec.level.name} '
        '${rec.loggerName} - ${rec.message}');

    void formatErrorAndStackTrace(final Object? error, StackTrace? stackTrace) {
      if (error != null) {
        sb.writeln();
        sb.write('### ${error.runtimeType}: ');
        sb.write(error);
      }
      // ignore: avoid_as
      final stack = stackTrace ?? (error is Error ? (error).stackTrace : null);
      if (stack != null) {
        sb.writeln();
        sb.write(stack);
      }
      final causedBy = error is Exception ? error.getCausedByException() : null;
      if (causedBy != null) {
        sb.write('### Caused by: ');
        formatErrorAndStackTrace(causedBy.error, causedBy.stack);
      }
    }

    formatErrorAndStackTrace(rec.error, rec.stackTrace);

    return sb;
  }
}