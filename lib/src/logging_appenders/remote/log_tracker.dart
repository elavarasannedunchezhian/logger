import 'dart:convert';
import 'dart:io';

class LogTracker {
  static late File trackerFile;
  static Map<String, dynamic> tracker = {};

  static Future<void> init(Directory logDir) async {
    trackerFile = File('${logDir.path}/log_tracker.json');
    if (!trackerFile.existsSync()) {
      trackerFile.writeAsStringSync(jsonEncode({'files': {}}));
    }
    tracker = jsonDecode(await trackerFile.readAsString());
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
