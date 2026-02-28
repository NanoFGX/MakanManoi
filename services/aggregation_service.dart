import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ai_extraction.dart';

class AggregationService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> applyVideoAiToPlace({
    required String videoId,
    required String placeId,
    required AiExtraction ai,
  }) async {
    final videoRef = _db.collection("videos").doc(videoId);
    final statsRef = _db.collection("place_stats").doc(placeId);
    final placeRef = _db.collection("places").doc(placeId);

    await _db.runTransaction((tx) async {
      // ----------------------------------------------------------------------
      // IMPORTANT: In Firestore transactions, ALL READS must happen BEFORE WRITES
      // ----------------------------------------------------------------------

      // 1) READ FIRST (stats + place)
      final statsSnap = await tx.get(statsRef);
      final placeSnap = await tx.get(placeRef);

      // If missing, start from empty baseline
      final Map<String, dynamic> stats =
      (statsSnap.data() is Map<String, dynamic>) ? Map<String, dynamic>.from(statsSnap.data()!) : <String, dynamic>{};

      final Map<String, dynamic> place =
      (placeSnap.data() is Map<String, dynamic>) ? Map<String, dynamic>.from(placeSnap.data()!) : <String, dynamic>{};

      // 2) Helpers
      Map<String, dynamic> _mapField(String key) {
        final v = stats[key];
        if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
        return <String, dynamic>{};
      }

      void _incMap(Map<String, dynamic> m, String k, int delta) {
        final key = k.trim().toLowerCase();
        if (key.isEmpty) return;
        final current = m[key];
        final now = (current is num) ? current.toInt() : 0;
        m[key] = now + delta;
      }

      // Normalize sentiment (keep your DB consistent)
      String _normSentiment(String s) {
        final x = s.trim().toLowerCase();
        if (x.contains("pos")) return "positive";
        if (x.contains("neg")) return "negative";
        if (x.contains("neu")) return "neutral";
        // fallback
        return "neutral";
      }

      // Normalize halal vote
      String _normHalalVote(String s) {
        final x = s.trim().toLowerCase();
        if (x.contains("not")) return "not_halal";
        if (x.contains("halal")) return "halal";
        return "unclear";
      }

      // 3) Existing freq maps
      final prosFreq = _mapField("prosFreq");
      final consFreq = _mapField("consFreq");
      final tagFreq = _mapField("tagFreq");

      // Sentiment counts
      final Map<String, dynamic> sentimentCounts = _mapField("sentimentCounts");
      sentimentCounts.putIfAbsent("positive", () => 0);
      sentimentCounts.putIfAbsent("neutral", () => 0);
      sentimentCounts.putIfAbsent("negative", () => 0);

      // Halal votes
      final Map<String, dynamic> halalVotes = _mapField("halalVotes");
      halalVotes.putIfAbsent("halal", () => 0);
      halalVotes.putIfAbsent("not_halal", () => 0);
      halalVotes.putIfAbsent("unclear", () => 0);

      // 4) Increment stats from AI
      for (final p in ai.pros) {
        _incMap(prosFreq, p, 1);
      }

      for (final c in ai.cons) {
        _incMap(consFreq, c, 1);
      }

      for (final t in ai.foodTags) {
        _incMap(tagFreq, t, 1);
      }

      final sentiment = _normSentiment(ai.sentiment);
      final halalVote = _normHalalVote(ai.halalVote);

      _incMap(sentimentCounts, sentiment, 1);
      _incMap(halalVotes, halalVote, 1);

      final prevVideoCount = (stats["videoCount"] is num) ? (stats["videoCount"] as num).toInt() : 0;
      final newVideoCount = prevVideoCount + 1;

      final prevScoreSumWeighted =
      (stats["scoreSumWeighted"] is num) ? (stats["scoreSumWeighted"] as num).toDouble() : 0.0;
      final prevConfSum =
      (stats["confidenceSum"] is num) ? (stats["confidenceSum"] as num).toDouble() : 0.0;

      // Simple rating logic (MVP):
      // positive=5, neutral=3, negative=1 then weighted by confidence.
      final baseScore = sentiment == "positive"
          ? 5.0
          : (sentiment == "negative" ? 1.0 : 3.0);

      final conf = (ai.confidence.isNaN || ai.confidence.isInfinite) ? 0.5 : ai.confidence;
      final safeConf = conf.clamp(0.0, 1.0);

      final newScoreSumWeighted = prevScoreSumWeighted + (baseScore * safeConf);
      final newConfSum = prevConfSum + safeConf;
      final computedRating = (newConfSum <= 0.0001) ? 0.0 : (newScoreSumWeighted / newConfSum);

      // 5) Build place summary (top keys etc.)
      List<String> _topKeys(Map<String, dynamic> freq, int k) {
        final entries = freq.entries
            .where((e) => e.key.toString().trim().isNotEmpty)
            .map((e) => MapEntry(e.key.toString(), (e.value is num) ? (e.value as num).toInt() : 0))
            .toList();

        entries.sort((a, b) => b.value.compareTo(a.value));
        return entries.take(k).map((e) => e.key).toList();
      }

      String _overallSentiment(Map<String, dynamic> counts) {
        final pos = (counts["positive"] is num) ? (counts["positive"] as num).toInt() : 0;
        final neu = (counts["neutral"] is num) ? (counts["neutral"] as num).toInt() : 0;
        final neg = (counts["negative"] is num) ? (counts["negative"] as num).toInt() : 0;

        if (pos == 0 && neu == 0 && neg == 0) return "mixed";
        if (pos > neg && pos >= neu) return "positive";
        if (neg > pos && neg >= neu) return "negative";
        return "mixed";
      }

      String _halalStatus(Map<String, dynamic> votes) {
        final halal = (votes["halal"] is num) ? (votes["halal"] as num).toInt() : 0;
        final notHalal = (votes["not_halal"] is num) ? (votes["not_halal"] as num).toInt() : 0;
        final unclear = (votes["unclear"] is num) ? (votes["unclear"] as num).toInt() : 0;

        // If strong signal
        if (halal >= notHalal + 2 && halal >= unclear) return "halal";
        if (notHalal >= halal + 2 && notHalal >= unclear) return "not_halal";
        return "unclear";
      }

      final topPros = _topKeys(prosFreq, 5);
      final topCons = _topKeys(consFreq, 5);
      final foodTagsTop = _topKeys(tagFreq, 8);
      final overallSent = _overallSentiment(sentimentCounts);
      final halalStatus = _halalStatus(halalVotes);

      // Keep name/location if already exist. DO NOT overwrite name with empty.
      final placeName = (place["name"] ?? "").toString().trim();

      // ----------------------------------------------------------------------
      // 6) NOW DO WRITES (video, stats, place)
      // ----------------------------------------------------------------------

      // (A) Update video doc (safe even if it doesn't exist yet)
      tx.set(videoRef, {
        "status": "processed",
        "ai": ai.toMap(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // (B) Write stats back
      tx.set(statsRef, {
        "videoCount": newVideoCount,
        "prosFreq": prosFreq,
        "consFreq": consFreq,
        "tagFreq": tagFreq,
        "sentimentCounts": sentimentCounts,
        "halalVotes": halalVotes,
        "scoreSumWeighted": newScoreSumWeighted,
        "confidenceSum": newConfSum,
        "lastVideoAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // (C) Update place summary fields (Explore uses these)
      final Map<String, dynamic> placeUpdate = {
        "videoCount": newVideoCount,
        "rating": computedRating,
        "overallSentiment": overallSent,
        "halalStatus": halalStatus,
        "topPros": topPros,
        "topCons": topCons,
        "foodTagsTop": foodTagsTop,
        "lastUpdatedAt": FieldValue.serverTimestamp(),
      };

      // Only include name if it already exists and non-empty
      if (placeName.isNotEmpty) {
        placeUpdate["name"] = placeName;
      }

      tx.set(placeRef, placeUpdate, SetOptions(merge: true));
    });
  }
}