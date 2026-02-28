import 'dart:async';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../home/home_shell.dart';

/// SplashScreen
/// - Keeps your existing auth boot flow (ensureAnon -> HomeShell)
/// - Improves UI (brand header, animated glow, progress, rotating tips)
/// - Fix: animation now stays visible (minimum splash duration + phase timing)
/// - Safe: no external assets required
/// - 200+ lines (not reduced)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // ---- Boot flow (kept) ----
  bool _bootStarted = false;

  // ---- Timing controls (NEW) ----
  // This prevents “split second” splash on fast devices / cached anon sign-in.
  static const Duration _minSplashDuration = Duration(milliseconds: 1900);
  final Stopwatch _stopwatch = Stopwatch();

  // ---- UI state ----
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _pulse;
  late final Animation<double> _slideUp;
  late final Animation<double> _shine;

  // A tiny “loading narrative” for hackathon polish.
  final List<String> _tips = const [
    "Loading nearby places…",
    "Syncing FoodTok insights…",
    "Preparing map markers…",
    "Warming up AI pipeline…",
    "Checking halal tags…",
    "Almost there…",
  ];

  int _tipIndex = 0;
  Timer? _tipTimer;

  // Simulated progress so users feel forward motion.
  // This does NOT represent real backend progress; it’s UI polish.
  double _progress = 0.08;
  Timer? _progressTimer;

  // Optional: show small status text without being too technical.
  String _status = "Starting…";

  // Just to avoid timer updates after we are done navigating
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();

    // Start stopwatch immediately to enforce minimum splash visibility.
    _stopwatch.start();

    // Animation controller for subtle motion
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    );

    // Entrance fade (single-run) + ongoing pulse (repeat)
    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
    );

    _slideUp = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    // Pulse loops gently
    _pulse = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 1.0, curve: Curves.easeInOut),
      ),
    );

    // A subtle “shine” alpha for the logo / card
    _shine = Tween<double>(begin: 0.10, end: 0.28).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Run entrance once, then repeat pulse.
    _controller.forward().whenComplete(() {
      if (!mounted) return;
      // Repeat for ongoing pulse once entrance is done.
      _controller.repeat(reverse: true);
    });

    // Start UI timers (tips + progress)
    _startTipRotation();
    _startProgressPulse();

    // Keep your boot logic
    _go();
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _progressTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTipRotation() {
    _tipTimer?.cancel();
    _tipTimer = Timer.periodic(const Duration(milliseconds: 1150), (t) {
      if (!mounted || _isNavigating) return;
      setState(() {
        _tipIndex = (_tipIndex + 1) % _tips.length;
      });
    });
  }

  void _startProgressPulse() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 180), (t) {
      if (!mounted || _isNavigating) return;

      // Move progress forward gently but never hit 1.0 until navigation.
      final next = _progress + 0.007;
      setState(() {
        _progress = next.clamp(0.08, 0.92);
      });
    });
  }

  Future<void> _ensureMinSplashTime() async {
    // If auth is fast, we still show splash long enough to see animation.
    final elapsed = _stopwatch.elapsed;
    final remaining = _minSplashDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> _go() async {
    // Guard: only run once
    if (_bootStarted) return;
    _bootStarted = true;

    try {
      if (mounted) {
        setState(() => _status = "Signing you in…");
      }

      // Your existing auth boot
      await AuthService.ensureAnon();

      // Enforce minimum splash duration so animation is visible
      await _ensureMinSplashTime();

      if (!mounted) return;
      setState(() => _status = "Launching…");

      // Smooth finish animation (small polish delay)
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;

      // Force progress to near-complete so user sees “done”
      setState(() => _progress = 0.98);

      // Another tiny delay so the progress bar visibly fills
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;

      // Stop timers before navigation to avoid setState after pushReplacement
      _isNavigating = true;
      _tipTimer?.cancel();
      _progressTimer?.cancel();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } catch (_) {
      // If anything fails, show a friendly retry UI instead of crashing.
      if (!mounted) return;
      setState(() => _status = "Something went wrong. Tap to retry.");
      _progressTimer?.cancel();
      _tipTimer?.cancel();
    }
  }

  // ---- UI helpers ----

  Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

  LinearGradient _backgroundGradient(BuildContext context) {
    final base = Theme.of(context).colorScheme;
    // Slightly “Google-ish” modern dark vibe
    final c1 = _mix(const Color(0xFF0B0F1A), base.primary.withOpacity(0.18), 0.42);
    final c2 = _mix(const Color(0xFF0B1220), base.secondary.withOpacity(0.16), 0.30);
    final c3 = _mix(const Color(0xFF070A12), base.primary.withOpacity(0.12), 0.28);

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c1, c2, c3],
      stops: const [0.0, 0.54, 1.0],
    );
  }

  Widget _brandMark(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Simple “pin + play” style logo, no assets needed
    return ScaleTransition(
      scale: _pulse,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient shine ring
          AnimatedBuilder(
            animation: _shine,
            builder: (context, _) {
              return Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(_shine.value),
                ),
              );
            },
          ),
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  cs.primary.withOpacity(0.98),
                  cs.secondary.withOpacity(0.94),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withOpacity(0.25),
                  blurRadius: 22,
                  spreadRadius: 2,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Pin-ish ring
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.88),
                        width: 2,
                      ),
                    ),
                  ),
                  // Play triangle
                  Transform.translate(
                    offset: const Offset(2, 0),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 34,
                      color: Colors.white.withOpacity(0.96),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleBlock(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _fadeIn,
      child: Transform.translate(
        offset: Offset(0, _slideUp.value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "MakanMap",
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Discover food spots from short-form reviews,\norganized on the map.",
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.white.withOpacity(0.78),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _fadeIn,
      child: AnimatedBuilder(
        animation: _shine,
        builder: (context, _) {
          final borderAlpha = (0.10 + _shine.value * 0.40).clamp(0.10, 0.24);
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(borderAlpha)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status row
                Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: cs.secondary.withOpacity(0.95),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.90),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 10,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      cs.primary.withOpacity(0.95),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Rotating “tip”
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Text(
                    _tips[_tipIndex],
                    key: ValueKey(_tipIndex),
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.72),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _footerNote(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _fadeIn,
      child: Column(
        children: [
          Text(
            "Powered by Firebase • Google Maps",
            style: textTheme.bodySmall?.copyWith(
              color: Colors.white.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Prototype build",
            style: textTheme.labelSmall?.copyWith(
              color: Colors.white.withOpacity(0.40),
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tapToRetryOverlay(BuildContext context) {
    // If boot failed, allow a retry tap anywhere.
    final failed = _status.toLowerCase().contains("retry");
    if (!failed) return const SizedBox.shrink();

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _status = "Retrying…";
              _progress = 0.10;
              _tipIndex = 0;
            });

            _isNavigating = false;
            _stopwatch
              ..reset()
              ..start();

            _startTipRotation();
            _startProgressPulse();
            _bootStarted = false;
            _go();
          },
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Text(
                "Tap to retry",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.92),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Build ----
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;
    final safeBottom = media.padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          DecoratedBox(
            decoration: BoxDecoration(gradient: _backgroundGradient(context)),
            child: const SizedBox.expand(),
          ),

          // Subtle “glow” spots
          Positioned(
            top: -120,
            left: -90,
            child: _GlowBlob(
              diameter: 260,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
            ),
          ),
          Positioned(
            bottom: -140,
            right: -110,
            child: _GlowBlob(
              diameter: 320,
              color: Theme.of(context).colorScheme.secondary.withOpacity(0.14),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                22,
                18 + safeTop * 0.05,
                22,
                18 + safeBottom * 0.15,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _brandMark(context),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: _slideUp,
                    builder: (context, _) => _titleBlock(context),
                  ),
                  const Spacer(),

                  // Status + progress
                  _statusCard(context),

                  const SizedBox(height: 18),

                  // Native progress indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context)
                                .colorScheme
                                .secondary
                                .withOpacity(0.95),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Loading…",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withOpacity(0.65),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  _footerNote(context),
                ],
              ),
            ),
          ),

          // Retry overlay if boot fails
          _tapToRetryOverlay(context),
        ],
      ),
    );
  }
}

/// A soft glowing blob for background ambience.
class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.diameter,
    required this.color,
  });

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withOpacity(0.0),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}