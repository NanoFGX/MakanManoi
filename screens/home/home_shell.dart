import 'dart:async';
import 'package:flutter/material.dart';

import '../explore/explore_screen.dart';
import '../submit/submit_screen.dart';

/// HomeShell
/// - Explore + Submit
/// - Live sync: Submit -> notify Explore -> Explore animates + refreshes view
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  int index = 0;

  // 🔥 "event bus" for Explore to react (move camera, show snack, etc.)
  final ValueNotifier<ExploreRefreshEvent?> _exploreEvent = ValueNotifier(null);

  late final List<Widget> pages;

  late final AnimationController _fadeController;
  late final Animation<double> _fade;

  DateTime? _lastBackPressedAt;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _destinations = <_NavItem>[
    _NavItem(
      label: 'Explore',
      icon: Icons.map_outlined,
      selectedIcon: Icons.map,
      tooltip: 'Discover places on the map',
    ),
    _NavItem(
      label: 'Submit',
      icon: Icons.add_circle_outline,
      selectedIcon: Icons.add_circle,
      tooltip: 'Submit a TikTok review',
    ),
  ];

  @override
  void initState() {
    super.initState();

    pages = [
      ExploreScreen(exploreEvent: _exploreEvent),
      SubmitScreen(
        onSubmitted: (result) {
          // ✅ After submit finishes:
          // 1) Jump to Explore tab
          // 2) Notify Explore with the newly updated/created placeId (optional)
          setState(() => index = 0);

          // result is a Map<String, dynamic> from SubmitScreen
          final placeId = (result["placeId"] ?? result["placeID"] ?? result["place_id"])?.toString();
          final toast = (result["toast"] ?? result["message"] ?? "Submitted! Syncing places…").toString();

          _exploreEvent.value = ExploreRefreshEvent(
            placeId: placeId,
            toast: toast,
          );

          _showSnack(toast);
        },
      ),
    ];

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.value = 1.0;
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _exploreEvent.dispose();
    super.dispose();
  }

  void _setIndex(int newIndex) {
    if (newIndex == index) return;
    _fadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() => index = newIndex);
      _fadeController.forward();
    });
  }

  void _showSnack(String msg) {
    final ctx = _scaffoldKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).clearSnackBars();
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _handleBackPressed() async {
    if (index != 0) {
      _setIndex(0);
      return false;
    }

    final now = DateTime.now();
    final last = _lastBackPressedAt;
    _lastBackPressedAt = now;

    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _showSnack("Press back again to exit");
      return false;
    }
    return true;
  }

  Widget _buildBody(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: IndexedStack(
        index: index,
        children: pages,
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).navigationBarTheme.backgroundColor ??
              cs.surface.withOpacity(0.92),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: cs.onSurface.withOpacity(0.06)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: NavigationBar(
            height: 66,
            selectedIndex: index,
            onDestinationSelected: _setIndex,
            destinations: List.generate(_destinations.length, (i) {
              final item = _destinations[i];
              return NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
                tooltip: item.tooltip,
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _handleBackPressed();
        if (shouldExit && mounted) Navigator.of(context).maybePop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        body: _buildBody(context),
        bottomNavigationBar: _buildNavBar(context),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String tooltip;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.tooltip,
  });
}

/// Explore listens to this (move camera, show toast, etc.)
class ExploreRefreshEvent {
  final String? placeId;
  final String? toast;

  ExploreRefreshEvent({this.placeId, this.toast});
}

/// Submit returns this when it successfully writes to Firestore
/// (Kept for compatibility; SubmitScreen now returns a Map via callback)
class SubmitResult {
  final String? placeId;
  final String? toast;

  SubmitResult({this.placeId, this.toast});
}