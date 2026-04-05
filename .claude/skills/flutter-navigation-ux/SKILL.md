---
name: flutter-navigation-ux
description: "Use when: implementing zoom drawer navigation, WhatsApp-style bottom nav with FAB, top app bar patterns, animated tab switching, role-based nav item visibility, deep linking with go_router."
---

# Skill: Flutter Navigation UX — Zoom Drawer + WhatsApp Style

## Architecture Decision
- **Mobile (< 720px)**: WhatsApp-style bottom NavigationBar (max 5 items) + Zoom Drawer for overflow items
- **Tablet (≥ 720px)**: Material 3 NavigationRail (as currently implemented)
- **Desktop (≥ 1024px)**: Extended NavigationRail

## Zoom Drawer Pattern (flutter_zoom_drawer)
```yaml
# pubspec.yaml addition
flutter_zoom_drawer: ^3.2.0  # or compatible latest
```

```dart
// ZoomDrawer wraps the entire AppShell — drawer slides open from left
// with a perspective zoom effect (3D-feel scale + translate)
class AppShell extends ConsumerStatefulWidget {
  // ...
}

// In _AppShellState — add drawer controller
final ZoomDrawerController _drawerController = ZoomDrawerController();

// Build structure:
Widget build(BuildContext context) {
  return ZoomDrawer(
    controller: _drawerController,
    menuScreen: _DrawerMenuScreen(...),   // left drawer: all nav items
    mainScreen: Scaffold(                 // main content
      appBar: _buildAppBar(),
      bottomNavigationBar: _buildBottomNav(),  // WhatsApp-style (5 items max)
      body: widget.child,
    ),
    borderRadius: 24.0,
    showShadow: true,
    angle: -12.0,   // slight perspective tilt
    drawerShadowsBackgroundColor: Colors.grey.shade800,
    slideWidth: MediaQuery.of(context).size.width * 0.70,
    openCurve: Curves.fastOutSlowIn,
    closeCurve: Curves.bounceIn,
  );
}
```

## WhatsApp-Style Bottom Navigation (5 items max for sellers, 4 for admin)

### Seller Bottom Nav Items (5 max)
1. Dashboard (home icon)
2. Shops (storefront)
3. Invoices (receipt_long)
4. Inventory (inventory_2)
5. Profile (person)

### Admin Bottom Nav Items (4 primary)
1. Dashboard
2. Routes
3. Reports
4. Settings

All other items accessible via Zoom Drawer.

## Bottom Nav Implementation
```dart
NavigationBar(
  selectedIndex: _selectedIndex(navItems, currentLocation),
  onDestinationSelected: (i) => context.go(navItems[i].route),
  elevation: 8,
  backgroundColor: Theme.of(context).colorScheme.surface,
  indicatorColor: AppBrand.primaryColor.withValues(alpha: 0.15),
  destinations: navItems.map((item) => NavigationDestination(
    icon: Icon(item.icon),
    selectedIcon: Icon(item.icon, color: AppBrand.primaryColor),
    label: item.label,
    tooltip: item.label,
  )).toList(),
)
```

## App Bar — WhatsApp Style
Key features:
- Company logo + "FootWear" brand name on left
- Drawer hamburger on left (opens ZoomDrawer)
- Action icons on right: search, notifications, profile avatar
- Online indicator dot on avatar

```dart
AppBar(
  leading: IconButton(
    icon: const Icon(Icons.menu),
    tooltip: 'Menu',
    onPressed: () => _drawerController.toggle?.call(),
  ),
  title: Row(children: [
    Image.asset(AppBrand.logoAsset, height: 32),
    const SizedBox(width: 8),
    Text(AppBrand.appName, style: const TextStyle(fontWeight: FontWeight.bold)),
  ]),
  actions: [
    IconButton(icon: const Icon(Icons.search), onPressed: () => _showSearch(context)),
    _ProfileAvatar(user: user, isOnline: isOnline),
  ],
)
```

## Drawer Menu Screen
```dart
class _DrawerMenuScreen extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(children: [
        // User info header
        _DrawerUserHeader(user: user),
        const Divider(),
        // All nav items as ListTiles
        ...allNavItems.map((item) => ListTile(
          leading: Icon(item.icon, color: AppBrand.primaryColor),
          title: Text(item.label),
          selected: currentRoute == item.route,
          onTap: () {
            ZoomDrawer.of(context)?.close();
            context.go(item.route);
          },
        )),
        const Spacer(),
        // Sign out button
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: Text(tr('sign_out', ref)),
          onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
        ),
      ]),
    );
  }
}
```

## go_router Integration
ZoomDrawer does NOT interfere with go_router — the `mainScreen` contains the `widget.child` which go_router already provides.

Key constraint: `ZoomDrawerController.toggle` must only be called on main screen scaffold (not inside child routes).

## Role-Based Nav Items
```dart
List<NavItem> _filteredItems(UserModel? user) {
  if (user == null) return [];
  if (user.isAdmin) return _adminNavItems;   // all items
  return _sellerNavItems;  // seller-visible only (no routes/customers/reports/settings)
}

// Bottom nav shows max 5 items
// Drawer shows ALL role-filtered items (unlimited)
List<NavItem> get _bottomNavItems => _filteredItems.take(5).toList();
List<NavItem> get _drawerNavItems => _filteredItems;
```

## Animation — Tab Switch Transition
Use `AnimatedSwitcher` or `PageTransitionsTheme` for smooth tab switches in bottom nav:
```dart
// In AppShell: animate child transitions
AnimatedSwitcher(
  duration: AppTokens.durNormal,
  transitionBuilder: (child, animation) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.05, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
  ),
  child: KeyedSubtree(key: ValueKey(currentLocation), child: widget.child),
)
```

## Common Pitfalls
- ZoomDrawer `menuScreen` must NOT use `Scaffold` with its own AppBar — the drawer is the outer wrapper
- `ZoomDrawer.of(context)` may be null if called outside ZoomDrawer tree — always null-check
- `context.go()` for bottom nav tabs (replaces stack); `context.push()` for detail pages
- Back button must close drawer first if open, then navigate up

## Dependency to Add
```yaml
dependencies:
  flutter_zoom_drawer: ^3.2.0
```
