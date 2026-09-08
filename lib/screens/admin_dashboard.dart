import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/lead_service.dart';
import '../services/product_service.dart';
import '../services/source_service.dart';
import 'admin/analytics_dashboard.dart';
import 'admin/product_management_screen.dart';
import 'quotation_management_screen.dart';
import 'follow_ups_screen.dart';
import 'settings_screen.dart';
import 'widgets/dashboard_welcome_header.dart';
import 'widgets/kanban_board.dart';
import 'widgets/manager_dashboard.dart';
import 'widgets/premium_sidebar.dart';
import 'widgets/quick_add_lead.dart';
import 'widgets/quick_add_tender.dart';
import 'widgets/tasks_overview_panel.dart';
import 'widgets/assign_task_dialog.dart';
import 'widgets/dashboard_layout.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, this.authService});

  final AuthService? authService;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final GlobalKey<DashboardLayoutState> _dashboardKey = GlobalKey<DashboardLayoutState>();
  late final AuthService _auth;
  late final LeadService _leadService;
  late final ProductService _productService;
  late final AnalyticsService _analyticsService;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _leadService = LeadService(authService: _auth);
    _productService = ProductService();
    _analyticsService = AnalyticsService(leadService: _leadService);
    // Newly shipped default lead sources only reach an existing install if
    // something merges them into settings/sources_config, and that document is
    // admin-writable only. No-op once they are all there.
    SourceService.instance.ensureDefaultsPresent();
  }

  Future<void> _openNormalLeadModal(String adminUid) async {
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
        currentUserRole: 'admin',
        currentUserId: adminUid,
        productService: _productService,
      ),
    );
  }

  Future<void> _openTenderLeadModal(String adminUid) async {
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
        currentUserRole: 'admin',
        currentUserId: adminUid,
        productService: _productService,
      ),
    );
  }

  String _titleForIndex(int i) {
    switch (i) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Lead Pipeline';
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
    final adminUid = FirebaseAuth.instance.currentUser?.uid;

    if (adminUid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
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

    final sidebarDestinations = const [
      SidebarDestination(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
      ),
      SidebarDestination(
        label: 'Kanban',
        icon: Icons.view_kanban_outlined,
        selectedIcon: Icons.view_kanban_rounded,
      ),
      SidebarDestination(
        label: 'Tender',
        icon: Icons.description_outlined,
        selectedIcon: Icons.description_rounded,
      ),
      SidebarDestination(
        label: 'Follow-ups',
        icon: Icons.event_repeat_outlined,
        selectedIcon: Icons.event_repeat_rounded,
      ),
      SidebarDestination(
        label: 'Analytics',
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights_rounded,
      ),
      SidebarDestination(
        label: 'Catalog',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
      ),
      SidebarDestination(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
      SidebarDestination(
        label: 'Quotations',
        icon: Icons.request_quote_outlined,
        selectedIcon: Icons.request_quote_rounded,
      ),
    ];

    final moreMenuItems = const [
      DashboardMoreMenuItem(
        index: 4,
        label: 'Analytics',
        icon: Icons.insights_rounded,
      ),
      DashboardMoreMenuItem(
        index: 5,
        label: 'Catalog',
        icon: Icons.inventory_2_rounded,
      ),
      DashboardMoreMenuItem(
        index: 6,
        label: 'Settings',
        icon: Icons.settings_rounded,
      ),
      DashboardMoreMenuItem(
        index: 7,
        label: 'Quotations',
        icon: Icons.request_quote_rounded,
      ),
      DashboardMoreMenuItem(
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
                uid: adminUid,
                isAdmin: true,
                authService: _auth,
              ),
              ManagerDashboard(
                analyticsService: _analyticsService,
                leadService: _leadService,
                productService: _productService,
                authService: _auth,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                child: TasksOverviewPanel(isAdmin: true),
              ),
            ],
          ),
        ),
      ),
      KanbanBoard(
        leadService: _leadService,
        authService: _auth,
        isAdmin: true,
        productService: _productService,
        isTender: false,
      ),
      KanbanBoard(
        leadService: _leadService,
        authService: _auth,
        isAdmin: true,
        productService: _productService,
        isTender: true,
      ),
      FollowUpsTabbedView(
        leadService: _leadService,
        authService: _auth,
        productService: _productService,
      ),
      AnalyticsDashboard(
        analyticsService: _analyticsService,
        authService: _auth,
        leadService: _leadService,
        productService: _productService,
      ),
      ProductManagementScreen(productService: _productService),
      const SettingsScreen(),
      QuotationManagementScreen(
        isAdmin: true,
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
        if (selectedIndex == 0) {
          return FloatingActionButton.extended(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const AssignTaskDialog(),
              );
            },
            icon: const Icon(Icons.assignment_ind),
            label: const Text('Assign Task'),
          );
        } else if (selectedIndex == 1) {
          return FloatingActionButton.extended(
            onPressed: () => _openNormalLeadModal(adminUid),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Lead'),
          );
        } else if (selectedIndex == 2) {
          return FloatingActionButton.extended(
            onPressed: () => _openTenderLeadModal(adminUid),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Tender'),
          );
        }
        return null;
      },
    );
  }
}
