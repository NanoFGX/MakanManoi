import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/app_secrets.dart';

class WorkerService {
  static Future<String> runOnce() async {
    final base = AppSecrets.workerBaseUrl.trim();
    if (base.isEmpty) {
      throw Exception("workerBaseUrl not set in AppSecrets");
    }
    if (base.contains("YOUR_") || base.contains("REPLACE_")) {
      throw Exception("workerBaseUrl still placeholder in AppSecrets");
    }

    final uri = Uri.parse("$base/runOnce");

    final resp = await http.post(
      uri,
      headers: {
        "Content-Type": "application/json",
        "x-worker-secret": AppSecrets.workerSecret,
      },
      body: jsonEncode({}),
    );

    final body = resp.body.trim();

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return body.isEmpty ? "Triggered" : body;
    }

    throw Exception("Worker HTTP ${resp.statusCode}: $body");
  }
}