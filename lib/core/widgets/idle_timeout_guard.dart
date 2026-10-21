import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

const _kIdleTimeout = Duration(minutes: 20);
const _kWarnBefore = Duration(seconds: 60);

/// Web-only: signs an idle authenticated session out after 20 minutes with no
/// pointer/keyboard activity, warning 60 seconds beforehand (any activity
/// during the warning cancels it). Wraps `MaterialApp.router`'s `builder` —
/// not a single route — so it sees activity on every screen, including ones
/// `Navigator.push`ed on top of the shell (e.g. Company Master), which live
/// outside whatever go_router currently thinks is the matched route.
///
/// Native builds are untouched on purpose: a POS tablet sitting idle between
/// orders is normal staff workflow, not the unattended-browser-tab risk this
/// guards against (see conversation — user asked for web only).
class IdleTimeoutGuard extends ConsumerStatefulWidget {
  final Widget child;
  const IdleTimeoutGuard({super.key, required this.child});

  @override
  ConsumerState<IdleTimeoutGuard> createState() => _IdleTimeoutGuardState();
}

class _IdleTimeoutGuardState extends ConsumerState<IdleTimeoutGuard> {
  Timer? _timer;
  OverlayEntry? _warningEntry;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _warningEntry?.remove();
    if (kIsWeb) HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    _registerActivity();
    return false; // never swallow the key — this only observes
  }

  bool get _isSignedIn => ref.read(authStateProvider).value != null;

  /// Any detected activity — a pointer event, a keystroke, a rebuild that
  /// notices sign-in state changed — cancels whatever phase we're in
  /// (idle-countdown or warning) and restarts the 20-minute clock from zero.
  void _registerActivity() {
    if (!kIsWeb || !mounted) return;
    _warningEntry?.remove();
    _warningEntry = null;
    _timer?.cancel();
    if (!_isSignedIn) return; // nothing to guard on the login/owner screens
    _timer = Timer(_kIdleTimeout - _kWarnBefore, _startWarningPhase);
  }

  /// 60 seconds of true inactivity have elapsed. The countdown banner is a
  /// best-effort courtesy — the actual sign-out below is scheduled
  /// unconditionally, so a failed overlay insert never silently cancels the
  /// real timeout.
  void _startWarningPhase() {
    if (!mounted || !_isSignedIn) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) {
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => _IdleWarningBanner(duration: _kWarnBefore, onStay: _registerActivity),
      );
      _warningEntry = entry;
      overlay.insert(entry);
    }
    _timer = Timer(_kWarnBefore, _signOutForInactivity);
  }

  void _signOutForInactivity() {
    _warningEntry?.remove();
    _warningEntry = null;
    if (!_isSignedIn) return;
    ref.read(authStateProvider.notifier).signOut();
    ref
        .read(sessionKickProvider.notifier)
        .set("You've been signed out after 20 minutes of inactivity.");
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;

    // Re-arms the very moment sign-in state flips — e.g. right after login,
    // or on a fresh page load where a persisted session resolves before the
    // first mouse move.
    ref.listen(authStateProvider, (_, _) => _registerActivity());
    // Covers the edge case where auth had *already* resolved before this
    // widget's first build (ref.listen only catches future transitions).
    _registerActivity();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _registerActivity(),
      onPointerMove: (_) => _registerActivity(),
      onPointerHover: (_) => _registerActivity(),
      onPointerSignal: (_) => _registerActivity(),
      child: widget.child,
    );
  }
}

/// Cosmetic-only countdown; the actual sign-out timer lives in
/// [_IdleTimeoutGuardState] regardless of whether this ever manages to show.
class _IdleWarningBanner extends StatefulWidget {
  final Duration duration;
  final VoidCallback onStay;
  const _IdleWarningBanner({required this.duration, required this.onStay});

  @override
  State<_IdleWarningBanner> createState() => _IdleWarningBannerState();
}

class _IdleWarningBannerState extends State<_IdleWarningBanner> {
  late int _secondsLeft = widget.duration.inSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, widget.duration.inSeconds));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 16,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFF59E0B),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                'Signing out in $_secondsLeft s due to inactivity',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: widget.onStay,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: const Text('Stay signed in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
