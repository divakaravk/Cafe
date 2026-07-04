import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/api_helper.dart';
import '../../../providers/providers.dart';
import 'company_registration_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _triggerShake = false; // Triggers shake on credential pre-fill

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn({bool force = false}) async {
    if (!force &&
        (_emailController.text.trim().isEmpty ||
            _passwordController.text.isEmpty)) {
      AppFeedback.toast(
        context,
        'Please enter username/email and password',
        isError: true,
      );
      setState(() => _triggerShake = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _triggerShake = false);
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authStateProvider.notifier)
          .signIn(
            _emailController.text.trim(),
            _passwordController.text,
            force: force,
          );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAlreadyLoggedIn() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.devices_rounded,
                color: AppColors.warning,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Already Signed In',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? AppColors.textWhite : AppColors.textDark,
              ),
            ),
          ],
        ),
        content: Text(
          'This account is already active on another device.\n\nSigning in here will end the session on that device.',
          style: GoogleFonts.outfit(
            fontSize: 13,
            height: 1.6,
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAmber,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.login_rounded, size: 16),
            label: Text(
              'Sign In Anyway',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _signIn(force: true);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good afternoon';
    } else if (hour >= 17 && hour < 22) {
      return 'Good evening';
    } else {
      return 'Welcome back';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 850;

    // The session guard logs the user out (inactive / another device) and
    // routes here — surface its reason as a top toast, then clear it.
    ref.listen(sessionKickProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        AppFeedback.toast(context, next, isError: true);
        ref.read(sessionKickProvider.notifier).clear();
      }
    });

    ref.listen(authStateProvider, (prev, next) {
      if (next is AsyncError) {
        final err = next.error.toString();

        if (err == 'ALREADY_LOGGED_IN') {
          // Show "already signed in" dialog — no shake/snackbar
          _handleAlreadyLoggedIn();
          return;
        }

        // Show clean business messages (e.g. deactivated account) as-is;
        // prefix only unexpected technical errors.
        final friendly =
            (err.toLowerCase().contains('inactive') ||
                err.toLowerCase().contains('deactivat') ||
                err.toLowerCase().contains('password') ||
                err.toLowerCase().contains('not found'))
            ? err
            : 'Login failed: $err';
        AppFeedback.toast(context, friendly, isError: true);
        setState(() => _triggerShake = true);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _triggerShake = false);
        });
      }
    });

    return Scaffold(
      body: AmbientBackground(
        child: Container(
          color: isDark
              ? Colors.black.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.4),
          child: isDesktop
              ? Row(
                  children: [
                    // Brand Panel
                    Expanded(
                      flex: 11,
                      child: BrandIntroductionPanel(greeting: _getGreeting()),
                    ),
                    // Login Panel
                    Expanded(
                      flex: 9,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(40),
                          child: _buildLoginForm(isDark, true),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildLoginForm(isDark, false),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(bool isDark, bool isDesktopMode) {
    return Container(
          width: isDesktopMode ? 460 : double.infinity,
          padding: EdgeInsets.all(isDesktopMode ? 48 : 32),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark
                  ? AppColors.darkBorder.withValues(alpha: 0.25)
                  : AppColors.lightBorder.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : AppColors.primaryAmber)
                    .withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo / Greeting Header
              Center(
                child: Column(
                  children: [
                    // Glowing Logo Badge
                    Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.primaryAmber,
                                AppColors.primaryOrange,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryAmber.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.restaurant_rounded,
                            size: 38,
                            color: Colors.white,
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          end: const Offset(1, 1),
                          duration: 400.ms,
                          curve: Curves.easeOutBack,
                        ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to your café dashboard',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted,
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // Email Input
              FocusableTextField(
                    controller: _emailController,
                    label: 'Username or Email',
                    prefixIcon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    suffixIcon: _emailController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              setState(() => _emailController.clear());
                            },
                          )
                        : null,
                  )
                  .animate()
                  .fadeIn(delay: 250.ms, duration: 400.ms)
                  .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),

              const SizedBox(height: 20),

              // Password Input
              FocusableTextField(
                    controller: _passwordController,
                    label: 'Password',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _signIn(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 350.ms, duration: 400.ms)
                  .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),

              const SizedBox(height: 32),

              // Submit Button
              ScaleButton(
                    onTap: _signIn,
                    isLoading: _isLoading,
                    child: Text(
                      'Sign In',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 450.ms, duration: 400.ms)
                  .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),

              const SizedBox(height: 24),

              // New company registration entry point
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'New here?',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CompanyRegistrationScreen(),
                        ),
                      ),
                      child: Text(
                        'Register your company',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
            ],
          ),
        )
        .animate(target: _triggerShake ? 1 : 0)
        .shake(hz: 8, curve: Curves.easeInOutCubic, duration: 400.ms);
  }
}

