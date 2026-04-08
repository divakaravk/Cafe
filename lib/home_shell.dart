import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_constants.dart';
import 'models/models.dart';
import 'providers/providers.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/pos/presentation/modern_pos_screen.dart';
import 'features/pos/presentation/quick_bill_screen.dart';
import 'features/pos/presentation/classic_pos_screen.dart';
import 'features/orders/tables_screen.dart';
import 'features/reports/bills_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final selectedTheme = ref.watch(selectedUiThemeProvider);
    final size = MediaQuery.of(context).size;
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

    final screens = [
      posScreen,
      TablesScreen(companyId: widget.user.companyId),
      BillsScreen(companyId: widget.user.companyId),
    ];

    if (isTablet) {
      // Tablet: NavigationRail
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedNavIndex,
              onDestinationSelected: (i) =>
                  setState(() => _selectedNavIndex = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.point_of_sale_rounded),
                  label: Text('POS'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.table_restaurant_rounded),
                  label: Text('Tables'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_rounded),
                  label: Text('Bills'),
                ),
              ],
            ),
            Expanded(child: screens[_selectedNavIndex]),
          ],
        ),
      );
    }

    // Mobile: Bottom nav
    return Scaffold(
      body: screens[_selectedNavIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavIndex,
        onDestinationSelected: (i) => setState(() => _selectedNavIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_rounded),
            label: 'POS',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_restaurant_rounded),
            label: 'Tables',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Bills',
          ),
        ],
      ),
    );
  }
}
