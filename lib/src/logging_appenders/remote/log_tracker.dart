import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class LogTracker {
  static late File trackerFile;
  static Map<String, dynamic> tracker = {};

  static Future<void> init(Directory logDirectory) async {
    trackerFile = File(p.join(logDirectory.path, 'log_tracker.json'));
    if (!trackerFile.existsSync()) {
      trackerFile.writeAsStringSync(jsonEncode({'files': {}}), flush: true);
    }
    tracker = jsonDecode(await trackerFile.readAsString());

    try {
      tracker = jsonDecode(await trackerFile.readAsString());
    } catch (_) {
      tracker = {'files': {}};
      await trackerFile.writeAsString(jsonEncode(tracker), flush: true);
    }
  }

  static Map<String, dynamic> getFile(String name) {
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

  static Future<void> save() async {
    await trackerFile.writeAsString(jsonEncode(tracker));
  }
}
