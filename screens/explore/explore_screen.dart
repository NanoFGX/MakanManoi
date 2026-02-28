import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/place.dart';
import '../../services/places_service.dart';
import '../../widgets/place_card.dart';
import '../place/place_details_screen.dart';
import '../home/home_shell.dart'; // for ExploreRefreshEvent

class ExploreScreen extends StatefulWidget {
  final ValueNotifier<ExploreRefreshEvent?> exploreEvent;

  const ExploreScreen({super.key, required this.exploreEvent});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> with TickerProviderStateMixin {
  final searchCtrl = TextEditingController();
  String halal = 'All';

  GoogleMapController? mapController;

  MapType _mapType = MapType.normal;
  bool _showTraffic = false;
  bool _showBuildings = true;
  bool _showMyLocation = false;
  bool _isSheetExpanded = false;

  late final AnimationController _fadeController;
  late final Animation<double> _fade;

  Timer? _searchDebounce;
  String _effectiveQuery = '';

  static const CameraPosition _initial = CameraPosition(
    target: LatLng(3.1390, 101.6869),
    zoom: 10,
  );

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _effectiveQuery = searchCtrl.text;

    // ✅ Listen for "submit finished" events
    widget.exploreEvent.addListener(_onExploreEvent);
  }

  @override
  void dispose() {
    widget.exploreEvent.removeListener(_onExploreEvent);
    _searchDebounce?.cancel();
    searchCtrl.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onExploreEvent() {
    final ev = widget.exploreEvent.value;
    if (ev == null) return;

    // show toast
    if (ev.toast != null && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ev.toast!),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1100),
        ),
      );
    }

    // We'll store the target placeId temporarily in state:
    setState(() => _pendingFocusPlaceId = ev.placeId);
  }

  String? _pendingFocusPlaceId;

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _effectiveQuery = v.trim());
    });
  }

  void _openPlace(BuildContext context, String placeId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaceDetailsScreen(placeId: placeId)),
    );
  }

  Future<void> _openDirectionsToPlace(Place p) async {
    // ✅ FIX: location is nullable
    if (p.location == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This place has no pinned location yet."),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1200),
        ),
      );
      return;
    }

    final lat = p.location!.latitude;
    final lng = p.location!.longitude;

    final uri = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving",
    );

    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (!mounted) return;
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

  Widget _pill({
    required String text,
    required VoidCallback onTap,
    bool primary = false,
    IconData? icon,
  }) {
    final bg = primary ? AppColors.primary : Colors.white;
    final fg = primary ? Colors.white : AppColors.text;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 42,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: primary ? Colors.transparent : AppColors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A020617),
              blurRadius: 18,
              offset: Offset(0, 8),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onNearMe() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Near me: enable location permission later (MVP placeholder)."),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: 1400),
      ),
    );
  }

  void _onLayers() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.r22)),
      builder: (_) => _LayersSheet(
        mapType: _mapType,
        showTraffic: _showTraffic,
        showBuildings: _showBuildings,
        onChanged: (next) {
          setState(() {
            _mapType = next.mapType;
            _showTraffic = next.traffic;
            _showBuildings = next.buildings;
          });
        },
      ),
    );
  }

  void _onFilter() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.r22)),
      builder: (_) => _FilterSheet(
        halal: halal,
        onHalalChanged: (v) => setState(() => halal = v),
      ),
    );
  }

  // ✅ When a submit happens, and the place appears in stream, we focus it
  Future<void> _maybeFocusNewPlace(List<Place> places) async {
    final targetId = _pendingFocusPlaceId;
    if (targetId == null) return;
    if (mapController == null) return;

    final match = places.where((p) => p.id == targetId).toList();
    if (match.isEmpty) return;

    final p = match.first;

    // ✅ FIX: if no location yet, don't crash, just consume focus
    if (p.location == null) {
      _pendingFocusPlaceId = null;
      return;
    }

    final pos = LatLng(p.location!.latitude, p.location!.longitude);

    _pendingFocusPlaceId = null; // consume once

    await mapController!.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 15)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MakanManoi", style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Notifications (demo)"),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(milliseconds: 900),
                ),
              );
            },
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fade,
        child: StreamBuilder<List<Place>>(
          // ✅ This call is correct for your PlacesService.dart
          stream: PlacesService.streamFiltered(query: _effectiveQuery, halalFilter: halal),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorState(
                message: "Failed to load places.\n${snap.error}",
                onRetry: () => setState(() {}),
              );
            }

            final isLoading = snap.connectionState == ConnectionState.waiting;
            final places = snap.data ?? [];

            // ✅ focus newly submitted place (when it arrives)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _maybeFocusNewPlace(places);
            });

            final markers = places
                .where((p) => p.location != null)
                .map((p) {
              final pos = LatLng(p.location!.latitude, p.location!.longitude);
              return Marker(
                markerId: MarkerId(p.id),
                position: pos,
                infoWindow: InfoWindow(
                  title: p.name,
                  snippet: "⭐ ${p.rating.toStringAsFixed(1)} • 🎥 ${p.videoCount}",
                  onTap: () => _openPlace(context, p.id),
                ),
              );
            }).toSet();

            return Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.r18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(AppRadii.r18),
                        ),
                        child: Stack(
                          children: [
                            GoogleMap(
                              initialCameraPosition: _initial,
                              markers: markers,
                              mapType: _mapType,
                              trafficEnabled: _showTraffic,
                              buildingsEnabled: _showBuildings,
                              myLocationEnabled: _showMyLocation,
                              myLocationButtonEnabled: false,
                              compassEnabled: true,
                              zoomControlsEnabled: false,
                              onMapCreated: (c) => mapController = c,
                            ),
                            if (isLoading)
                              const Positioned(
                                left: 10,
                                top: 10,
                                child: _LoadingChip(text: "Loading places…"),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 22,
                  left: 20,
                  right: 20,
                  child: Row(
                    children: [
                      Expanded(
                        child: _pill(
                          primary: true,
                          text: "Near me",
                          icon: Icons.place_outlined,
                          onTap: _onNearMe,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _pill(
                          text: "Layers",
                          icon: Icons.layers_outlined,
                          onTap: _onLayers,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _pill(
                          text: "Filter",
                          icon: Icons.tune_rounded,
                          onTap: _onFilter,
                        ),
                      ),
                    ],
                  ),
                ),
                _ExploreDraggableSheet(
                  searchCtrl: searchCtrl,
                  halal: halal,
                  isLoading: isLoading,
                  places: places,
                  onView: (id) => _openPlace(context, id),
                  onSearchChanged: _onSearchChanged,
                  onHalalChanged: (v) => setState(() => halal = v),
                  onExpandedChanged: (v) => setState(() => _isSheetExpanded = v),
                  isExpanded: _isSheetExpanded,
                  onRoute: (p) => _openDirectionsToPlace(p),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExploreDraggableSheet extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String halal;
  final bool isLoading;
  final List<Place> places;
  final ValueChanged<String> onView;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onHalalChanged;
  final ValueChanged<bool> onExpandedChanged;
  final bool isExpanded;
  final ValueChanged<Place> onRoute;

  const _ExploreDraggableSheet({
    required this.searchCtrl,
    required this.halal,
    required this.isLoading,
    required this.places,
    required this.onView,
    required this.onSearchChanged,
    required this.onHalalChanged,
    required this.onExpandedChanged,
    required this.isExpanded,
    required this.onRoute,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.22,
      maxChildSize: 0.62,
      snap: true,
      snapSizes: const [0.28, 0.45, 0.62],
      builder: (context, scrollController) {
        scrollController.addListener(() {
          if (!scrollController.hasClients) return;
          final expandedNow = scrollController.offset > 12;
          if (expandedNow != isExpanded) onExpandedChanged(expandedNow);
        });

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.r22),
                  border: Border.all(color: AppColors.line),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A020617),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                "Explore",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: [
                          TextField(
                            controller: searchCtrl,
                            onChanged: onSearchChanged,
                            textInputAction: TextInputAction.search,
                            decoration: const InputDecoration(
                              labelText: "Search (place or tag)",
                              hintText: "ayam_gepuk, ramen, coffee…",
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: halal,
                            items: const [
                              DropdownMenuItem(value: 'All', child: Text("All")),
                              DropdownMenuItem(value: 'halal', child: Text("Halal-likely")),
                              DropdownMenuItem(value: 'unclear', child: Text("Unclear")),
                              DropdownMenuItem(value: 'not_halal', child: Text("Not halal")),
                            ],
                            onChanged: (v) => onHalalChanged(v ?? 'All'),
                            decoration: const InputDecoration(
                              labelText: "Halal filter",
                              prefixIcon: Icon(Icons.verified_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (isLoading) const _LoadingChip(text: "Syncing…"),
                              if (!isLoading)
                                _InfoChip(
                                  icon: Icons.place_outlined,
                                  text: "${places.length} place(s)",
                                ),
                              const SizedBox(width: 8),
                              if (!isLoading)
                                _InfoChip(
                                  icon: Icons.tune_rounded,
                                  text: halal == 'All' ? "Any halal" : halal,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!isLoading && places.isEmpty) ...[
                            const SizedBox(height: 10),
                            const _EmptyState(
                              title: "No places yet",
                              subtitle: "Try a different search or set halal to All.",
                            ),
                          ] else ...[
                            ListView.separated(
                              itemCount: places.length,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final p = places[i];
                                return PlaceCard(
                                  place: p,
                                  onView: () => onView(p.id),
                                  onRoute: () => onRoute(p),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------- sheets / widgets unchanged ----------
class _LayersSheetSelection {
  final MapType mapType;
  final bool traffic;
  final bool buildings;

  const _LayersSheetSelection({
    required this.mapType,
    required this.traffic,
    required this.buildings,
  });
}

class _LayersSheet extends StatelessWidget {
  final MapType mapType;
  final bool showTraffic;
  final bool showBuildings;
  final ValueChanged<_LayersSheetSelection> onChanged;

  const _LayersSheet({
    required this.mapType,
    required this.showTraffic,
    required this.showBuildings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          const Text("Map layers", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          _RadioTile(
            title: "Normal",
            subtitle: "Default map style",
            selected: mapType == MapType.normal,
            onTap: () => onChanged(_LayersSheetSelection(mapType: MapType.normal, traffic: showTraffic, buildings: showBuildings)),
          ),
          _RadioTile(
            title: "Satellite",
            subtitle: "Satellite imagery",
            selected: mapType == MapType.satellite,
            onTap: () => onChanged(_LayersSheetSelection(mapType: MapType.satellite, traffic: showTraffic, buildings: showBuildings)),
          ),
          _RadioTile(
            title: "Terrain",
            subtitle: "Terrain emphasis",
            selected: mapType == MapType.terrain,
            onTap: () => onChanged(_LayersSheetSelection(mapType: MapType.terrain, traffic: showTraffic, buildings: showBuildings)),
          ),
          const Divider(height: 18),
          SwitchListTile(
            value: showTraffic,
            onChanged: (v) => onChanged(_LayersSheetSelection(mapType: mapType, traffic: v, buildings: showBuildings)),
            title: const Text("Traffic"),
            subtitle: const Text("Show live traffic layer (when available)"),
            secondary: const Icon(Icons.traffic_rounded),
          ),
          SwitchListTile(
            value: showBuildings,
            onChanged: (v) => onChanged(_LayersSheetSelection(mapType: mapType, traffic: showTraffic, buildings: v)),
            title: const Text("3D Buildings"),
            subtitle: const Text("Show buildings (supported areas)"),
            secondary: const Icon(Icons.location_city_outlined),
          ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  final String halal;
  final ValueChanged<String> onHalalChanged;

  const _FilterSheet({required this.halal, required this.onHalalChanged});

  @override
  Widget build(BuildContext context) {
    final options = const [
      ('All', 'All'),
      ('halal', 'Halal-Certified'),
      ('unclear', 'Unclear'),
      ('not_halal', 'Not halal'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          const Text("Filter places", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: options.map((e) {
              final value = e.$1;
              final label = e.$2;
              final selected = halal == value;
              return ChoiceChip(
                selected: selected,
                label: Text(label),
                onSelected: (_) => onHalalChanged(value),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: halal,
            items: options.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
            onChanged: (v) => onHalalChanged(v ?? 'All'),
            decoration: const InputDecoration(
              labelText: "Halal filter (exact)",
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingChip extends StatelessWidget {
  final String text;
  const _LoadingChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      label: Text(text),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
    );
  }
}

class _RadioTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RadioTile({required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check_rounded) : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_off_rounded, size: 26),
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

  const _ErrorState({required this.message, required this.onRetry});

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
              const Text("Something went wrong", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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