// ─── AMBIENT BACKGROUND WITH DRIFTING BLOBS ─────────────────────────
class AmbientBackground extends StatefulWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _AmbientPainter(_controller.value),
          child: widget.child,
        );
      },
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final double progress;
  _AmbientPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120);

    // Orb 1: Warm Amber (top leftish)
    final x1 = size.width * (0.22 + 0.14 * sin(progress * 2 * pi));
    final y1 = size.height * (0.28 + 0.12 * cos(progress * 2 * pi));
    final r1 = min(size.width, size.height) * 0.42;
    paint.color = const Color(0xFFFF8F00).withValues(alpha: 0.15);
    canvas.drawCircle(Offset(x1, y1), r1, paint);

    // Orb 2: Coral Rose (bottom rightish)
    final x2 = size.width * (0.78 + 0.11 * cos(progress * 2 * pi + pi / 2));
    final y2 = size.height * (0.72 + 0.14 * sin(progress * 2 * pi + pi / 2));
    final r2 = min(size.width, size.height) * 0.46;
    paint.color = const Color(0xFFFF6E40).withValues(alpha: 0.13);
    canvas.drawCircle(Offset(x2, y2), r2, paint);

    // Orb 3: Golden Bronze (center bottom)
    final x3 = size.width * (0.50 + 0.16 * sin(progress * 2 * pi + pi));
    final y3 = size.height * (0.82 + 0.08 * cos(progress * 2 * pi + pi));
    final r3 = min(size.width, size.height) * 0.38;
    paint.color = const Color(0xFFFFAB00).withValues(alpha: 0.12);
    canvas.drawCircle(Offset(x3, y3), r3, paint);
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─── CUSTOM GLOWING TEXTFIELD ──────────────────────────────────────
class FocusableTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const FocusableTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<FocusableTextField> createState() => _FocusableTextFieldState();
}

class _FocusableTextFieldState extends State<FocusableTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _hasFocus = _focusNode.hasFocus;
      });
    });
    // Re-render suffix when text changes (like clear button)
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: _hasFocus
            ? [
                BoxShadow(
                  color: AppColors.primaryAmber.withValues(alpha: 0.14),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isDark ? AppColors.textWhite : AppColors.textDark,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: GoogleFonts.outfit(
            color: _hasFocus
                ? AppColors.primaryAmber
                : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted),
            fontWeight: _hasFocus ? FontWeight.w600 : FontWeight.w500,
          ),
          prefixIcon: Icon(
            widget.prefixIcon,
            color: _hasFocus
                ? AppColors.primaryAmber
                : (isDark
                      ? AppColors.textWhiteMuted.withValues(alpha: 0.7)
                      : AppColors.textDarkMuted.withValues(alpha: 0.7)),
          ),
          suffixIcon: widget.suffixIcon,
          filled: true,
          fillColor: isDark
              ? AppColors.darkCard.withValues(alpha: _hasFocus ? 0.95 : 0.65)
              : Colors.white.withValues(alpha: _hasFocus ? 1.0 : 0.85),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: isDark
                  ? AppColors.darkBorder.withValues(alpha: 0.3)
                  : AppColors.lightBorder.withValues(alpha: 0.5),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primaryAmber,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
        ),
      ),
    );
  }
}

