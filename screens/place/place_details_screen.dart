import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../services/places_service.dart';
import '../../widgets/tag_chip.dart';

class PlaceDetailsScreen extends StatelessWidget {
  final String placeId;
  const PlaceDetailsScreen({super.key, required this.placeId});

  Future<void> _openDirections(BuildContext context, double lat, double lng) async {
    final uri = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving",
    );

    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not open maps on this device."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _toastLocationMissing(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Location not set yet for this place. Submit a review with address so we can pin it."),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Place Details",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Share (demo)"),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(milliseconds: 1100),
                ),
              );
            },
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Saved (demo)"),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(milliseconds: 1100),
                ),
              );
            },
            icon: const Icon(Icons.bookmark_border_rounded),
          ),
        ],
      ),
      body: FutureBuilder(
        future: PlacesService.getPlace(placeId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _LoadingState();
          }

          if (snap.hasError) {
            return _ErrorState(
              message: "Failed to load place details.\n${snap.error}",
              onRetry: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Please go back and open again (demo retry)"),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            );
          }

          final place = snap.data;
          if (place == null) {
            return const _EmptyNotFoundState();
          }

          // Keep math import meaningful + safe clamp
          final double ratingRaw = (place.rating as num).toDouble();
          final double rating = math.min(5.0, math.max(0.0, ratingRaw));
          final int videoCount = (place.videoCount as num).toInt();

          final ChipTone halalTone = _toneForHalal(place.halalStatus);
          final ChipTone sentimentTone = _toneForSentiment(place.overallSentiment);

          // ✅ FIX: location is nullable (GeoPoint?)
          final hasLocation = place.location != null;
          final double lat = place.location?.latitude ?? 0.0;
          final double lng = place.location?.longitude ?? 0.0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              _HeroHeader(
                name: place.name,
                rating: rating,
                videoCount: videoCount,
                halalStatus: place.halalStatus,
                sentiment: place.overallSentiment,
                halalTone: halalTone,
                sentimentTone: sentimentTone,
              ),
              const SizedBox(height: 14),

              _QuickActionsRow(
                onRoute: () {
                  if (!hasLocation) {
                    _toastLocationMissing(context);
                    return;
                  }
                  _openDirections(context, lat, lng);
                },
                onCopy: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Copied place info (demo)"),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(milliseconds: 1100),
                    ),
                  );
                },
                onReport: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Report (demo)"),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(milliseconds: 1100),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              _SectionTitle(
                title: "Highlights",
                subtitle: "Key AI-extracted signals from TikTok reviews",
                icon: Icons.auto_awesome_rounded,
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TagChip(text: "Halal: ${place.halalStatus}", tone: halalTone),
                  TagChip(text: "Sentiment: ${place.overallSentiment}", tone: sentimentTone),
                  TagChip(text: "Videos: $videoCount"),
                  TagChip(text: "AI Rating: ${rating.toStringAsFixed(1)}"),
                  if (!hasLocation) TagChip(text: "Location: pending"),
                ],
              ),

              const SizedBox(height: 16),

              _SectionTitle(
                title: "Food tags",
                subtitle: "Most mentioned dishes / categories",
                icon: Icons.local_dining_rounded,
              ),
              const SizedBox(height: 10),

              if (place.foodTagsTop.isEmpty)
                const _EmptyHintCard(
                  icon: Icons.label_off_rounded,
                  title: "No tags yet",
                  subtitle: "Once you add videos, AI will extract popular dishes and categories.",
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: place.foodTagsTop.take(18).map((t) => TagChip(text: t)).toList(),
                ),

              const SizedBox(height: 18),

              _SectionTitle(
                title: "Pros",
                subtitle: "What creators liked",
                icon: Icons.thumb_up_alt_outlined,
              ),
              const SizedBox(height: 10),

              if (place.topPros.isEmpty)
                const _EmptyHintCard(
                  icon: Icons.sentiment_neutral_rounded,
                  title: "No pros extracted yet",
                  subtitle: "Submit TikTok links and we’ll summarize creator opinions here.",
                )
              else
                _BulletCard(
                  items: place.topPros,
                  accent: const Color(0xFF16A34A),
                ),

              const SizedBox(height: 18),

              _SectionTitle(
                title: "Cons",
                subtitle: "What creators complained about",
                icon: Icons.thumb_down_alt_outlined,
              ),
              const SizedBox(height: 10),

              if (place.topCons.isEmpty)
                const _EmptyHintCard(
                  icon: Icons.sentiment_satisfied_alt_rounded,
                  title: "No cons extracted yet",
                  subtitle: "If creators mention negatives, they will appear here automatically.",
                )
              else
                _BulletCard(
                  items: place.topCons,
                  accent: const Color(0xFFDC2626),
                ),

              const SizedBox(height: 18),

              _PrimaryCTA(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Add a TikTok review from the Submit tab"),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(milliseconds: 1300),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

ChipTone _toneForHalal(String halalStatus) {
  final s = halalStatus.toLowerCase().trim();
  if (s.contains("not")) return ChipTone.warn;
  if (s.contains("unclear") || s.contains("unknown")) return ChipTone.warn;
  if (s.contains("halal")) return ChipTone.warn;
  return ChipTone.warn;
}

ChipTone _toneForSentiment(String sentiment) {
  final s = sentiment.toLowerCase().trim();
  if (s.contains("negative")) return ChipTone.warn;
  if (s.contains("neutral")) return ChipTone.warn;
  if (s.contains("positive")) return ChipTone.warn;
  return ChipTone.warn;
}

// --- UI components (unchanged below) ------------------------------------------

class _HeroHeader extends StatelessWidget {
  final String name;
  final double rating;
  final int videoCount;
  final String halalStatus;
  final String sentiment;
  final ChipTone halalTone;
  final ChipTone sentimentTone;

  const _HeroHeader({
    required this.name,
    required this.rating,
    required this.videoCount,
    required this.halalStatus,
    required this.sentiment,
    required this.halalTone,
    required this.sentimentTone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.r22),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A020617),
            blurRadius: 28,
            offset: Offset(0, 14),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AvatarBadge(text: _initials(name)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "• 🎥 $videoCount",
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TagChip(text: "Halal: $halalStatus", tone: halalTone),
              TagChip(text: "Sentiment: $sentiment", tone: sentimentTone),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "AI Summary will appear here.\nSubmit TikTok links to generate insights.",
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r"\s+")).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return "MM";
    final a = parts.first.isNotEmpty ? parts.first[0] : "M";
    final b = parts.length >= 2 ? parts[1][0] : (parts.first.length >= 2 ? parts.first[1] : "M");
    return (a + b).toUpperCase();
  }
}

