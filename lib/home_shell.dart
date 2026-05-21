import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'core/theme/app_colors.dart';
import 'core/constants/app_constants.dart';
import 'models/models.dart';
import 'providers/providers.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/pos/presentation/modern_pos_screen.dart';
import 'features/pos/presentation/quick_bill_screen.dart';
import 'features/pos/presentation/classic_pos_screen.dart';
import 'features/orders/tables_screen.dart';
import 'features/reports/bills_screen.dart';
import 'features/admin/presentation/company_master_screen.dart';
import 'features/admin/presentation/user_master_screen.dart';
import 'features/admin/presentation/item_master_screen.dart';
import 'features/kitchen/kitchen_screen.dart';
import 'features/admin/presentation/my_profile_screen.dart';

/// Main app shell — switches between login and POS based on auth state
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.maybeWhen(
      data: (user) {
        if (user == null) return const LoginScreen();
        return _AuthenticatedShell(user: user);
      },
      // Keep showing LoginScreen during loading/error if no user is authenticated
      orElse: () => const LoginScreen(),
    );
  }
}

class _AuthenticatedShell extends ConsumerStatefulWidget {
  final UserProfile user;
  const _AuthenticatedShell({required this.user});

  @override
  ConsumerState<_AuthenticatedShell> createState() =>
      _AuthenticatedShellState();
}

class _AuthenticatedShellState extends ConsumerState<_AuthenticatedShell> {
  int _selectedNavIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool get _isWaiter => widget.user.isWaiter;
  bool get _isKitchen => widget.user.isKitchen;

  @override
  Widget build(BuildContext context) {
    final selectedTheme = ref.watch(selectedUiThemeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Kitchen role: show only the KOT/kitchen screen
    if (_isKitchen) {
      return Scaffold(
        drawer: _buildUnifiedDrawer(context, isDark),
        body: KitchenScreen(companyId: widget.user.companyId),
      );
    }

    final List<Widget> screens;
    if (_isWaiter) {
      screens = [TablesScreen(companyId: widget.user.companyId)];
    } else {
      Widget posScreen;
      switch (selectedTheme) {
        case AppConstants.uiQuickBill:
          posScreen = const QuickBillScreen();
          break;
        case AppConstants.uiClassic:
          posScreen = const ClassicPosScreen();
          break;
        case AppConstants.uiModern:
        default:
          posScreen = const ModernPosScreen();
      }
      screens = [
        posScreen,
        TablesScreen(companyId: widget.user.companyId),
        BillsScreen(companyId: widget.user.companyId),
      ];
    }

    final safeIndex = _selectedNavIndex.clamp(0, screens.length - 1);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildUnifiedDrawer(context, isDark),
      body: screens[safeIndex],
    );
  }

