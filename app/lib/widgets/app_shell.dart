import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/notification_provider.dart';
import '../models/user_model.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/formatters.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _navItems = [
    (icon: Icons.dashboard, key: 'dashboard', route: '/'),
    (icon: Icons.inventory_2, key: 'products', route: '/products'),
    (icon: Icons.layers, key: 'inventory', route: '/inventory'),
    (icon: Icons.shopping_cart, key: 'orders', route: '/orders'),
    (icon: Icons.people, key: 'customers', route: '/customers'),
    (icon: Icons.assignment_return_outlined, key: 'returns', route: '/returns'),
    (icon: Icons.person, key: 'workers', route: '/workers'),
    (icon: Icons.receipt_long, key: 'expenses', route: '/expenses'),
    (icon: Icons.attach_money, key: 'cash', route: '/cash'),
    (icon: Icons.approval, key: 'approvals', route: '/approvals'),
    (
      icon: Icons.local_shipping,
      key: 'purchase_orders',
      route: '/purchase-orders'
    ),
    (icon: Icons.store, key: 'suppliers', route: '/suppliers'),
    (icon: Icons.check_circle, key: 'qc', route: '/qc'),
    (icon: Icons.delete_sweep, key: 'waste', route: '/waste'),
    (icon: Icons.bar_chart, key: 'pnl', route: '/pnl'),
    (icon: Icons.analytics, key: 'reports', route: '/reports'),
    (icon: Icons.settings, key: 'settings', route: '/settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final isWide = MediaQuery.of(context).size.width >= 720;

    final rawItems = _filteredItems(user);
    // Resolve translation keys to localized labels
    final navItems = rawItems
        .map((e) => (icon: e.icon, label: tr(e.key, ref), route: e.route))
        .toList();
    final currentLocation = GoRouterState.of(context).uri.path;

    if (isWide) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScrollableNavRail(
              extended: MediaQuery.of(context).size.width >= 1024,
              selectedIndex: _selectedIndex(navItems, currentLocation),
              items: navItems,
              onItem: (i) => context.go(navItems[i].route),
              onLogout: () => ref.read(authNotifierProvider.notifier).signOut(),
              notificationBell: _NotificationBell(),
              connectionDot: _ConnectionDot(),
              user: user,
              signOutTooltip: tr('sign_out', ref),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppBrand.appName),
        actions: [
          _ConnectionDot(),
          _NotificationBell(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: tr('sign_out', ref),
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
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
          DrawerHeader(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _UserAvatar(user: user, radius: 28),
                  const SizedBox(height: 8),
                  if (user != null) ...[
                    Text(user.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(user.email,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 4),
                    _RoleBadge(role: user.role),
                  ] else ...[
                    const Text(AppBrand.appName,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ],
              ),
            ),
          ),
          ...navItems.map((e) => NavigationDrawerDestination(
                icon: Icon(e.icon),
                label: Text(e.label),
              )),
        ],
      ),
      body: child,
    );
  }

  List<({IconData icon, String key, String route})> _filteredItems(
      UserModel? user) {
    if (user == null) return [];
    return _navItems.where((item) {
      if (item.route == '/workers' ||
          item.route == '/cash' ||
          item.route == '/reports') {
        return user.isManager;
      }
      if (item.route == '/approvals' || item.route == '/settings') {
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
}

// ─── Scrollable side navigation rail ─────────────────────────────────────────

class _ScrollableNavRail extends StatelessWidget {
  final bool extended;
  final int? selectedIndex;
  final List<({IconData icon, String label, String route})> items;
  final ValueChanged<int> onItem;
  final VoidCallback onLogout;
  final Widget? notificationBell;
  final Widget? connectionDot;
  final UserModel? user;
  final String signOutTooltip;

  const _ScrollableNavRail({
    required this.extended,
    required this.selectedIndex,
    required this.items,
    required this.onItem,
    required this.onLogout,
    this.notificationBell,
    this.connectionDot,
    this.user,
    this.signOutTooltip = 'Sign out',
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
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(AppBrand.logoIcon, size: 26, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(AppBrand.appName,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: cs.primary)),
                        ],
                      )
                    : Icon(AppBrand.logoIcon, size: 26, color: cs.primary),
              ),
            ),
            // ── User profile card ──
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
                          if (connectionDot != null) connectionDot!,
                        ],
                      )
                    : Column(
                        children: [
                          _UserAvatar(user: user, radius: 14),
                          if (connectionDot != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: connectionDot!,
                            ),
                        ],
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (notificationBell != null) notificationBell!,
                    IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: signOutTooltip,
                      onPressed: onLogout,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Notification Bell with Badge ────────────────────────────────────────────

class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeCount = ref.watch(notificationBadgeCountProvider);

    return IconButton(
      icon: Badge(
        isLabelVisible: badgeCount > 0,
        label: Text('$badgeCount'),
        child: const Icon(Icons.notifications_outlined),
      ),
      tooltip: tr('notifications', ref),
      onPressed: () => _showNotificationPanel(context, ref),
    );
  }

  void _showNotificationPanel(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollCtrl) {
            // Use Consumer so the panel watches the stream reactively
            return Consumer(builder: (context, innerRef, _) {
              final notifAsync = innerRef.watch(appNotificationsProvider);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Text(tr('notifications', innerRef),
                            style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: notifAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) =>
                          Center(child: Text(tr('error', innerRef))),
                      data: (notifications) => notifications.isEmpty
                          ? Center(
                              child: Text(tr('no_notifications', innerRef)))
                          : ListView.separated(
                              controller: scrollCtrl,
                              itemCount: notifications.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final n = notifications[i];
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: n.id.startsWith('order')
                                        ? Colors.blue.withValues(alpha: 0.15)
                                        : Colors.orange.withValues(alpha: 0.15),
                                    child: Icon(
                                      n.id.startsWith('order')
                                          ? Icons.shopping_cart
                                          : Icons.approval,
                                      size: 18,
                                      color: n.id.startsWith('order')
                                          ? Colors.blue
                                          : Colors.orange,
                                    ),
                                  ),
                                  title: Text(n.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14)),
                                  subtitle: Text(n.subtitle,
                                      style: const TextStyle(fontSize: 12)),
                                  trailing: Text(
                                    AppFormatters.dateTime(n.createdAt),
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                  dense: true,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    context.go(n.route);
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ],
              );
            });
          },
        );
      },
    );
  }
}

// ─── Connection Status Dot ───────────────────────────────────────────────────

class _ConnectionDot extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    return Tooltip(
      message: tr(online ? 'online' : 'offline', ref),
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: online ? Colors.green : Colors.red,
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
      UserRole.admin => ('Admin', Colors.deepPurple),
      UserRole.manager => ('Manager', Colors.blue),
      UserRole.viewer => ('Viewer', Colors.teal),
      UserRole.workerPk => ('Worker PK', Colors.orange),
      UserRole.workerKsa => ('Worker KSA', Colors.orange),
      UserRole.seller => ('Seller', Colors.green),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
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
