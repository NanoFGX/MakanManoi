import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/video.dart';
import 'auth_service.dart';

class VideosService {
  static final _db = FirebaseFirestore.instance;

  static Future<String> createPending(VideoInput input) async {
    final ref = _db.collection('videos').doc();

    // ✅ Build a strong geocode hint string (worker can use this directly)
    final shop = input.userShopName.trim();
    final addr = input.userAddress.trim();
    final combinedHint = [
      if (shop.isNotEmpty) shop,
      if (addr.isNotEmpty) addr,
    ].join(', ');

    await _db.collection('videos').add({
      "status": "pending",
      "url": input.url,
      "placeId": input.placeId,
      "placeKey": input.placeKey, // ✅ NEW
      "language": input.language,
      "transcriptText": input.transcriptText,
      "captionText": input.captionText,
      "userShopName": input.userShopName,
      "userAddress": input.userAddress,
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPendingVideos() {
    return _db
        .collection('videos')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> markFailed(String videoId, String reason) async {
    await _db.collection('videos').doc(videoId).update({
      'status': 'failed',
      'error': {'message': reason},
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}