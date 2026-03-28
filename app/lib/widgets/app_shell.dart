import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../models/user_model.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/services/permissions_service.dart';
import '../core/utils/error_mapper.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _navItems = [
    (icon: Icons.dashboard, key: 'dashboard', route: '/'),
    (icon: Icons.route, key: 'routes', route: '/routes'),
    (icon: Icons.storefront, key: 'shops', route: '/shops'),
    (icon: Icons.people, key: 'customers', route: '/customers'),
    (icon: Icons.inventory_2, key: 'products', route: '/products'),
    (icon: Icons.warehouse, key: 'inventory', route: '/inventory'),
    (icon: Icons.analytics, key: 'reports', route: '/reports'),
    (icon: Icons.settings, key: 'settings', route: '/settings'),
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionsService.requestOnFirstRun();
    });
  }

  /// Returns the logical parent route for [path], or null when already at root.
  String? _parentRoute(String path) {
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null; // at /
    if (segs.length == 1) return '/'; // /routes → /
    // /products/:id/variants/new  or  /products/:id/variants/:vid/edit → /products/:id
    if (segs.length >= 3 && segs[2] == 'variants') {
      return '/${segs[0]}/${segs[1]}';
    }
    // /routes/:id/edit → /routes/:id
    if (segs.length == 3 && segs[2] == 'edit') {
      return '/${segs[0]}/${segs[1]}';
    }
    // /routes/:id → /routes
    if (segs.length == 2) return '/${segs[0]}';
    return '/';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final isWide = MediaQuery.of(context).size.width >= 720;

    final rawItems = _filteredItems(user);
    final navItems = rawItems
        .map((e) => (icon: e.icon, label: tr(e.key, ref), route: e.route))
        .toList();
    final currentLocation = GoRouterState.of(context).uri.path;

    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? false;

    void onPopInvoked(bool didPop, dynamic result) {
      if (didPop) return;
      final parent = _parentRoute(currentLocation);
      if (parent != null) {
        context.go(parent);
      } else {
        SystemNavigator.pop();
      }
    }

    if (isWide) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: onPopInvoked,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScrollableNavRail(
                extended: MediaQuery.of(context).size.width >= 1024,
                selectedIndex: _selectedIndex(navItems, currentLocation),
                items: navItems,
                onItem: (i) => context.go(navItems[i].route),
                onLogout: () =>
                    ref.read(authNotifierProvider.notifier).signOut(),
                user: user,
                signOutTooltip: tr('sign_out', ref),
                isOnline: isOnline,
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: widget.child),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(AppBrand.logoAsset, height: 32, fit: BoxFit.contain),
              const SizedBox(width: 8),
              Expanded(
                child: _BreadcrumbTitle(
                    location: currentLocation, isOnline: isOnline, ref: ref),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: tr('sign_out', ref),
              onPressed: () =>
                  ref.read(authNotifierProvider.notifier).signOut(),
            ),
          ],
        ),
        drawer: NavigationDrawer(
          selectedIndex: _selectedIndex(navItems, currentLocation),
          onDestinationSelected: (i) {
            Navigator.pop(context);
            context.go(navItems[i].route);
          },
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(AppBrand.logoAsset,
                      height: 56, fit: BoxFit.contain),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _UserAvatar(user: user, radius: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: user != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(user.displayName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                      overflow: TextOverflow.ellipsis),
                                  Text(user.email,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  _RoleBadge(role: user.role),
                                ],
                              )
                            : const Text(AppBrand.appName,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...navItems.map((e) => NavigationDrawerDestination(
                  icon: Icon(e.icon),
                  label: Text(e.label),
                )),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_reset),
              title: Text(tr('change_password', ref)),
              onTap: () {
                Navigator.pop(context);
                _showChangePasswordDialog();
              },
            ),
          ],
        ),
        body: widget.child,
      ),
    );
  }

  List<({IconData icon, String key, String route})> _filteredItems(
      UserModel? user) {
    if (user == null) return [];
    if (user.isSeller) {
      return AppShell._navItems
          .where((item) =>
              item.route == '/' ||
              item.route == '/shops' ||
              item.route == '/products' ||
              item.route == '/inventory')
          .toList();
    }
    return AppShell._navItems.where((item) {
      if (item.route == '/settings') {
        return user.isAdmin;
      }
      return true;
    }).toList();
  }

  int? _selectedIndex(List<({IconData icon, String label, String route})> items,
      String location) {
    if (items.isEmpty) return null;
    final idx = items.indexWhere((e) =>
        e.route == location ||
        (e.route != '/' && location.startsWith(e.route)));
    return idx < 0 ? 0 : idx;
  }

  void _showChangePasswordDialog() {
    final currentC = TextEditingController();
    final newC = TextEditingController();
    final confirmC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('change_password', ref)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentC,
              obscureText: true,
              autofocus: true,
              decoration:
                  InputDecoration(labelText: tr('current_password', ref)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newC,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('new_password', ref)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmC,
              obscureText: true,
              decoration:
                  InputDecoration(labelText: tr('confirm_password', ref)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel', ref)),
          ),
          ElevatedButton(
            onPressed: () async {
              final np = newC.text.trim();
              if (np.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('err_weak_password', ref))),
                );
                return;
              }
              if (np != confirmC.text.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('passwords_dont_match', ref))),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await ref
                    .read(authNotifierProvider.notifier)
                    .changePassword(currentC.text.trim(), np);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('password_changed', ref))),
                  );
                }
              } catch (e) {
                if (mounted) {
                  final key = AppErrorMapper.key(e);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(tr(key, ref))));
                }
              }
            },
            child: Text(tr('save', ref)),
          ),
        ],
      ),
    );
  }
}

