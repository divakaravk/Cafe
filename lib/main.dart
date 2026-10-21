import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/backend/backend.dart';
import 'core/routing/app_router.dart';
import 'core/services/push_service.dart';
import 'core/widgets/idle_timeout_guard.dart';
import 'providers/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge: app draws behind transparent status & nav bars (like Swiggy/Blinkit)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await Backend.init();
  // Best-effort: enables registration-OTP push on owner/super-admin devices.
  // No-ops gracefully when Firebase isn't configured for the platform yet.
  await PushService.init();
  runApp(const ProviderScope(child: CafePosApp()));
}

class CafePosApp extends ConsumerWidget {
  const CafePosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(isDarkModeProvider);
    // `Provider`-cached (core/routing/app_router.dart) — this watch does NOT
    // rebuild the GoRouter on every theme toggle; it only re-reads the same
    // cached instance, which is required (recreating it would reset in-app
    // navigation history and break browser back/forward on web).
    final router = ref.watch(appRouterProvider);

    // Transparent bars; icon brightness flips with the app theme
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: MaterialApp.router(
        title: 'RasaBhojan',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: router,
        builder: (context, child) =>
            IdleTimeoutGuard(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
