import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants.dart';
import '../../models/video.dart';
import '../../services/videos_service.dart';
import '../../services/places_service.dart';
import '../../services/worker_service.dart';
import '../../widgets/primary_button.dart';

class SubmitScreen extends StatefulWidget {
  final void Function(Map<String, dynamic> result)? onSubmitted;

  const SubmitScreen({super.key, this.onSubmitted});

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  final placeIdCtrl = TextEditingController();
  final urlCtrl = TextEditingController(); // ✅ make sure this exists
  final transcriptCtrl = TextEditingController();
  final captionCtrl = TextEditingController();

  // manual inputs
  final shopNameCtrl = TextEditingController();
  final addressCtrl = TextEditingController();

  String language = "mixed";
  bool loading = false;

  String status = "Ready ✅ Paste TikTok link + PlaceId + Shop + Address.";

  String? lastVideoId;
  String? lastPlaceId;

  @override
  void dispose() {
    placeIdCtrl.dispose();
    urlCtrl.dispose();
    transcriptCtrl.dispose();
    captionCtrl.dispose();
    shopNameCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _looksLikeTikTokUrl(String s) {
    final t = s.trim().toLowerCase();
    if (t.startsWith("dummy://")) return true;
    return t.contains("tiktok.com") || t.contains("vt.tiktok.com");
  }

  bool _basicValidate() {
    final pid = placeIdCtrl.text.trim();
    final url = urlCtrl.text.trim();
    final shopName = shopNameCtrl.text.trim();
    final address = addressCtrl.text.trim();

    if (pid.isEmpty) {
      setState(() => status = "Please fill in PlaceId 🙂");
      _toast("PlaceId is required");
      return false;
    }
    if (url.isEmpty) {
      setState(() => status = "Please paste a TikTok link 🙂");
      _toast("TikTok link is required");
      return false;
    }
    if (!_looksLikeTikTokUrl(url)) {
      setState(() => status = "That link doesn’t look like TikTok (still OK for testing).");
    }
    if (shopName.isEmpty) {
      setState(() => status = "Please fill in Shop name 🙂");
      _toast("Shop name is required");
      return false;
    }
    if (address.isEmpty) {
      setState(() => status = "Please fill in Address 🙂");
      _toast("Address is required");
      return false;
    }
    return true;
  }

  Future<String> _createPendingVideo() async {
    final input = VideoInput(
      placeId: placeIdCtrl.text.trim(),
      url: urlCtrl.text.trim(),
      transcriptText: transcriptCtrl.text.trim(),
      captionText: captionCtrl.text.trim(),
      language: language,
      userShopName: shopNameCtrl.text.trim(),
      userAddress: addressCtrl.text.trim(), placeKey: '',
    );

    final id = await VideosService.createPending(input);
    lastVideoId = id;
    lastPlaceId = input.placeId;
    return id;
  }

  Future<void> _submitSingleButton() async {
    if (!_basicValidate()) return;

    setState(() {
      loading = true;
      status = "Submitting… ⏳";
    });

    String videoId = "";
    final placeId = placeIdCtrl.text.trim();
    final shopName = shopNameCtrl.text.trim();
    final address = addressCtrl.text.trim();

    try {
      // 1) Create pending video doc
      videoId = await _createPendingVideo();
      setState(() => status = "Submitted ✅ videoId=$videoId (pending).");
      _toast("Submitted ✅");

      // ✅ 2) Ensure places + place_stats exist immediately
      // IMPORTANT: match PlacesService signature (no placeKey / no geo / no addressHint)
      await PlacesService.upsertPlaceAndStatsFromSubmit(
        placeId: placeId,
        shopName: shopName,
        address: address,
        halalStatus: "unclear",
      );

      // ✅ 3) Trigger worker immediately (best for demo)
      try {
        setState(() => status = "Submitted ✅ Triggering worker… ⚡");
        final msg = await WorkerService.runOnce();
        setState(() => status = "Worker triggered ✅ $msg\nvideoId=$videoId");
        _toast("Worker triggered ✅");
      } catch (e) {
        setState(() {
          status =
          "Submitted ✅ (pending).\nWorker trigger failed (still OK): $e\n"
              "Run worker manually if needed.";
        });
        _toast("Worker trigger failed (still pending)");
      }

      // clear transcript/caption after submit
      transcriptCtrl.clear();
      captionCtrl.clear();

      // notify HomeShell/Explore if provided
      widget.onSubmitted?.call({
        "placeId": placeId,
        "videoId": videoId,
        "toast": "Submitted ✅ Syncing places…",
      });
    } catch (e) {
      setState(() => status = "Error: $e");
      _toast("Submit failed");

      try {
        if (videoId.isNotEmpty) {
          await FirebaseFirestore.instance.collection("videos").doc(videoId).set({
            "status": "error",
            "errorMessage": e.toString(),
            "updatedAt": FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    } finally {
      setState(() => loading = false);
    }
  }

  void _fillDemo() {
    urlCtrl.text = "https://www.tiktok.com/@demo/video/0000000000";
    placeIdCtrl.text = "Balakong";
    transcriptCtrl.text =
    "Ayam gepuk dia sedap, sambal padu dan rangup. Tapi agak mahal sikit, dan kadang-kadang kering.";
    captionCtrl.text = "Ayam Gepuk Express dekat Balakong!";
    shopNameCtrl.text = "Ayam Gepuk Pak Gembus";
    addressCtrl.text = "Bangi, Selangor";

    setState(() => status = "Demo filled ✅ You can submit now.");
    _toast("Demo filled");
  }

  Widget _sectionTitle(String t, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t, style: const TextStyle(fontWeight: FontWeight.w900)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _tinyHint(String t) => Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 11));

  @override
  Widget build(BuildContext context) {
    final placeId = placeIdCtrl.text.trim();
    final url = urlCtrl.text.trim();
    final shopName = shopNameCtrl.text.trim();
    final address = addressCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Submit", style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            onPressed: loading ? null : _fillDemo,
            icon: const Icon(Icons.auto_fix_high),
            tooltip: "Fill demo",
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            "TikTok link",
            subtitle: "Paste TikTok URL. Worker will download + transcribe automatically.",
          ),
          const SizedBox(height: 8),
          TextField(
            controller: urlCtrl,
            decoration: InputDecoration(
              hintText: "https://www.tiktok.com/@user/video/123...",
              prefixIcon: const Icon(Icons.link),
              suffixIcon: url.isEmpty
                  ? null
                  : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: loading ? null : () => setState(() => urlCtrl.clear()),
                tooltip: "Clear",
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _tinyHint("Tip: vt.tiktok.com short links are OK too."),
          const SizedBox(height: 16),

          _sectionTitle(
            "Restaurant details (manual)",
            subtitle: "Shop name + address makes geocoding accurate.",
          ),
          const SizedBox(height: 8),
          TextField(
            controller: shopNameCtrl,
            decoration: InputDecoration(
              labelText: "Shop name",
              hintText: "Ayam Gepuk Pak Gembus",
              prefixIcon: const Icon(Icons.store),
              suffixIcon: shopName.isEmpty
                  ? null
                  : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: loading ? null : () => setState(() => shopNameCtrl.clear()),
                tooltip: "Clear",
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: addressCtrl,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: "Address / area",
              hintText: "Bangi, Selangor (or full address)",
              prefixIcon: const Icon(Icons.location_on),
              suffixIcon: address.isEmpty
                  ? null
                  : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: loading ? null : () => setState(() => addressCtrl.clear()),
                tooltip: "Clear",
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          _sectionTitle(
            "Where is this review for?",
            subtitle: "We group reviews by PlaceId (Balakong, Bangi, etc).",
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: placeIdCtrl,
                  decoration: InputDecoration(
                    labelText: "PlaceId",
                    hintText: "Balakong",
                    prefixIcon: const Icon(Icons.place),
                    suffixIcon: placeId.isEmpty
                        ? null
                        : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: loading ? null : () => setState(() => placeIdCtrl.clear()),
                      tooltip: "Clear",
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: language,
                  items: const [
                    DropdownMenuItem(value: "mixed", child: Text("mixed")),
                    DropdownMenuItem(value: "ms", child: Text("ms")),
                    DropdownMenuItem(value: "en", child: Text("en")),
                  ],
                  onChanged: (v) => setState(() => language = v ?? "mixed"),
                  decoration: const InputDecoration(
                    labelText: "Lang",
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _sectionTitle("Transcript / caption (optional)", subtitle: "Not needed for worker mode."),
          const SizedBox(height: 8),
          TextField(
            controller: transcriptCtrl,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: "Optional: paste what the creator said…",
              prefixIcon: Icon(Icons.mic),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: captionCtrl,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: "Optional caption…",
              prefixIcon: Icon(Icons.text_snippet),
            ),
          ),

          const SizedBox(height: 14),
          PrimaryButton(
            text: "Submit",
            onPressed: loading ? null : _submitSingleButton,
            loading: loading,
          ),

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.chip,
              borderRadius: BorderRadius.circular(AppRadii.r14),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Status", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                const SizedBox(height: 8),
                Text(status, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 8),
                if (lastVideoId != null)
                  Text(
                    "Last videoId: $lastVideoId",
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                if (lastPlaceId != null)
                  Text(
                    "Last placeId: $lastPlaceId",
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Text(
            "Flow: Submit → (immediate places+stats upsert) → Worker processes (download + transcribe + AI).",
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}