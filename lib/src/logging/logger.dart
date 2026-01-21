import 'dart:async';
import 'dart:collection';

import 'level.dart';
import 'log_record.dart';

bool hierarchicalLoggingEnabled = false;
const defaultLevel = Level.INFO;

class Logger {
  final String name;
  String get fullName =>
      parent?.name.isNotEmpty ?? false ? '${parent!.fullName}.$name' : name;
  final Logger? parent;
  Level? _level;
  final Map<String, Logger> _children;
  final Map<String, Logger> children;
  StreamController<LogRecord>? _controller;
  StreamController<Level?>? _levelChangedController;
  factory Logger(String name) =>
      _loggers.putIfAbsent(name, () => Logger._named(name));

  factory Logger.detached(String name) =>
      Logger._internal(name, null, <String, Logger>{});

  factory Logger._named(String name) {
    if (name.startsWith('.')) {
      throw ArgumentError("name shouldn't start with a '.'");
    }
    if (name.endsWith('.')) {
      throw ArgumentError("name shouldn't end with a '.'");
    }

    final dot = name.lastIndexOf('.');
    Logger? parent;
    String thisName;
    if (dot == -1) {
      if (name != '') parent = Logger('');
      thisName = name;
    } else {
      parent = Logger(name.substring(0, dot));
      thisName = name.substring(dot + 1);
    }
    return Logger._internal(thisName, parent, <String, Logger>{});
  }

  Logger._internal(this.name, this.parent, Map<String, Logger> children)
      : _children = children,
        children = UnmodifiableMapView(children) {
    if (parent == null) {
      _level = defaultLevel;
    } else {
      parent!._children[name] = this;
    }
  }

  Level get level {
    Level effectiveLevel;

    if (parent == null) {
      effectiveLevel = _level!;
    } else if (!hierarchicalLoggingEnabled) {
      effectiveLevel = root._level!;
    } else {
      effectiveLevel = _level ?? parent!.level;
    }

    // ignore: unnecessary_null_comparison
    assert(effectiveLevel != null);
    return effectiveLevel;
  }

  set level(Level? value) {
    if (!hierarchicalLoggingEnabled && parent != null) {
      throw UnsupportedError(
        'Please set "hierarchicalLoggingEnabled" to true if you want to '
        'change the level on a non-root logger.',
      );
    }
    if (parent == null && value == null) {
      throw UnsupportedError(
        'Cannot set the level to `null` on a logger with no parent.',
      );
    }
    final isLevelChanged = _level != value;
    _level = value;
    if (isLevelChanged) {
      _levelChangedController?.add(value);
    }
  }

  Stream<Level?> get onLevelChanged {
    _levelChangedController ??= StreamController<Level?>.broadcast(sync: true);
    return _levelChangedController!.stream;
  }

  Stream<LogRecord> get onRecord => _getStream();

  void clearListeners() {
    if (hierarchicalLoggingEnabled || parent == null) {
      _controller?.close();
      _controller = null;
    } else {
      root.clearListeners();
    }
  }

  bool isLoggable(Level value) => value >= level;

  void log(
    Level logLevel,
    Object? message, [
    Object? error,
    StackTrace? stackTrace,
    Zone? zone,
  ]) {
    Object? object;
    if (isLoggable(logLevel)) {
      if (message is Function) {
        message = (message as Object? Function())();
      }

      String msg;
      if (message is String) {
        msg = message;
      } else {
        msg = message.toString();
        object = message;
      }

      zone ??= Zone.current;

      final record = LogRecord(
        logLevel,
        msg,
        fullName,
        error,
        stackTrace,
        zone,
        object,
      );

      if (parent == null) {
        _publish(record);
      } else if (!hierarchicalLoggingEnabled) {
        root._publish(record);
      } else {
        Logger? target = this;
        while (target != null) {
          target._publish(record);
          target = target.parent;
        }
      }
    }
  }

  void all(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(Level.ALL, message, error, stackTrace);

  void trace(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(Level.TRACE, message, error, stackTrace);

  void debug(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(Level.DEBUG, message, error, stackTrace);

  void info(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(Level.INFO, message, error, stackTrace);

  void warning(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(Level.WARNING, message, error, stackTrace);

  void error(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(Level.ERROR, message, error, stackTrace);

  void critical(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(Level.CRITICAL, message, error, stackTrace);

  Stream<LogRecord> _getStream() {
    if (hierarchicalLoggingEnabled || parent == null) {
      return (_controller ??= StreamController<LogRecord>.broadcast(
        sync: true,
      ))
          .stream;
    } else {
      return root._getStream();
    }
  }

  void _publish(LogRecord record) => _controller?.add(record);

  static final Logger root = Logger('');

  static final Map<String, Logger> _loggers = <String, Logger>{};

  static Iterable<Logger> get attachedLoggers => _loggers.values;
}