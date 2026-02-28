import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/place.dart';

class PlacesService {
  static final _db = FirebaseFirestore.instance;

  static Stream<List<Place>> streamPlaces() {
    return _db.collection('places').snapshots().map(
          (snap) => snap.docs.map((d) => Place.fromDoc(d)).toList(),
    );
  }

  static Future<Place?> getPlace(String placeId) async {
    final doc = await _db.collection('places').doc(placeId).get();
    if (!doc.exists) return null;
    return Place.fromDoc(doc);
  }

  static Stream<List<Place>> streamFiltered({
    required String query,
    required String halalFilter, // All | halal | not_halal | unclear
  }) {
    return streamPlaces().map((places) {
      final q = query.trim().toLowerCase();

      return places.where((p) {
        final halalOk = (halalFilter == 'All') ? true : p.halalStatus == halalFilter;
        if (!halalOk) return false;

        if (q.isEmpty) return true;

        final inName = p.name.toLowerCase().contains(q);
        final inTags = p.foodTags.any((t) => t.toLowerCase().contains(q));
        return inName || inTags;
      }).toList();
    });
  }

  /// ✅ IMPORTANT:
  /// This is what fixes your pipeline mismatch.
  /// SubmitScreen calls this right after writing videos/{videoId}.
  ///
  /// placeKey standardizes:
  /// - If you want ONE place per shop per area:
  ///     placeKey = "${placeId}__${slug(shopName)}"
  /// - If you want MVP one doc per area only:
  ///     placeKey = placeId
  ///
  /// I’m using shop-per-area so you don’t overwrite shops.
  static Future<String> upsertPlaceAndStatsFromSubmit({
    required String placeId,
    required String shopName,
    required String address,
    String halalStatus = "unclear",
  }) async {
    final placeKey = _placeKey(placeId: placeId, shopName: shopName);

    final placeRef = _db.collection("places").doc(placeKey);
    final statsRef = _db.collection("place_stats").doc(placeKey);

    final now = FieldValue.serverTimestamp();

    await _db.runTransaction((tx) async {
      final placeSnap = await tx.get(placeRef);

      // create/merge place
      tx.set(
        placeRef,
        {
          "placeId": placeId, // keep original grouping id
          "name": shopName,
          "addressHint": address,
          "halalStatus": halalStatus,
          "overallSentiment": "mixed",
          "rating": placeSnap.data()?["rating"] ?? 0.0,
          "videoCount": placeSnap.data()?["videoCount"] ?? 0,
          "foodTagsTop": placeSnap.data()?["foodTagsTop"] ?? [],
          "lastUpdatedAt": now,

          // ✅ start as null, worker can later fill GeoPoint
          "location": placeSnap.data()?["location"] ?? null,
        },
        SetOptions(merge: true),
      );

      // create/merge stats
      tx.set(
        statsRef,
        {
          "placeKey": placeKey,
          "placeId": placeId,
          "updatedAt": now,
          "videoCount": placeSnap.data()?["videoCount"] ?? 0,
        },
        SetOptions(merge: true),
      );
    });

    return placeKey;
  }

  static String _placeKey({required String placeId, required String shopName}) {
    return "${placeId.trim()}__${_slug(shopName)}";
  }

  static String _slug(String s) {
    final t = s.trim().toLowerCase();
    final cleaned = t.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return cleaned.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }
}