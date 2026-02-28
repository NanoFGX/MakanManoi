class VideoInput {
  final String placeId;
  final String placeKey;
  final String url; // can be dummy for now
  final String transcriptText;
  final String captionText;
  final String language; // ms/en/mixed

  // NEW: manual location hints for accuracy
  final String userShopName;
  final String userAddress;

  VideoInput({
    required this.placeId,
    required this.placeKey,
    required this.url,
    required this.transcriptText,
    required this.captionText,
    required this.language,

    // NEW
    required this.userShopName,
    required this.userAddress,
  });

  // OPTIONAL: convenient map for Firestore writes (keeps your service clean)
  Map<String, dynamic> toMap() {
    return {
      'placeId': placeId,
      'url': url,
      'transcriptText': transcriptText,
      'captionText': captionText,
      'language': language,
      'userShopName': userShopName,
      'userAddress': userAddress,
    };
  }
}