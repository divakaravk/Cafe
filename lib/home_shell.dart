import 'package:flutter/material.dart';
import 'dart:ui';
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
import 'features/admin/presentation/item_variant_screen.dart';
import 'features/admin/presentation/table_master_screen.dart';
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
    final user = widget.user;

    // Effective module access. Admins bypass gating; otherwise use the cached
    // permission set, falling back to role defaults for legacy sessions that
    // were created before permissions were cached.
    final perms =
        ref.watch(permissionsProvider) ??
        (user.isAdmin
            ? UserPermission.all(user.id)
            : UserPermission.forRole(user.id, user.role));

    // Kitchen role: dedicated full-screen KOT display.
    if (_isKitchen) {
      return Scaffold(
        key: _scaffoldKey,
        drawer: _buildUnifiedDrawer(context, isDark, perms, const []),
        body: KitchenScreen(companyId: user.companyId),
      );
    }

    // Build the navigable modules from the user's access. Waiters keep their
    // dedicated tables-only flow.
    final List<_NavModule> modules;
    if (_isWaiter) {
      modules = [
        _NavModule(
          Icons.table_restaurant_rounded,
          'Tables & KOT',
          TablesScreen(companyId: user.companyId),
        ),
      ];
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
      modules = [
        if (perms.canCreateBill)
          _NavModule(Icons.point_of_sale_rounded, 'POS Terminal', posScreen),
        if (perms.canManageTables)
          _NavModule(
            Icons.table_restaurant_rounded,
            'Tables & KOT',
            TablesScreen(companyId: user.companyId),
          ),
        if (perms.canViewReports)
          _NavModule(
            Icons.receipt_long_rounded,
            'Bills & History',
            BillsScreen(companyId: user.companyId),
          ),
      ];
      // Never leave the shell empty — fall back to POS if nothing was granted.
      if (modules.isEmpty) {
        modules.add(
          _NavModule(Icons.point_of_sale_rounded, 'POS Terminal', posScreen),
        );
      }
    }

    final safeIndex = _selectedNavIndex.clamp(0, modules.length - 1);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildUnifiedDrawer(context, isDark, perms, modules),
      body: modules[safeIndex].screen,
    );
  }

  /// Whether any back-office master destination is visible for these
  /// permissions.
  bool _canSeeAdminSection(UserPermission p) =>
      p.canManageSettings ||
      p.canManageUsers ||
      p.canManageItems ||
      p.canManageStock ||
      p.canManageTables;

  Widget _buildUnifiedDrawer(
    BuildContext context,
    bool isDark,
    UserPermission perms,
    List<_NavModule> modules,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 600;

    return Theme(
      data: Theme.of(context).copyWith(
        drawerTheme: const DrawerThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: Drawer(
        width: isMobile ? 260.0 : 280.0,
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 12, left: 12, right: 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(5, 5),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.85),
                        isDark ? const Color(0xFF121212).withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildDrawerUserHeader(isDark),
                      Expanded(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.only(
                            top: 8,
                            bottom: MediaQuery.of(context).padding.bottom + 24,
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
                            ] else ...[
                              _buildDrawerSection('NAVIGATION', isDark),
                              ...modules.asMap().entries.map(
                                (e) => _buildDrawerItem(
                                  e.value.icon,
                                  e.value.label,
                                  () {
                                    setState(() => _selectedNavIndex = e.key);
                                    Navigator.pop(context);
                                  },
                                  isDark,
                                  isSelected: _selectedNavIndex == e.key,
                                ),
                              ),
                              if (perms.canManageTables)
                                _buildDrawerItem(
                                  Icons.soup_kitchen_rounded,
                                  'Kitchen Monitor',
                                  () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            KitchenScreen(companyId: widget.user.companyId),
                                      ),
                                    );
                                  },
                                  isDark,
                                ),
                              if (_canSeeAdminSection(perms)) ...[
                                const SizedBox(height: 12),
                                _buildDrawerSection('ADMIN MASTERS', isDark),
                                if (perms.canManageSettings)
                                  _buildDrawerItem(Icons.business_rounded, 'Company Master', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyMasterScreen())), isDark),
                                if (perms.canManageTables)
                                  _buildDrawerItem(Icons.table_restaurant_rounded, 'Table Master', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TableMasterScreen())), isDark),
                                if (perms.canManageUsers)
                                  _buildDrawerItem(Icons.people_alt_rounded, 'User Master', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserMasterScreen())), isDark),
                                if (perms.canManageItems)
                                  _buildDrawerItem(Icons.category_rounded, 'Item Group', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ItemMasterScreen())), isDark),
                                if (perms.canManageItems)
                                  _buildDrawerItem(Icons.inventory_2_rounded, 'Item Variant', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ItemVariantScreen())), isDark),
                                if (perms.canManageStock)
                                  _buildDrawerItem(Icons.warehouse_rounded, 'Stock & Inventory', () {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock module coming soon'), behavior: SnackBarBehavior.floating));
                                  }, isDark),
                              ],
                            ],
                            const SizedBox(height: 12),
                            _buildDrawerSection('ACCOUNT', isDark),
                            _buildDrawerItem(Icons.person_outline_rounded, 'My Profile', () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => MyProfileScreen(user: widget.user)));
                            }, isDark),
                            _buildDrawerItem(Icons.logout_rounded, 'Logout', () => ref.read(authStateProvider.notifier).signOut(), isDark, isError: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
        ? user.fullName.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase()
        : '?';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryAmber, AppColors.primaryOrange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryOrange.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.restaurant_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Rasabhojan',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textDark,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // User Profile Row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.5), width: 1.5),
                ),
                child: ClipOval(
                  child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? Image.network(user.avatarUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsAvatar(initials))
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
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          user.role.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryOrange,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _initialsAvatar(String initials) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryAmber, AppColors.primaryOrange],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            initials,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
  Widget _buildDrawerSection(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isDark ? AppColors.textWhiteMuted.withValues(alpha: 0.5) : AppColors.textDarkMuted.withValues(alpha: 0.5),
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
    final activeColor = isDark ? AppColors.primaryAmber : AppColors.primaryOrange;
    final contentColor = isError
        ? AppColors.error
        : (isSelected
            ? activeColor
            : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: activeColor.withValues(alpha: 0.05),
          splashColor: activeColor.withValues(alpha: 0.1),
          highlightColor: activeColor.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isSelected ? activeColor.withValues(alpha: 0.08) : Colors.transparent,
            ),
            child: Stack(
              children: [
                if (isSelected)
                  Positioned(
                    left: 0,
                    top: 10,
                    bottom: 10,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: contentColor,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isError
                                ? AppColors.error
                                : (isSelected
                                    ? (isDark ? Colors.white : AppColors.textDark)
                                    : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _NavModule {
  final IconData icon;
  final String label;
  final Widget screen;
  const _NavModule(this.icon, this.label, this.screen);
}
