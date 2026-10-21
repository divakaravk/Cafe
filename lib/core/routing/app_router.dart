import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../home_shell.dart';
import '../../providers/providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/owner_dashboard_screen.dart';

/// Bridges [authStateProvider] to [GoRouter.refreshListenable]. Sign-in,
/// sign-out and the session guard's forced logout (providers.dart's
/// `AuthNotifier`) all just flip that provider's state and rely on a reactive
/// rebuild — never an explicit navigation call. Without this bridge the
/// router would never notice and the URL would silently drift from what's
/// actually on screen.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}

final _authRefreshProvider = Provider<_AuthRefreshNotifier>((ref) {
  final notifier = _AuthRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Real, bookmarkable, back/refresh-safe URLs for the app's three top-level
/// states — signed out, owner, and signed-in company user
/// (docs/web-view/PLAN.md Phase W2).
///
/// Scope note: everything *inside* the signed-in shell (the POS/Tables/Bills
/// tabs, and the admin master screens `AuthenticatedShell` pushes from its
/// nav panel — Company/Table/User/Item Master, My Profile, Kitchen Monitor)
/// is deliberately untouched: still reached via the existing
/// `setState`/`Navigator.push` calls under the single `/` route, not their
/// own URLs. Rewiring 4000+ lines of order-taking/billing/KOT navigation to
/// go_router's `StatefulShellRoute` is the higher-risk half of this work —
/// this pass fixes "no URLs, no working back/refresh" at the app-shell level
/// (auth gating) first, without touching business-critical in-app navigation
/// that can't be verified without a live logged-in click-through.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_authRefreshProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final atLogin = state.matchedLocation == '/login';

      return authState.when(
        data: (user) {
          if (user == null) return atLogin ? null : '/login';
          // The app owner isn't tied to a company — the registration
          // approvals dashboard, never the POS shell.
          if (user.isOwner) {
            return state.matchedLocation == '/owner' ? null : '/owner';
          }
          if (atLogin || state.matchedLocation == '/owner') return '/';
          return null;
        },
        // Resolving the stored session (cold start) — hold at whatever
        // matched first (initialLocation defaults to /login) instead of
        // bouncing mid-resolve, mirroring the old `orElse: () =>
        // LoginScreen()` behavior.
        loading: () => null,
        error: (_, _) => atLogin ? null : '/login',
      );
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/owner',
        builder: (context, state) {
          final user = ref.read(authStateProvider).value;
          // The redirect above guarantees this only while `user` is briefly
          // still catching up mid-transition; never a real dead end.
          if (user == null) return const SizedBox.shrink();
          return OwnerDashboardScreen(owner: user);
        },
      ),
      GoRoute(
        path: '/',
        builder: (context, state) {
          final user = ref.read(authStateProvider).value;
          if (user == null) return const SizedBox.shrink();
          return AuthenticatedShell(user: user);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Page not found'),
            const SizedBox(height: 12),
            TextButton(onPressed: () => context.go('/'), child: const Text('Go back')),
          ],
        ),
      ),
    ),
  );
});