// ─── CUSTOM INTERACTIVE BUTTON (SCALE FEEDBACK) ─────────────────────
class ScaleButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isLoading;
  final Widget child;

  const ScaleButton({
    super.key,
    required this.onTap,
    required this.isLoading,
    required this.child,
  });

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) {
    if (!widget.isLoading) {
      setState(() => _scale = 0.96);
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (!widget.isLoading) {
      setState(() => _scale = 1.0);
    }
  }

  void _onTapCancel() {
    if (!widget.isLoading) {
      setState(() => _scale = 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.isLoading ? null : widget.onTap,
      child: Transform.scale(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryAmber, AppColors.primaryOrange],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryOrange.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : widget.child,
        ),
      ),
    );
  }
}

// ─── BRANDING / INTRO CARD FOR DESKTOP VIEW ──────────────────────────
class BrandIntroductionPanel extends StatelessWidget {
  final String greeting;
  const BrandIntroductionPanel({super.key, required this.greeting});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 60),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1B0F0A), const Color(0xFF2E1A11)]
              : [const Color(0xFFFFF6EE), const Color(0xFFFFECE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark
              ? const Color(0xFF3A241A).withValues(alpha: 0.3)
              : const Color(0xFFEEDDCC).withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Logo Tag
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryAmber, AppColors.primaryOrange],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.restaurant_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Rasabhojan',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.textWhite : AppColors.textDark,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ).animate().fadeIn(duration: 400.ms),
          const Spacer(),

          // Big greeting & statement
          Text(
                '$greeting,',
                style: GoogleFonts.outfit(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: isDark ? AppColors.textWhite : AppColors.textDark,
                ),
              )
              .animate()
              .fadeIn(delay: 150.ms, duration: 400.ms)
              .moveX(begin: -15, end: 0),
          const SizedBox(height: 12),
          Text(
                'Let\'s brew something beautiful today.',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              )
              .animate()
              .fadeIn(delay: 250.ms, duration: 400.ms)
              .moveX(begin: -15, end: 0),
          const SizedBox(height: 48),

          // Features cards list
          Column(
            children: [
              _buildFeatureRow(
                    context,
                    icon: Icons.table_bar_rounded,
                    title: 'Dining & Floor Layouts',
                    desc:
                        'Manage seating states, reservations, and dispatch KOTs instantly.',
                    isDark: isDark,
                  )
                  .animate()
                  .fadeIn(delay: 350.ms, duration: 400.ms)
                  .moveY(begin: 12, end: 0),
              const SizedBox(height: 16),
              _buildFeatureRow(
                    context,
                    icon: Icons.point_of_sale_rounded,
                    title: 'High-Speed Checkout',
                    desc:
                        'Generate compliant tax invoices with Cash, Card, and UPI methods.',
                    isDark: isDark,
                  )
                  .animate()
                  .fadeIn(delay: 450.ms, duration: 400.ms)
                  .moveY(begin: 12, end: 0),
              const SizedBox(height: 16),
              _buildFeatureRow(
                    context,
                    icon: Icons.soup_kitchen_rounded,
                    title: 'Kitchen Sync Display',
                    desc:
                        'Real-time ordering ticket queue directly in kitchen modules.',
                    isDark: isDark,
                  )
                  .animate()
                  .fadeIn(delay: 550.ms, duration: 400.ms)
                  .moveY(begin: 12, end: 0),
            ],
          ),

          const Spacer(flex: 2),

          // Coffee Quote footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2A1C14).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF3D2A1F).withValues(alpha: 0.5)
                    : const Color(0xFFF3E5D8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.accentGold,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '"Coffee is a language in itself, speaking clarity to creativity."',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 650.ms, duration: 450.ms),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF24160E).withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF322016).withValues(alpha: 0.3)
              : const Color(0xFFF5E8DC).withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryAmber.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryAmber, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textWhite : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
