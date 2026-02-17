// ignore_for_file: constant_identifier_names

class Level implements Comparable<Level> {
  final String name;
  final int value;
  const Level(this.name, this.value);

  static const Level ALL = Level('all', 0);
  static const Level TRACE = Level('trace', 100);
  static const Level DEBUG = Level('debug', 200);
  static const Level INFO = Level('info', 300);
  static const Level WARNING = Level('warning', 400);
  static const Level ERROR = Level('error', 500);
  static const Level CRITICAL = Level('critical', 600);

  static const List<Level> LEVELS = [
    ALL,
    TRACE,
    DEBUG,
    INFO,
    WARNING,
    ERROR,
    CRITICAL,
  ];

  @override
  bool operator ==(Object other) => other is Level && value == other.value;

  bool operator <(Level other) => value < other.value;

  bool operator <=(Level other) => value <= other.value;

  bool operator >(Level other) => value > other.value;

  bool operator >=(Level other) => value >= other.value;

  @override
  int compareTo(Level other) => value - other.value;

  @override
  int get hashCode => value;

  @override
  String toString() => name;
}