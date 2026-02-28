class AiExtraction {
  final String sentiment; // positive | neutral | negative
  final List<String> pros;
  final List<String> cons;
  final List<String> foodTags;
  final String halalVote; // halal | not_halal | unclear
  final double confidence; // 0..1

  const AiExtraction({
    required this.sentiment,
    required this.pros,
    required this.cons,
    required this.foodTags,
    required this.halalVote,
    required this.confidence,
  });

  Map<String, dynamic> toMap() => {
    "sentiment": sentiment,
    "pros": pros,
    "cons": cons,
    "foodTags": foodTags,
    "halalVote": halalVote,
    "confidence": confidence,
  };

  static AiExtraction fromMap(Map<String, dynamic> m) {
    List<String> _list(dynamic v) =>
        (v is List) ? v.map((e) => e.toString()).toList() : <String>[];

    String _pick(String v, List<String> allowed, String fallback) {
      final s = v.trim().toLowerCase();
      return allowed.contains(s) ? s : fallback;
    }

    final sentiment = _pick(
      (m["sentiment"] ?? "neutral").toString(),
      const ["positive", "neutral", "negative"],
      "neutral",
    );

    final halalVote = _pick(
      (m["halalVote"] ?? "unclear").toString(),
      const ["halal", "not_halal", "unclear"],
      "unclear",
    );

    double conf;
    final c = m["confidence"];
    if (c is num) {
      conf = c.toDouble();
    } else {
      conf = double.tryParse((c ?? "0.5").toString()) ?? 0.5;
    }
    if (conf.isNaN) conf = 0.5;
    if (conf < 0) conf = 0;
    if (conf > 1) conf = 1;

    return AiExtraction(
      sentiment: sentiment,
      pros: _list(m["pros"]),
      cons: _list(m["cons"]),
      foodTags: _list(m["foodTags"]).map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      halalVote: halalVote,
      confidence: conf,
    );
  }
}