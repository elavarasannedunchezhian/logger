import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class LogContext {
  static Map<String, String>? context;
  static late File file;

  static Future<void> init(Directory logsDirectory) async {
    file = File(p.join(logsDirectory.path, 'log_context.json'));

    if (!await file.exists()) {
      context = {};
      await file.writeAsString(jsonEncode(context), flush: true);
      return;
    }

    try {
      final content = await file.readAsString();

      if (content.trim().isEmpty) {
        context = {};
        await file.writeAsString(jsonEncode(context));
        return;
      }

      final json = jsonDecode(content);
      context = Map<String, String>.from(json);
    } catch (e) {
      // Corrupted file protection
      context = {};
      await file.writeAsString(jsonEncode(context));
    }
  }

  static Map<String, String> get labels => context ?? {};

  static Future<void> save(Map<String, String> ctx) async {
    context = ctx;
    await file.writeAsString(jsonEncode(ctx), flush: true);
  }
}
