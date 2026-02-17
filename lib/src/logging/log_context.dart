import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class LogContext {
  static Map<String, String>? context;
  static late File file;

  static Future<void> init(Directory dir) async {
    file = File(p.join(dir.path, 'log_context.json'));

    if (await file.exists()) {
      final json = jsonDecode(await file.readAsString());
      context = Map<String, String>.from(json);
    }
  }

  static bool get isReady => context != null;

  static Map<String, String> get labels => context ?? {};

  static Future<void> save(Map<String, String> ctx) async {
    context = ctx;
    await file.writeAsString(jsonEncode(ctx));
  }
}
