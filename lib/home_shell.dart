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

  @override
  Widget build(BuildContext context) {
    final selectedTheme = ref.watch(selectedUiThemeProvider);
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTablet = size.width > 800;

    // POS screen based on selected theme
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

    final List<Widget> screens = [
      posScreen,
      TablesScreen(companyId: widget.user.companyId),
      BillsScreen(companyId: widget.user.companyId),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildUnifiedDrawer(context, isDark),
      body: screens[_selectedNavIndex],
    );
  }

  Widget _buildUnifiedDrawer(BuildContext context, bool isDark) {
    return Drawer(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryAmber, AppColors.primaryOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.restaurant_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'CafePOS',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 32),
                ),
                _buildDrawerSection('ACCOUNT', isDark),
                _buildDrawerItem(
                  Icons.person_outline_rounded,
                  'My Profile',
                  () {},
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
