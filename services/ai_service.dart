import 'dart:convert';
import 'dart:io'; // ✅ REQUIRED for HttpClient on Android/iOS/Desktop
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/app_secrets.dart';
import '../models/ai_extraction.dart';

/// AiService
/// - Calls Gemini API using your API key (AppSecrets.geminiApiKey)
/// - Returns a structured analysis object (AiExtraction)
/// - Defensive parsing: handles non-JSON wrapping, code fences, extra text
/// - Works with "gemini-2.5-flash" style model strings (via v1beta endpoint)
class AiService {
  AiService._(); // no instances

  static const String defaultModel = "gemini-2.5-flash";

  /// Main function: analyze a user transcript/caption about a place.
  /// Returns an AiExtraction object.
  static Future<AiExtraction> analyze({
    required String transcript,
    String caption = "",
    String language = "ms",
    String placeNameHint = "",
    String model = defaultModel,
  }) async {
    final prompt = _buildPrompt(
      transcript: transcript,
      caption: caption,
      language: language,
      placeNameHint: placeNameHint,
    );

    final uri = _uri(model);

    final payload = <String, dynamic>{
      "contents": [
        {
          "role": "user",
          "parts": [
            {"text": prompt}
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0.2,
        "topK": 40,
        "topP": 0.95,
        "maxOutputTokens": 700,
      }
    };

    final raw = await _postJson(uri, payload);

    // Gemini returns: candidates[0].content.parts[0].text
    final text = _extractText(raw);

    // Now parse JSON from the text safely
    final jsonString = _findJsonObject(text);
    final decoded = jsonDecode(jsonString);

    if (decoded is! Map<String, dynamic>) {
      throw Exception("Gemini returned JSON but not an object: $decoded");
    }

    // Normalize and return as AiExtraction
    final normalizedMap = _normalize(decoded);
    return AiExtraction.fromMap(normalizedMap);
  }

  static Uri _uri(String model) {
    final key = AppSecrets.geminiApiKey.trim();
    if (key.isEmpty || key == "PASTE_YOUR_GEMINI_API_KEY_HERE") {
      throw Exception("Gemini API key missing. Put it in AppSecrets.geminiApiKey");
    }

    final url =
        "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key";
    return Uri.parse(url);
  }

  static String _buildPrompt({
    required String transcript,
    required String caption,
    required String language,
    required String placeNameHint,
  }) {
    final hint = placeNameHint.trim().isEmpty ? "Unknown place" : placeNameHint.trim();

    return """
You are an information extraction engine for a food review app.
You MUST output ONLY valid JSON (no markdown, no code fences, no explanation).

Context:
The place being reviewed is: "$hint"

Task:
Given a creator transcript and optional caption about a food place, extract:

Fields:
- sentiment: one of ["positive","neutral","negative"]
- confidence: number 0 to 1
- halalVote: one of ["halal","not_halal","unclear"]
- foodTags: array of 3 to 10 short food tags (lowercase, snake_case)
- pros: array of 0 to 6 short bullet points
- cons: array of 0 to 6 short bullet points

Rules:
- Use "unclear" if halal is not clearly mentioned.
- If mixed language, still decide best possible.
- Keep strings short (max 60 chars each).
- foodTags should look like: ["ayam_gepuk","spicy","crispy_chicken"]

Input language hint: "$language"

Transcript:
$transcript

Caption:
$caption

Return ONLY JSON object with exactly these keys:
{"sentiment":"","confidence":0,"halalVote":"","foodTags":[],"pros":[],"cons":[]}
""";
  }

  static Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, dynamic> payload) async {
    if (kIsWeb) {
      throw Exception(
        "AiService: Web build detected. Run on Android emulator/device OR add the 'http' package for web.",
      );
    }
    return _postJsonIo(uri, payload);
  }

  static Future<Map<String, dynamic>> _postJsonIo(Uri uri, Map<String, dynamic> payload) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    final request = await client.postUrl(uri);
    request.headers.set("Content-Type", "application/json; charset=utf-8");
    request.headers.set("Accept", "application/json");

    request.add(utf8.encode(jsonEncode(payload)));

    final response = await request.close();
    final bodyBytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final body = utf8.decode(bodyBytes);

    final status = response.statusCode;

    if (status < 200 || status >= 300) {
      throw Exception("Gemini HTTP $status: $body");
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;

    throw Exception("Unexpected Gemini response type: ${decoded.runtimeType}");
  }

  static String _extractText(Map<String, dynamic> raw) {
    try {
      final candidates = raw["candidates"];
      if (candidates is List && candidates.isNotEmpty) {
        final content = candidates[0]["content"];
        final parts = content["parts"];
        if (parts is List && parts.isNotEmpty) {
          final text = parts[0]["text"];
          if (text is String) return text;
        }
      }
    } catch (_) {}
    return jsonEncode(raw);
  }

  static String _findJsonObject(String s) {
    s = s.replaceAll("```json", "");
    s = s.replaceAll("```", "");

    final start = s.indexOf("{");
    final end = s.lastIndexOf("}");

    if (start == -1 || end == -1 || end <= start) {
      throw Exception("Could not locate JSON in Gemini output: $s");
    }

    return s.substring(start, end + 1).trim();
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> m) {
    final sentiment = _asOneOf(m["sentiment"], ["positive", "neutral", "negative"], "neutral");
    // Supporting both keys just in case model ignores instruction
    final halalVote = _asOneOf(m["halalVote"] ?? m["halalStatus"], ["halal", "not_halal", "unclear"], "unclear");

    final confidence = _asDouble(m["confidence"]);
    final foodTags = _asStringList(m["foodTags"] ?? m["tags"], limit: 10);
    final pros = _asStringList(m["pros"], limit: 6);
    final cons = _asStringList(m["cons"], limit: 6);

    return {
      "sentiment": sentiment,
      "halalVote": halalVote,
      "confidence": confidence,
      "foodTags": foodTags,
      "pros": pros,
      "cons": cons,
    };
  }

  static String _asOneOf(dynamic v, List<String> allowed, String fallback) {
    final s = (v ?? "").toString().trim().toLowerCase();
    if (allowed.contains(s)) return s;
    return fallback;
  }

  static double _asDouble(dynamic v) {
    if (v is double) return v.clamp(0.0, 1.0);
    if (v is int) return (v.toDouble()).clamp(0.0, 1.0);
    if (v is num) return (v.toDouble()).clamp(0.0, 1.0);

    final s = (v ?? "").toString();
    final parsed = double.tryParse(s);
    if (parsed == null) return 0.5;
    return parsed.clamp(0.0, 1.0);
  }

  static List<String> _asStringList(dynamic v, {int limit = 10}) {
    final out = <String>[];
    if (v is List) {
      for (final item in v) {
        final s = item.toString().trim();
        if (s.isEmpty) continue;
        out.add(s);
        if (out.length >= limit) break;
      }
      return out;
    }

    if (v is String) {
      final parts = v.split(RegExp(r"[,\n]"));
      for (final p in parts) {
        final s = p.trim();
        if (s.isEmpty) continue;
        out.add(s);
        if (out.length >= limit) break;
      }
    }
    return out;
  }
}