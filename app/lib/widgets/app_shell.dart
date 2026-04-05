import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/network_provider.dart';
import '../models/user_model.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/services/permissions_service.dart';

// ─── App Shell ───────────────────────────────────────────────────────────────

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
    (icon: Icons.receipt_long, key: 'invoices', route: '/invoices'),
    (icon: Icons.analytics, key: 'reports', route: '/reports'),
    (icon: Icons.manage_accounts, key: 'users', route: '/users'),
    (icon: Icons.settings, key: 'settings', route: '/settings'),
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drawerCtrl;
  late final Animation<double> _drawerAnim;
  bool _isDrawerOpen = false;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _drawerAnim = CurvedAnimation(
      parent: _drawerCtrl,
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeIn,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionsService.requestOnFirstRun();
    });
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    super.dispose();
  }

  void _openDrawer() {
    setState(() => _isDrawerOpen = true);
    _drawerCtrl.forward();
  }

  void _closeDrawer() {
    _drawerCtrl.reverse().then((_) {
      if (mounted) setState(() => _isDrawerOpen = false);
    });
  }

  void _toggleDrawer() => _isDrawerOpen ? _closeDrawer() : _openDrawer();

  String? _parentRoute(String path) {
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;
    if (segs.length == 1) return '/';
    if (segs.length >= 3 && segs[2] == 'variants') {
      return '/${segs[0]}/${segs[1]}';
    }
    if (segs.length == 3 && segs[2] == 'edit') {
      return '/${segs[0]}/${segs[1]}';
    }
    if (segs.length == 2) return '/${segs[0]}';
    return '/';
  }

  List<({IconData icon, String key, String route})> _filteredItems(
      UserModel? user) {
    if (user == null) return [];
    if (user.isSeller) {
      return AppShell._navItems
          .where((e) =>
              e.route == '/' ||
              e.route == '/shops' ||
              e.route == '/products' ||
              e.route == '/inventory' ||
              e.route == '/invoices')
          .toList();
    }
    return AppShell._navItems.where((e) {
      if (e.route == '/settings' || e.route == '/users') return user.isAdmin;
      return true;
    }).toList();
  }

  List<({IconData icon, String key, String route})> _primaryNavItems(
      UserModel? user) {
    if (user == null) return [];
    if (user.isSeller) {
      return const [
        (icon: Icons.dashboard, key: 'dashboard', route: '/'),
        (icon: Icons.storefront, key: 'shops', route: '/shops'),
        (icon: Icons.receipt_long, key: 'invoices', route: '/invoices'),
        (icon: Icons.warehouse, key: 'inventory', route: '/inventory'),
        (icon: Icons.person, key: 'profile', route: '/profile'),
      ];
    }
    return const [
      (icon: Icons.dashboard, key: 'dashboard', route: '/'),
      (icon: Icons.route, key: 'routes', route: '/routes'),
      (icon: Icons.receipt_long, key: 'invoices', route: '/invoices'),
      (icon: Icons.analytics, key: 'reports', route: '/reports'),
      (icon: Icons.settings, key: 'settings', route: '/settings'),
    ];
  }

  int _selectedIndex(List<({IconData icon, String label, String route})> items,
      String location) {
    if (items.isEmpty) return 0;
    final idx = items.indexWhere((e) =>
        e.route == location ||
        (e.route != '/' && location.startsWith(e.route)));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final isWide = MediaQuery.of(context).size.width >= 720;
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? false;
    final currentLocation = GoRouterState.of(context).uri.path;

    final rawItems = _filteredItems(user);
    final navItems = rawItems
        .map((e) => (icon: e.icon, label: tr(e.key, ref), route: e.route))
        .toList();

    void onPopInvoked(bool didPop, dynamic result) {
      if (didPop) return;
      if (_isDrawerOpen) {
        _closeDrawer();
        return;
      }
      final parent = _parentRoute(currentLocation);
      if (parent != null) {
        context.go(parent);
      } else {
        SystemNavigator.pop();
      }
    }

    // ── Tablet/Desktop: NavigationRail (unchanged) ────────────────────────
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
                onProfile: () => context.go('/profile'),
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

    // ── Mobile: Zoom Drawer + WhatsApp AppBar + Bottom Nav ────────────────
    final rawPrimary = _primaryNavItems(user);
    final primaryItems = rawPrimary
        .map((e) => (icon: e.icon, label: tr(e.key, ref), route: e.route))
        .toList();

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final slideWidth = MediaQuery.of(context).size.width * 0.74;
    final profileLabel = tr('profile', ref);
    final signOutLabel = tr('sign_out', ref);
    final menuLabel = tr('menu', ref);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: onPopInvoked,
      child: AnimatedBuilder(
        animation: _drawerAnim,
        builder: (context, _) {
          final progress = _drawerAnim.value;
          final dx = isRtl ? -(progress * slideWidth) : progress * slideWidth;
          final scale = 1.0 - 0.08 * progress;
          final radius = 22.0 * progress;
          final shadowAlpha = (64 * progress).round().clamp(0, 64);

          return Stack(
            children: [
              // Drawer background
              Positioned.fill(
                child: _DrawerMenuScreen(
                  user: user,
                  navItems: navItems,
                  currentLocation: currentLocation,
                  isOnline: isOnline,
                  isRtl: isRtl,
                  profileLabel: profileLabel,
                  signOutLabel: signOutLabel,
                  onNavigate: (route) {
                    _closeDrawer();
                    context.go(route);
                  },
                  onProfile: () {
                    _closeDrawer();
                    context.go('/profile');
                  },
                  onSignOut: () =>
                      ref.read(authNotifierProvider.notifier).signOut(),
                ),
              ),

              // Main content with zoom transform (scale from edge, then slide)
              Transform.translate(
                offset: Offset(dx, 0),
                child: Transform.scale(
                  scale: scale,
                  alignment:
                      isRtl ? Alignment.centerRight : Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(shadowAlpha),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Scaffold(
                        appBar: _WhatsAppBar(
                          user: user,
                          currentLocation: currentLocation,
                          isOnline: isOnline,
                          menuLabel: menuLabel,
                          drawerAnim: _drawerAnim,
                          onMenuTap: _toggleDrawer,
                          onProfileTap: () {
                            if (_isDrawerOpen) _closeDrawer();
                            context.go('/profile');
                          },
                        ),
                        body: GestureDetector(
                          onTap: _isDrawerOpen ? _closeDrawer : null,
                          onHorizontalDragEnd: (d) {
                            final vel = d.primaryVelocity ?? 0;
                            if (!isRtl && vel > 200) _openDrawer();
                            if (!isRtl && vel < -200) _closeDrawer();
                            if (isRtl && vel < -200) _openDrawer();
                            if (isRtl && vel > 200) _closeDrawer();
                          },
                          behavior: HitTestBehavior.translucent,
                          child: AbsorbPointer(
                            absorbing: _isDrawerOpen,
                            child: widget.child,
                          ),
                        ),
                        bottomNavigationBar: primaryItems.isEmpty
                            ? null
                            : _WhatsAppBottomNav(
                                items: primaryItems,
                                currentLocation: currentLocation,
                                onTap: (route) {
                                  HapticFeedback.selectionClick();
                                  if (_isDrawerOpen) _closeDrawer();
                                  context.go(route);
                                },
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── WhatsApp-style App Bar ───────────────────────────────────────────────────

class _WhatsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final UserModel? user;
  final String currentLocation;
  final bool isOnline;
  final String menuLabel;
  final Animation<double> drawerAnim;
  final VoidCallback onMenuTap;
  final VoidCallback onProfileTap;

  const _WhatsAppBar({
    required this.user,
    required this.currentLocation,
    required this.isOnline,
    required this.menuLabel,
    required this.drawerAnim,
    required this.onMenuTap,
    required this.onProfileTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 2,
      leading: Tooltip(
        message: menuLabel,
        child: IconButton(
          icon: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: drawerAnim,
            semanticLabel: menuLabel,
          ),
          onPressed: onMenuTap,
        ),
      ),
      title: Row(
        children: [
          Image.asset(AppBrand.logoAsset, height: 30, fit: BoxFit.contain),
          const SizedBox(width: 8),
          Expanded(
            child: _BreadcrumbTitle(
              location: currentLocation,
              isOnline: isOnline,
            ),
          ),
        ],
      ),
      actions: [
        if (user != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: GestureDetector(
              onTap: onProfileTap,
              child: Semantics(
                label: 'Profile',
                button: true,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    _UserAvatar(user: user, radius: 17),
                    if (isOnline)
                      Positioned(
                        bottom: 1,
                        right: 1,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppBrand.successColor,
                            border: Border.all(color: cs.surface, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── WhatsApp-style Bottom Navigation ────────────────────────────────────────

class _WhatsAppBottomNav extends StatelessWidget {
  final List<({IconData icon, String label, String route})> items;
  final String currentLocation;
  final ValueChanged<String> onTap;

  const _WhatsAppBottomNav({
    required this.items,
    required this.currentLocation,
    required this.onTap,
  });

  int get _selectedIndex {
    final idx = items.indexWhere((e) =>
        e.route == currentLocation ||
        (e.route != '/' && currentLocation.startsWith(e.route)));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => onTap(items[i].route),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      animationDuration: const Duration(milliseconds: 300),
      destinations: items
          .map(
            (item) => NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.icon, color: AppBrand.primaryColor),
              label: item.label,
              tooltip: item.label,
            ),
          )
          .toList(),
    );
  }
}

// ─── Zoom Drawer Menu Screen ──────────────────────────────────────────────────

class _DrawerMenuScreen extends StatelessWidget {
  final UserModel? user;
  final List<({IconData icon, String label, String route})> navItems;
  final String currentLocation;
  final bool isOnline;
  final bool isRtl;
  final String profileLabel;
  final String signOutLabel;
  final ValueChanged<String> onNavigate;
  final VoidCallback onProfile;
  final VoidCallback onSignOut;

  const _DrawerMenuScreen({
    required this.user,
    required this.navItems,
    required this.currentLocation,
    required this.isOnline,
    required this.isRtl,
    required this.profileLabel,
    required this.signOutLabel,
    required this.onNavigate,
    required this.onProfile,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final drawerWidth = MediaQuery.of(context).size.width * 0.74;

    return Align(
      alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
      child: SizedBox(
        width: drawerWidth,
        child: Material(
          color: cs.surface,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // User header
                InkWell(
                  onTap: onProfile,
                  child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(20, 28, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset(AppBrand.logoAsset,
                            height: 46, fit: BoxFit.contain),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _UserAvatar(user: user, radius: 23),
                                if (isOnline)
                                  Positioned(
                                    bottom: 1,
                                    right: 1,
                                    child: Container(
                                      width: 11,
                                      height: 11,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppBrand.successColor,
                                        border: Border.all(
                                            color: cs.surface, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            if (user != null)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      user!.displayName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      user!.email,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 5),
                                    _RoleBadge(role: user!.role, small: true),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),

                // Nav items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: navItems.length,
                    itemBuilder: (ctx, i) {
                      final item = navItems[i];
                      final isSel = item.route == currentLocation ||
                          (item.route != '/' &&
                              currentLocation.startsWith(item.route));
                      return ListTile(
                        leading: Icon(
                          item.icon,
                          size: 22,
                          color: isSel
                              ? AppBrand.primaryColor
                              : cs.onSurfaceVariant,
                        ),
                        title: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isSel ? FontWeight.w600 : FontWeight.normal,
                            color: isSel ? AppBrand.primaryColor : cs.onSurface,
                          ),
                        ),
                        selected: isSel,
                        selectedTileColor: AppBrand.primaryColor.withAlpha(20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        horizontalTitleGap: 8,
                        contentPadding:
                            const EdgeInsetsDirectional.fromSTEB(18, 0, 14, 0),
                        onTap: () => onNavigate(item.route),
                      );
                    },
                  ),
                ),

                const Divider(height: 1),

                // Footer
                ListTile(
                  leading: Icon(Icons.person_outline,
                      color: cs.onSurfaceVariant, size: 22),
                  title: Text(profileLabel,
                      style: TextStyle(fontSize: 14, color: cs.onSurface)),
                  contentPadding:
                      const EdgeInsetsDirectional.fromSTEB(18, 0, 14, 0),
                  horizontalTitleGap: 8,
                  onTap: onProfile,
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: cs.error, size: 22),
                  title: Text(signOutLabel,
                      style: TextStyle(fontSize: 14, color: cs.error)),
                  contentPadding:
                      const EdgeInsetsDirectional.fromSTEB(18, 0, 14, 0),
                  horizontalTitleGap: 8,
                  onTap: onSignOut,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Scrollable NavigationRail (tablet/desktop) ───────────────────────────────

class _ScrollableNavRail extends StatelessWidget {
  final bool extended;
  final int? selectedIndex;
  final List<({IconData icon, String label, String route})> items;
  final ValueChanged<int> onItem;
  final VoidCallback onLogout;
  final VoidCallback onProfile;
  final UserModel? user;
  final String signOutTooltip;
  final bool isOnline;

  const _ScrollableNavRail({
    required this.extended,
    required this.selectedIndex,
    required this.items,
    required this.onItem,
    required this.onLogout,
    required this.onProfile,
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
            const Divider(height: 1),
            if (user != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onProfile,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: extended
                        ? Row(
                            children: [
                              _UserAvatar(user: user, radius: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user!.displayName,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface),
                                      overflow: TextOverflow.ellipsis,
                                    ),
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
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onItem(i);
                          },
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
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: fg,
                                      fontWeight: sel
                                          ? FontWeight.w600
                                          : FontWeight.normal),
                                ),
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
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onItem(i);
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Center(
                              child: Icon(item.icon, size: 20, color: fg),
                            ),
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
    final borderColor = user?.isAdmin == true
        ? AppBrand.adminRoleColor
        : AppBrand.sellerRoleColor;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: CircleAvatar(
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

// ─── Role Badge ───────────────────────────────────────────────────────────────

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

  const _BreadcrumbTitle({
    required this.location,
    required this.isOnline,
  });

  static const _segmentLabels = <String, String>{
    'customers': 'Customers',
    'products': 'Products',
    'routes': 'Routes',
    'shops': 'Shops',
    'inventory': 'Inventory',
    'invoices': 'Invoices',
    'reports': 'Reports',
    'settings': 'Settings',
    'profile': 'Profile',
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
    }
    return labels.isEmpty ? AppBrand.appName : labels.join(' \u203a ');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _buildCrumb(),
              key: ValueKey(location),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ConnectivityDot(isOnline: isOnline),
      ],
    );
  }
}

// ─── Connectivity Dot ─────────────────────────────────────────────────────────

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
