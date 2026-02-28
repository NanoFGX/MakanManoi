import 'package:cloud_firestore/cloud_firestore.dart';

class Place {
  final String id;
  final String name;

  /// Nullable so places can exist before worker geocodes.
  final GeoPoint? location;

  /// halal | not_halal | unclear
  final String halalStatus;

  /// positive | neutral | negative | mixed
  final String overallSentiment;

  final double rating;
  final int videoCount;

  /// Aggregated fields (used by cards/details)
  final List<String> foodTagsTop;
  final List<String> topPros;
  final List<String> topCons;

  Place({
    required this.id,
    required this.name,
    required this.location,
    required this.halalStatus,
    required this.rating,
    required this.videoCount,
    required this.overallSentiment,
    required this.foodTagsTop,
    required this.topPros,
    required this.topCons,
  });

  // ---------- Convenience getters used by UI ----------

  bool get hasValidLocation => location != null;

  double get lat => location?.latitude ?? 0.0;

  double get lng => location?.longitude ?? 0.0;

  /// Backwards-compat alias (older code used `foodTags`).
  List<String> get foodTags => foodTagsTop;

  // ---------- Parsing ----------

  static List<String> _readStringList(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v is Iterable) {
      return v
          .map((e) => e.toString())
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  static GeoPoint? _readGeoPoint(dynamic v) {
    if (v is GeoPoint) return v;

    // Sometimes location may be stored as {lat, lon} or {lat, lng}
    if (v is Map) {
      final lat = v['lat'] ?? v['latitude'];
      final lon = v['lon'] ?? v['lng'] ?? v['longitude'];
      if (lat is num && lon is num) {
        return GeoPoint(lat.toDouble(), lon.toDouble());
      }
    }
    return null;
  }

  factory Place.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return Place(
      id: doc.id,
      name: (data['name'] ?? doc.id).toString(),
      location: _readGeoPoint(data['location']),
      halalStatus: (data['halalStatus'] ?? 'unclear').toString(),
      rating: (data['rating'] is num) ? (data['rating'] as num).toDouble() : 0.0,
      videoCount: (data['videoCount'] is num) ? (data['videoCount'] as num).toInt() : 0,
      overallSentiment: (data['overallSentiment'] ?? 'mixed').toString(),
      foodTagsTop: _readStringList(data, 'foodTagsTop'),
      topPros: _readStringList(data, 'topPros'),
      topCons: _readStringList(data, 'topCons'),
    );
  }
}