  Widget _buildUnifiedDrawer(BuildContext context, bool isDark) {
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 600;

    return Drawer(
      width: isMobile ? 240.0 : 280.0,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          _buildDrawerUserHeader(isDark),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 20,
              ),
              children: [
                if (_isKitchen) ...[
                  _buildDrawerSection('KITCHEN', isDark),
                  _buildDrawerItem(
                    Icons.restaurant_rounded,
                    'Kitchen Display',
                    () => Navigator.pop(context),
                    isDark,
                    isSelected: true,
                  ),
                ] else if (_isWaiter) ...[
                  _buildDrawerSection('NAVIGATION', isDark),
                  _buildDrawerItem(
                    Icons.table_restaurant_rounded,
                    'Tables & KOT',
                    () {
                      setState(() => _selectedNavIndex = 0);
                      Navigator.pop(context);
                    },
                    isDark,
                    isSelected: _selectedNavIndex == 0,
                  ),
                ] else ...[
                  _buildDrawerSection('NAVIGATION', isDark),
                  _buildDrawerItem(
                    Icons.point_of_sale_rounded,
                    'POS Terminal',
                    () {
                      setState(() => _selectedNavIndex = 0);
                      Navigator.pop(context);
                    },
                    isDark,
                    isSelected: _selectedNavIndex == 0,
                  ),
                  _buildDrawerItem(
                    Icons.table_restaurant_rounded,
                    'Tables & KOT',
                    () {
                      setState(() => _selectedNavIndex = 1);
                      Navigator.pop(context);
                    },
                    isDark,
                    isSelected: _selectedNavIndex == 1,
                  ),
                  _buildDrawerItem(
                    Icons.receipt_long_rounded,
                    'Bills & History',
                    () {
                      setState(() => _selectedNavIndex = 2);
                      Navigator.pop(context);
                    },
                    isDark,
                    isSelected: _selectedNavIndex == 2,
                  ),
                  if (widget.user.isAdmin) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 32),
                    ),
                    _buildDrawerSection('ADMIN MASTERS', isDark),
                    _buildDrawerItem(
                      Icons.business_rounded,
                      'Company Master',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CompanyMasterScreen(),
                        ),
                      ),
                      isDark,
                    ),
                    _buildDrawerItem(
                      Icons.soup_kitchen_rounded,
                      'Kitchen Monitor',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              KitchenScreen(companyId: widget.user.companyId),
                        ),
                      ),
                      isDark,
                    ),
                    _buildDrawerItem(
                      Icons.people_alt_rounded,
                      'User Master',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UserMasterScreen(),
                        ),
                      ),
                      isDark,
                    ),
                    _buildDrawerItem(
                      Icons.inventory_2_rounded,
                      'Item Master',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ItemMasterScreen(),
                        ),
                      ),
                      isDark,
                    ),
                    _buildDrawerItem(
                      Icons.category_rounded,
                      'Item Group',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ItemMasterScreen(),
                        ),
                      ),
                      isDark,
                    ),
                  ],
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 32),
                ),
                _buildDrawerSection('ACCOUNT', isDark),
                _buildDrawerItem(
                  Icons.person_outline_rounded,
                  'My Profile',
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyProfileScreen(user: widget.user),
                      ),
                    );
                  },
                  isDark,
                ),
                _buildDrawerItem(
                  Icons.logout_rounded,
                  'Logout',
                  () => ref.read(authStateProvider.notifier).signOut(),
                  isDark,
                  isError: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${months[local.month - 1]} ${local.day}, ${local.year}  $h:$m $ampm';
  }

  Widget _buildDrawerUserHeader(bool isDark) {
    final user = widget.user;
    final initials = user.fullName.isNotEmpty
        ? user.fullName
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0] : '')
            .join()
            .toUpperCase()
        : '?';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryAmber, AppColors.primaryOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App brand logo
          Image.asset(
            'assets/rasabhojan.png',
            height: 36,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 14),
          // Avatar + name
          Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6), width: 2),
                ),
                child: ClipOval(
                  child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? Image.network(user.avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _initialsAvatar(initials))
                      : _initialsAvatar(initials),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.role.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Last login row
          Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 12, color: Colors.white.withValues(alpha: 0.75)),
              const SizedBox(width: 5),
              Text(
                'Last login: ',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Expanded(
                child: Text(
                  user.lastLogin != null
                      ? _formatDateTime(user.lastLogin!)
                      : 'First login',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _initialsAvatar(String initials) => Container(
        color: Colors.white.withValues(alpha: 0.25),
        child: Center(
          child: Text(
            initials,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );

  Widget _buildDrawerSection(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title,
    VoidCallback onTap,
    bool isDark, {
    bool isError = false,
    bool isSelected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? (isDark
                    ? AppColors.primaryAmber.withValues(alpha: 0.15)
                    : AppColors.primaryOrange.withValues(alpha: 0.1))
              : Colors.transparent,
          border: isSelected
              ? Border.all(
                  color:
                      (isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange)
                          .withValues(alpha: 0.2),
                  width: 1,
                )
              : null,
        ),
        child: ListTile(
          leading:
              Icon(
                    icon,
                    size: 20,
                    color: isError
                        ? AppColors.error
                        : (isSelected
                              ? (isDark
                                    ? AppColors.primaryAmber
                                    : AppColors.primaryOrange)
                              : (isDark
                                    ? AppColors.textWhiteMuted
                                    : AppColors.textDarkMuted)),
                  )
                  .animate(target: isSelected ? 1 : 0)
                  .shimmer(
                    duration: 1200.ms,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isError
                  ? AppColors.error
                  : (isSelected
                        ? (isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange)
                        : (isDark ? AppColors.textWhite : AppColors.textDark)),
            ),
          ),
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