class _AvatarBadge extends StatelessWidget {
  final String text;
  const _AvatarBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.primary.withOpacity(0.12);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.22)),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onRoute;
  final VoidCallback onCopy;
  final VoidCallback onReport;

  const _QuickActionsRow({
    required this.onRoute,
    required this.onCopy,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.directions_rounded,
            title: "Route",
            subtitle: "Open maps",
            onTap: onRoute,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.copy_all_rounded,
            title: "Copy",
            subtitle: "Place info",
            onTap: onCopy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.flag_outlined,
            title: "Report",
            subtitle: "Wrong data",
            onTap: onReport,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.text),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BulletCard extends StatelessWidget {
  final List<String> items;
  final Color accent;

  const _BulletCard({
    required this.items,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final safeItems = items.where((e) => e.trim().isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(safeItems.length, (i) {
            final text = safeItems[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i == safeItems.length - 1 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.85),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PrimaryCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _PrimaryCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x22020617), blurRadius: 22, offset: Offset(0, 10)),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          "Add a TikTok review",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 46,
        height: 46,
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _EmptyNotFoundState extends StatelessWidget {
  const _EmptyNotFoundState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined, size: 34),
              SizedBox(height: 10),
              Text("Place not found", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              SizedBox(height: 6),
              Text("Go back and try another place.", textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHintCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyHintCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFDA4AF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 34),
              const SizedBox(height: 10),
              const Text(
                "Something went wrong",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Retry"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r"\s+")).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return "MM";
  final first = parts.first;
  final second = parts.length > 1 ? parts[1] : first;
  final a = first.isNotEmpty ? first[0] : "M";
  final b = second.isNotEmpty ? second[0] : "M";
  final s = (a + b).toUpperCase();
  return s.replaceAll(RegExp(r"[^A-Z]"), "M");
}