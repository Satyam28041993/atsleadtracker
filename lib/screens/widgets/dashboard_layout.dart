import 'package:flutter/material.dart';

import 'premium_sidebar.dart';

class DashboardMoreMenuItem {
  const DashboardMoreMenuItem({
    required this.index,
    required this.label,
    required this.icon,
    this.isLogout = false,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool isLogout;
}

class DashboardLayout extends StatefulWidget {
  const DashboardLayout({
    super.key,
    required this.titleForIndex,
    required this.bodyPages,
    required this.sidebarDestinations,
    required this.bottomNavDestinations,
    required this.moreMenuItems,
    required this.onLogout,
    this.floatingActionButtonBuilder,
    this.menuIndex = 4,
  });

  final String Function(int) titleForIndex;
  final List<Widget> bodyPages;
  final List<SidebarDestination> sidebarDestinations;
  final List<NavigationDestination> bottomNavDestinations;
  final List<DashboardMoreMenuItem> moreMenuItems;
  final Future<void> Function() onLogout;
  final Widget? Function(BuildContext, int)? floatingActionButtonBuilder;
  final int menuIndex;

  @override
  State<DashboardLayout> createState() => DashboardLayoutState();
}

class DashboardLayoutState extends State<DashboardLayout> {
  int _selectedIndex = 0;
  bool _sidebarCollapsed = false;
  static const double _railBreakpoint = 900;

  void setIndex(int index) {
    if (mounted) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Future<void> _openMoreMenu() async {
    final selected = await showModalBottomSheet<DashboardMoreMenuItem>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'More',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final item in widget.moreMenuItems)
              ListTile(
                leading: Icon(
                  item.icon,
                  color: item.isLogout ? Colors.red : null,
                ),
                title: Text(
                  item.label,
                  style: TextStyle(
                    color: item.isLogout ? Colors.red : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: !item.isLogout && _selectedIndex == item.index,
                onTap: () => Navigator.of(ctx).pop(item),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;
    if (selected.isLogout) {
      await widget.onLogout();
      return;
    }
    setState(() => _selectedIndex = selected.index);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= _railBreakpoint;

    final bottomNavSelectedIndex =
        _selectedIndex < widget.menuIndex ? _selectedIndex : widget.menuIndex;

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(
        key: ValueKey<int>(_selectedIndex),
        child: widget.bodyPages[_selectedIndex],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titleForIndex(_selectedIndex)),
        actions: useRail
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: 'Logout',
                  onPressed: widget.onLogout,
                ),
              ],
      ),
      body: useRail
          ? Row(
              children: [
                PremiumSidebar(
                  destinations: widget.sidebarDestinations,
                  selectedIndex: _selectedIndex,
                  collapsed: _sidebarCollapsed,
                  onDestinationSelected: (i) =>
                      setState(() => _selectedIndex = i),
                  onToggleCollapse: () =>
                      setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                  onLogout: widget.onLogout,
                ),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: bottomNavSelectedIndex,
              onDestinationSelected: (i) {
                if (i == widget.menuIndex) {
                  _openMoreMenu();
                } else {
                  setState(() => _selectedIndex = i);
                }
              },
              destinations: widget.bottomNavDestinations,
            ),
      floatingActionButton: widget.floatingActionButtonBuilder != null
          ? widget.floatingActionButtonBuilder!(context, _selectedIndex)
          : null,
    );
  }
}
