import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/lead_service.dart';
import '../services/product_service.dart';
import 'admin/analytics_dashboard.dart';
import 'admin/product_management_screen.dart';
import 'quotation_management_screen.dart';
import 'follow_ups_screen.dart';
import 'settings_screen.dart';
import 'widgets/dashboard_welcome_header.dart';
import 'widgets/employee_overview_panel.dart';
import 'widgets/kanban_board.dart';
import 'widgets/premium_sidebar.dart';
import 'widgets/quick_add_lead.dart';
import 'widgets/quick_add_tender.dart';
import 'widgets/tasks_overview_panel.dart';
import 'widgets/dashboard_layout.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key, this.authService});

  final AuthService? authService;

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  final GlobalKey<DashboardLayoutState> _dashboardKey =
      GlobalKey<DashboardLayoutState>();
  late final AuthService _auth;
  late final LeadService _leadService;
  late final ProductService _productService;
  late final AnalyticsService _analyticsService;
  bool _canManageCatalog = false;
  bool _catalogAccessLoaded = false;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _leadService = LeadService(authService: _auth);
    _productService = ProductService();
    _analyticsService = AnalyticsService(leadService: _leadService);
    _loadCatalogAccess();
  }

  Future<void> _loadCatalogAccess() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _canManageCatalog = false;
          _catalogAccessLoaded = true;
        });
      }
      return;
    }
    final allowed = await _auth.canManageCatalog(uid);
    if (!mounted) return;
    setState(() {
      _canManageCatalog = allowed;
      _catalogAccessLoaded = true;
    });
  }

  Future<void> _openNormalLeadModal(String employeeUid) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => QuickAddLeadSheet(
        leadService: _leadService,
        authService: _auth,
        currentUserRole: 'employee',
        currentUserId: employeeUid,
        productService: _productService,
      ),
    );
  }

  Future<void> _openTenderLeadModal(String employeeUid) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => QuickAddTenderSheet(
        leadService: _leadService,
        authService: _auth,
        currentUserRole: 'employee',
        currentUserId: employeeUid,
        productService: _productService,
      ),
    );
  }

  /// Index map when catalog is hidden:
  /// 0 Dashboard, 1 Kanban, 2 Tender, 3 Follow-ups, 4 Analytics, 5 Settings, 6 Quotations
  /// With catalog:
  /// 0 Dashboard, 1 Kanban, 2 Tender, 3 Follow-ups, 4 Analytics, 5 Catalog, 6 Settings, 7 Quotations
  String _titleForIndex(int index) {
    if (!_canManageCatalog) {
      switch (index) {
        case 0:
          return 'Dashboard';
        case 1:
          return 'My Leads';
        case 2:
          return 'Tender Pipeline';
        case 3:
          return 'Follow-ups';
        case 4:
          return 'Analytics';
        case 5:
          return 'Settings';
        case 6:
          return 'Quotations';
        default:
          return 'ATS Lead Tracker';
      }
    }
    switch (index) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'My Leads';
      case 2:
        return 'Tender Pipeline';
      case 3:
        return 'Follow-ups';
      case 4:
        return 'Analytics';
      case 5:
        return 'Product Catalog';
      case 6:
        return 'Settings';
      case 7:
        return 'Quotations';
      default:
        return 'ATS Lead Tracker';
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeeUid = FirebaseAuth.instance.currentUser?.uid;

    if (employeeUid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }

    if (!_catalogAccessLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bottomNavDestinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard_rounded),
        label: 'Dashboard',
      ),
      const NavigationDestination(
        icon: Icon(Icons.view_kanban_outlined),
        selectedIcon: Icon(Icons.view_kanban_rounded),
        label: 'Kanban',
      ),
      const NavigationDestination(
        icon: Icon(Icons.description_outlined),
        selectedIcon: Icon(Icons.description_rounded),
        label: 'Tender',
      ),
      const NavigationDestination(
        icon: Icon(Icons.event_repeat_outlined),
        selectedIcon: Icon(Icons.event_repeat_rounded),
        label: 'Follow-ups',
      ),
      const NavigationDestination(
        icon: Icon(Icons.menu_rounded),
        selectedIcon: Icon(Icons.menu_open_rounded),
        label: 'Menu',
      ),
    ];

    final sidebarDestinations = <SidebarDestination>[
      const SidebarDestination(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
      ),
      const SidebarDestination(
        label: 'Kanban',
        icon: Icons.view_kanban_outlined,
        selectedIcon: Icons.view_kanban_rounded,
      ),
      const SidebarDestination(
        label: 'Tender',
        icon: Icons.description_outlined,
        selectedIcon: Icons.description_rounded,
      ),
      const SidebarDestination(
        label: 'Follow-ups',
        icon: Icons.event_repeat_outlined,
        selectedIcon: Icons.event_repeat_rounded,
      ),
      const SidebarDestination(
        label: 'Analytics',
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights_rounded,
      ),
      if (_canManageCatalog)
        const SidebarDestination(
          label: 'Catalog',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2_rounded,
        ),
      const SidebarDestination(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
      const SidebarDestination(
        label: 'Quotations',
        icon: Icons.request_quote_outlined,
        selectedIcon: Icons.request_quote_rounded,
      ),
    ];

    final settingsIndex = _canManageCatalog ? 6 : 5;
    final quotationsIndex = _canManageCatalog ? 7 : 6;

    final moreMenuItems = <DashboardMoreMenuItem>[
      const DashboardMoreMenuItem(
        index: 4,
        label: 'Analytics',
        icon: Icons.insights_rounded,
      ),
      if (_canManageCatalog)
        const DashboardMoreMenuItem(
          index: 5,
          label: 'Catalog',
          icon: Icons.inventory_2_rounded,
        ),
      DashboardMoreMenuItem(
        index: settingsIndex,
        label: 'Settings',
        icon: Icons.settings_rounded,
      ),
      DashboardMoreMenuItem(
        index: quotationsIndex,
        label: 'Quotations',
        icon: Icons.request_quote_rounded,
      ),
      const DashboardMoreMenuItem(
        index: -1,
        label: 'Logout',
        icon: Icons.logout_rounded,
        isLogout: true,
      ),
    ];

    final bodyPages = <Widget>[
      SingleChildScrollView(
        child: ColoredBox(
          color: const Color(0xFFF8F9FA),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardWelcomeHeader(
                uid: employeeUid,
                isAdmin: false,
                authService: _auth,
              ),
              EmployeeOverviewPanel(
                leadService: _leadService,
                analyticsService: _analyticsService,
                authService: _auth,
                productService: _productService,
                employeeUid: employeeUid,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 10.0,
                ),
                child: TasksOverviewPanel(
                  employeeUid: employeeUid,
                  isAdmin: false,
                ),
              ),
            ],
          ),
        ),
      ),
      KanbanBoard(
        key: ValueKey<String>('${employeeUid}_normal'),
        leadService: _leadService,
        assignedToUid: employeeUid,
        authService: _auth,
        isAdmin: false,
        productService: _productService,
        isTender: false,
      ),
      KanbanBoard(
        key: ValueKey<String>('${employeeUid}_tender'),
        leadService: _leadService,
        assignedToUid: employeeUid,
        authService: _auth,
        isAdmin: false,
        productService: _productService,
        isTender: true,
      ),
      FollowUpsTabbedView(
        leadService: _leadService,
        authService: _auth,
        productService: _productService,
        filterAssignedToUid: employeeUid,
      ),
      AnalyticsDashboard(
        analyticsService: _analyticsService,
        authService: _auth,
        leadService: _leadService,
        productService: _productService,
        assignedToUid: employeeUid,
      ),
      if (_canManageCatalog)
        ProductManagementScreen(productService: _productService),
      const SettingsScreen(),
      QuotationManagementScreen(
        isAdmin: false,
        productService: _productService,
        leadService: _leadService,
      ),
    ];

    return DashboardLayout(
      key: _dashboardKey,
      titleForIndex: _titleForIndex,
      bodyPages: bodyPages,
      sidebarDestinations: sidebarDestinations,
      bottomNavDestinations: bottomNavDestinations,
      moreMenuItems: moreMenuItems,
      onLogout: () async => _auth.signOut(),
      floatingActionButtonBuilder: (context, selectedIndex) {
        if (selectedIndex == 1) {
          return FloatingActionButton.extended(
            onPressed: () => _openNormalLeadModal(employeeUid),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Lead'),
          );
        }
        if (selectedIndex == 2) {
          return FloatingActionButton.extended(
            onPressed: () => _openTenderLeadModal(employeeUid),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Tender'),
          );
        }
        return null;
      },
    );
  }
}
