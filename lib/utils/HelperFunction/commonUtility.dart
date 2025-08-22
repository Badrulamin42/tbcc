import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogStorage {
  static const _key = "logs";
  static const Duration _retention = Duration(hours: 1);

  /// Add a log entry and keep only last 1 hour
  static Future<void> logMessage(String message) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> logsJson = prefs.getStringList(_key) ?? <String>[];

    final now = DateTime.now();
    final formatted = DateFormat("yyyy-MM-dd HH:mm:ss.SSS").format(now); // include ms

    // Get last log (if any) to calculate elapsed time
    Duration? diff;
    if (logsJson.isNotEmpty) {
      try {
        final lastLog = jsonDecode(logsJson.last) as Map<String, dynamic>;
        final lastTime = DateTime.parse(lastLog["time"] as String);
        diff = now.difference(lastTime);
      } catch (_) {}
    }

    // Store raw ISO for filtering + pretty message for display + diff
    final String newLog = jsonEncode({
      "time": now.toIso8601String(),
      "message": "[$formatted] $message",
      "elapsed_ms": diff?.inMilliseconds,   // null for first log
      "elapsed_us": diff?.inMicroseconds,   // higher precision
    });

    logsJson.add(newLog);

    final cutoff = now.subtract(_retention);
    final List<String> filtered = logsJson.where((logStr) {
      try {
        final Map<String, dynamic> log =
        jsonDecode(logStr) as Map<String, dynamic>;
        final DateTime t = DateTime.parse(log["time"] as String);
        return t.isAfter(cutoff);
      } catch (_) {
        return false; // drop corrupted entries
      }
    }).toList(growable: false);

    await prefs.setStringList(_key, filtered);
  }

  /// Get logs from last 1 hour (as display strings)
  static Future<List<String>> getLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> logsJson = prefs.getStringList(_key) ?? <String>[];
    final DateTime cutoff = DateTime.now().subtract(_retention);

    final List<String> result = logsJson.where((logStr) {
      try {
        final Map<String, dynamic> log =
        jsonDecode(logStr) as Map<String, dynamic>;
        final DateTime t = DateTime.parse(log["time"] as String);
        return t.isAfter(cutoff);
      } catch (_) {
        return false;
      }
    }).map<String>((logStr) {
      final Map<String, dynamic> log =
      jsonDecode(logStr) as Map<String, dynamic>;
      final elapsed = log["elapsed_ms"];
      if (elapsed != null) {
        return "${log["message"]}  (+${elapsed} ms)";
      } else {
        return log["message"] as String;
      }
    }).toList(growable: false);

    return result; // <- List<String>
  }

  /// Clear all logs
  static Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
