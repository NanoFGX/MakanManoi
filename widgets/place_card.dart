import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';
import '../core/constants.dart';
import 'tag_chip.dart';

class PlaceCard extends StatelessWidget {
  final Place place;
  final VoidCallback onView;
  final VoidCallback onRoute;

  const PlaceCard({
    super.key,
    required this.place,
    required this.onView,
    required this.onRoute,
  });

  ChipTone halalTone(String s) {
    switch (s) {
      case 'halal':
        return ChipTone.good;
      case 'not_halal':
        return ChipTone.bad;
      default:
        return ChipTone.warn;
    }
  }

  String halalLabel(String s) {
    switch (s) {
      case 'halal':
        return 'Halal-likely';
      case 'not_halal':
        return 'Not halal';
      default:
        return 'Halal unclear';
    }
  }

  // ---------------------------------------
  // NEW: open Google Maps directions
  // - Uses user's current location as origin automatically
  // - Works best with destination lat/lng
  // ---------------------------------------
  Future<void> _openGoogleMapsDirections(BuildContext context) async {
    if (!place.hasValidLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Location not set yet for this place. Submit a review with address so we can pin it."),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final destination = "${place.lat},${place.lng}";
    final url = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving",
    );

    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not open Google Maps."),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(place.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            "⭐ ${place.rating.toStringAsFixed(1)} • ${place.videoCount} video(s) • ${place.overallSentiment}",
            style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TagChip(text: halalLabel(place.halalStatus), tone: halalTone(place.halalStatus)),
              ...place.foodTagsTop.take(4).map((t) => TagChip(text: t)),
            ],
          ),
          const SizedBox(height: 8),
          if (place.topPros.isNotEmpty)
            Text("Pros: ${place.topPros.join(' • ')}", style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (place.topCons.isNotEmpty)
            Text("Cons: ${place.topCons.join(' • ')}", style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.r14)),
                    side: const BorderSide(color: AppColors.line),
                  ),
                  onPressed: onView,
                  child: const Text("View", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.r14)),
                  ),

                  // NEW behavior:
                  // - if place has lat/lng → open Google Maps directions
                  // - otherwise → toast
                  // - we still call onRoute for compatibility/analytics if you use it
                  onPressed: () async {
                    try {
                      onRoute();
                    } catch (_) {}
                    await _openGoogleMapsDirections(context);
                  },

                  child: const Text("Route", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}