// ─── Scrollable side navigation rail ─────────────────────────────────────────

class _ScrollableNavRail extends StatelessWidget {
  final bool extended;
  final int? selectedIndex;
  final List<({IconData icon, String label, String route})> items;
  final ValueChanged<int> onItem;
  final VoidCallback onLogout;
  final UserModel? user;
  final String signOutTooltip;
  final bool isOnline;

  const _ScrollableNavRail({
    required this.extended,
    required this.selectedIndex,
    required this.items,
    required this.onItem,
    required this.onLogout,
    this.user,
    this.signOutTooltip = 'Sign out',
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = extended ? 200.0 : 72.0;
    return SizedBox(
      width: width,
      child: ColoredBox(
        color: cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: extended
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(AppBrand.logoAsset,
                              width: 160, height: 66, fit: BoxFit.contain),
                          const SizedBox(height: 4),
                          _ConnectivityDot(isOnline: isOnline),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(AppBrand.logoAsset,
                                width: 52, height: 34, fit: BoxFit.contain),
                            const SizedBox(height: 4),
                            _ConnectivityDot(isOnline: isOnline),
                          ],
                        ),
                      ),
              ),
            ),
            if (user != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: extended
                    ? Row(
                        children: [
                          _UserAvatar(user: user, radius: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user!.displayName,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface),
                                    overflow: TextOverflow.ellipsis),
                                _RoleBadge(role: user!.role, small: true),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: _UserAvatar(user: user, radius: 14),
                      ),
              ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    final sel = selectedIndex == i;
                    final bg = sel ? cs.secondaryContainer : Colors.transparent;
                    final fg =
                        sel ? cs.onSecondaryContainer : cs.onSurfaceVariant;
                    if (extended) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: InkWell(
                          onTap: () => onItem(i),
                          borderRadius: BorderRadius.circular(28),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Row(children: [
                              Icon(item.icon, size: 20, color: fg),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(item.label,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: fg,
                                        fontWeight: sel
                                            ? FontWeight.w600
                                            : FontWeight.normal)),
                              ),
                            ]),
                          ),
                        ),
                      );
                    }
                    return Tooltip(
                      message: item.label,
                      preferBelow: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: InkWell(
                          onTap: () => onItem(i),
                          borderRadius: BorderRadius.circular(24),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Center(
                                child: Icon(item.icon, size: 20, color: fg)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: signOutTooltip,
                  onPressed: onLogout,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── User Avatar ─────────────────────────────────────────────────────────────

class _UserAvatar extends StatelessWidget {
  final UserModel? user;
  final double radius;

  const _UserAvatar({this.user, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = _initials(user?.displayName ?? '');
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w600,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

// ─── Role Badge ──────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final UserRole role;
  final bool small;

  const _RoleBadge({required this.role, this.small = false});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      UserRole.admin => ('Admin', AppBrand.adminRoleColor),
      UserRole.seller => ('Seller', AppBrand.sellerRoleColor),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─── Breadcrumb Title ─────────────────────────────────────────────────────────

class _BreadcrumbTitle extends StatelessWidget {
  final String location;
  final bool isOnline;
  final WidgetRef ref;

  const _BreadcrumbTitle({
    required this.location,
    required this.isOnline,
    required this.ref,
  });

  static const _segmentLabels = <String, String>{
    'customers': 'Customers',
    'products': 'Products',
    'routes': 'Routes',
    'shops': 'Shops',
    'inventory': 'Inventory',
    'reports': 'Reports',
    'settings': 'Settings',
    'variants': 'Variants',
    'edit': 'Edit',
    'new': 'New',
  };

  String _buildCrumb() {
    final segments = location.split('/').where((s) => s.isNotEmpty).toList();
    final labels = <String>[];
    for (final seg in segments) {
      final label = _segmentLabels[seg];
      if (label != null) labels.add(label);
      // Skip IDs (long alphanumeric strings without spaces)
    }
    return labels.isEmpty ? AppBrand.appName : labels.join(' \u203a ');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            _buildCrumb(),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _ConnectivityDot(isOnline: isOnline),
      ],
    );
  }
}

// ─── Connectivity Dot ────────────────────────────────────────────────────────

class _ConnectivityDot extends StatelessWidget {
  final bool isOnline;
  const _ConnectivityDot({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isOnline ? 'Online' : 'Offline',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isOnline ? Colors.green : Colors.grey,
          boxShadow: isOnline
              ? [BoxShadow(color: Colors.green.withAlpha(100), blurRadius: 4)]
              : null,
        ),
      ),
    );
  }
}
