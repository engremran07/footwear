import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/network_provider.dart';
import '../providers/shop_provider.dart';
import '../models/user_model.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/services/permissions_service.dart';
import '../core/utils/snack_helper.dart';

// ─── App Shell ───────────────────────────────────────────────────────────────

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _navItems = [
    (icon: Icons.dashboard, key: 'dashboard', route: '/'),
    (icon: Icons.route, key: 'routes', route: '/routes'),
    (icon: Icons.storefront, key: 'shops', route: '/shops'),
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
  DateTime? _lastBackPress; // F-03: double-back-to-exit tracking

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

  // ─── Quick-action map for long-press on bottom nav ──────────────────────
  // Returns localized quick-action entries for the given route.
  List<({IconData icon, String label, String route})> _quickActionsFor(
    String route,
  ) {
    switch (route) {
      case '/shops':
        return [
          (
            icon: Icons.add_business,
            label: tr('new_shop', ref),
            route: '/shops/new',
          ),
        ];
      case '/routes':
        return [
          (
            icon: Icons.add_road,
            label: tr('new_route', ref),
            route: '/routes/new',
          ),
        ];
      case '/products':
        return [
          (
            icon: Icons.add_box,
            label: tr('new_product', ref),
            route: '/products/new',
          ),
        ];
      case '/invoices':
        return [
          (
            icon: Icons.add_circle_outline,
            label: tr('sale_invoice', ref),
            route: '/invoices/new',
          ),
        ];
      case '/inventory':
        return [];
      default:
        return [];
    }
  }

  void _onNavLongPress(
    BuildContext ctx,
    ({IconData icon, String label, String route}) item,
  ) {
    HapticFeedback.mediumImpact();
    final actions = _quickActionsFor(item.route);
    if (actions.isEmpty) return;
    showModalBottomSheet<void>(
      context: ctx,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              item.label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const Divider(height: 1),
          for (final action in actions)
            ListTile(
              leading: Icon(action.icon, color: AppBrand.primaryColor),
              title: Text(action.label),
              onTap: () {
                Navigator.pop(ctx);
                context.push(action.route);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

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
    UserModel? user,
  ) {
    if (user == null) return [];
    if (user.isSeller) {
      return AppShell._navItems
          .where(
            (e) =>
                e.route == '/' ||
                e.route == '/shops' ||
                e.route == '/products' ||
                e.route == '/inventory' ||
                e.route == '/invoices',
          )
          .toList();
    }
    return AppShell._navItems.where((e) {
      if (e.route == '/settings' || e.route == '/users') return user.isAdmin;
      return true;
    }).toList();
  }

  List<({IconData icon, String key, String route})> _primaryNavItems(
    UserModel? user,
  ) {
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
      (icon: Icons.storefront, key: 'shops', route: '/shops'),
      (icon: Icons.receipt_long, key: 'invoices', route: '/invoices'),
      (icon: Icons.analytics, key: 'reports', route: '/reports'),
      (icon: Icons.warehouse, key: 'inventory', route: '/inventory'),
    ];
  }

  int _selectedIndex(
    List<({IconData icon, String label, String route})> items,
    String location,
  ) {
    if (items.isEmpty) return 0;
    final idx = items.indexWhere(
      (e) =>
          e.route == location ||
          (e.route != '/' && location.startsWith(e.route)),
    );
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final isWide = MediaQuery.of(context).size.width >= 720;
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
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
      // 1. If GoRouter has a pushed route on the stack, pop it naturally
      if (GoRouter.of(context).canPop()) {
        context.pop();
        return;
      }
      // 2. If on a non-root top-level tab, go to dashboard
      if (currentLocation != '/' &&
          navItems.any((e) => e.route == currentLocation)) {
        context.go('/');
        return;
      }
      // 3. At root '/': require double-back within 2 seconds (F-03)
      final now = DateTime.now();
      if (_lastBackPress != null &&
          now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
        SystemNavigator.pop();
        return;
      }
      _lastBackPress = now;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(infoSnackBar(tr('press_back_again_to_exit', ref)));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            _isDrawerOpen && !isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: PopScope(
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
                  alignment: isRtl
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF000000).withAlpha(shadowAlpha),
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
                          isTopLevel: primaryItems.any(
                            (e) => e.route == currentLocation,
                          ),
                          onMenuTap: _toggleDrawer,
                          onBack: () {
                            if (_isDrawerOpen) {
                              _closeDrawer();
                              return;
                            }
                            if (GoRouter.of(context).canPop()) {
                              context.pop();
                              return;
                            }
                            final parent = _parentRoute(currentLocation);
                            if (parent != null) context.go(parent);
                          },
                          onProfileTap: () {
                            if (_isDrawerOpen) _closeDrawer();
                            context.go('/profile');
                          },
                        ),
                        body: GestureDetector(
                          onTap: _isDrawerOpen ? _closeDrawer : null,
                          onHorizontalDragEnd: (d) {
                            final vel = d.primaryVelocity ?? 0;
                            if (_isDrawerOpen) {
                              // Only close when drawer already open
                              if (!isRtl && vel < -200) _closeDrawer();
                              if (isRtl && vel > 200) _closeDrawer();
                              return;
                            }
                            // Only allow tab swipe on top-level nav routes
                            final isTopLevel = primaryItems.any(
                              (e) => e.route == currentLocation,
                            );
                            final absVel = vel.abs();
                            // Drawer closed: tab-swipe (high vel) OR drawer-open (low vel)
                            if (!isRtl) {
                              if (absVel >= 400 &&
                                  isTopLevel &&
                                  primaryItems.length > 1) {
                                final idx = primaryItems.indexWhere(
                                  (e) => e.route == currentLocation,
                                );
                                if (vel < 0 &&
                                    idx >= 0 &&
                                    idx < primaryItems.length - 1) {
                                  // Forward swipe (left) → next tab
                                  HapticFeedback.selectionClick();
                                  context.go(primaryItems[idx + 1].route);
                                } else if (vel > 0 && idx > 0) {
                                  // Backward swipe (right) → previous tab
                                  HapticFeedback.selectionClick();
                                  context.go(primaryItems[idx - 1].route);
                                }
                              } else if (vel > 200) {
                                if (!isTopLevel) {
                                  HapticFeedback.lightImpact();
                                  if (GoRouter.of(context).canPop()) {
                                    context.pop();
                                  } else {
                                    final parent =
                                        _parentRoute(currentLocation);
                                    if (parent != null) context.go(parent);
                                  }
                                } else {
                                  _openDrawer();
                                }
                              }
                            } else {
                              if (absVel >= 400 &&
                                  isTopLevel &&
                                  primaryItems.length > 1) {
                                final idx = primaryItems.indexWhere(
                                  (e) => e.route == currentLocation,
                                );
                                if (vel > 0 &&
                                    idx >= 0 &&
                                    idx < primaryItems.length - 1) {
                                  // RTL forward swipe (right) → next tab
                                  HapticFeedback.selectionClick();
                                  context.go(primaryItems[idx + 1].route);
                                } else if (vel < 0 && idx > 0) {
                                  // RTL backward swipe (left) → previous tab
                                  HapticFeedback.selectionClick();
                                  context.go(primaryItems[idx - 1].route);
                                }
                              } else if (vel < -200) {
                                if (!isTopLevel) {
                                  HapticFeedback.lightImpact();
                                  if (GoRouter.of(context).canPop()) {
                                    context.pop();
                                  } else {
                                    final parent =
                                        _parentRoute(currentLocation);
                                    if (parent != null) context.go(parent);
                                  }
                                } else {
                                  _openDrawer();
                                }
                              }
                            }
                          },
                          behavior: HitTestBehavior.translucent,
                          child: AbsorbPointer(
                            absorbing: _isDrawerOpen,
                            child: widget.child,
                          ),
                        ),
                        bottomNavigationBar: primaryItems.isEmpty
                            ? null
                            : _ArcticBottomNav(
                                items: primaryItems,
                                currentLocation: currentLocation,
                                onTap: (route) {
                                  HapticFeedback.selectionClick();
                                  if (_isDrawerOpen) _closeDrawer();
                                  context.go(route);
                                },
                                onLongPress: (item) =>
                                    _onNavLongPress(context, item),
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
  final bool isTopLevel;
  final VoidCallback onBack;

  const _WhatsAppBar({
    required this.user,
    required this.currentLocation,
    required this.isOnline,
    required this.menuLabel,
    required this.drawerAnim,
    required this.onMenuTap,
    required this.onProfileTap,
    required this.isTopLevel,
    required this.onBack,
  });

  @override
  // +2 px for aurora accent stripe at the bottom edge
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 2);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      // Arctic glacier gradient fills the full AppBar area
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppBrand.appBarGradientDark
              : AppBrand.appBarGradientLight,
        ),
        child: const SizedBox.expand(),
      ),
      // Aurora accent 2 px stripe at the bottom
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(2),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: AppBrand.auroraAccent),
          child: SizedBox(height: 2, width: double.infinity),
        ),
      ),
      leading: isTopLevel
          ? Tooltip(
              message: menuLabel,
              child: IconButton(
                icon: AnimatedIcon(
                  icon: AnimatedIcons.menu_close,
                  progress: drawerAnim,
                  semanticLabel: menuLabel,
                ),
                onPressed: onMenuTap,
              ),
            )
          : IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              tooltip: 'Back',
              onPressed: onBack,
            ),
      title: _BreadcrumbTitle(location: currentLocation, isOnline: isOnline),
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

// ─── Arctic Bottom Navigation ───────────────────────────────────────────────

class _ArcticBottomNav extends StatelessWidget {
  final List<({IconData icon, String label, String route})> items;
  final String currentLocation;
  final ValueChanged<String> onTap;
  final void Function(({IconData icon, String label, String route}))
  onLongPress;

  const _ArcticBottomNav({
    required this.items,
    required this.currentLocation,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1618) : const Color(0xFFFFFFFF),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1E3340) : const Color(0xFFB6DFF0),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppBrand.primaryColor.withAlpha(28),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: items.map((item) {
              final isSelected =
                  item.route == currentLocation ||
                  (item.route != '/' && currentLocation.startsWith(item.route));
              return Expanded(
                child: _ArcticNavItem(
                  item: item,
                  isSelected: isSelected,
                  onTap: () => onTap(item.route),
                  onLongPress: () => onLongPress(item),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ArcticNavItem extends StatefulWidget {
  final ({IconData icon, String label, String route}) item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ArcticNavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_ArcticNavItem> createState() => _ArcticNavItemState();
}

class _ArcticNavItemState extends State<_ArcticNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      value: 0,
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.87,
    ).animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _pressCtrl.forward();
  void _onTapUp(TapUpDetails _) => _pressCtrl.reverse();
  void _onTapCancel() => _pressCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = isDark
        ? const Color(0xFF81D4FA)
        : AppBrand.primaryColor;
    final color = widget.isSelected ? selectedColor : cs.onSurfaceVariant;

    return Semantics(
      label: widget.item.label,
      selected: widget.isSelected,
      button: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated pill indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.fastOutSlowIn,
                  height: 3,
                  width: widget.isSelected ? 24 : 0,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? selectedColor
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Icon(widget.item.icon, size: 22, color: color),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: widget.isSelected
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: color,
                    letterSpacing: widget.isSelected ? 0.2 : 0,
                  ),
                  child: Text(
                    widget.item.label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
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

    return Material(
      color: cs.surface,
      child: Align(
        alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
        child: SizedBox(
          width: drawerWidth,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Arctic gradient drawer header
                DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: AppBrand.drawerHeaderGradient,
                  ),
                  child: InkWell(
                    onTap: onProfile,
                    splashColor: const Color(
                      0x1FFFFFFF,
                    ), // white12 — ink on dark gradient header
                    highlightColor: const Color(
                      0x1AFFFFFF,
                    ), // white10 — ink on dark gradient header
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        20,
                        28,
                        20,
                        18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                            color: AppBrand.onPrimary,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              if (user != null)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        user!.displayName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppBrand.onPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        user!.email,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppBrand.onPrimaryMuted,
                                        ),
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
                ),
                const Divider(height: 1),

                // Nav items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: navItems.length,
                    itemBuilder: (ctx, i) {
                      final item = navItems[i];
                      final isSel =
                          item.route == currentLocation ||
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
                            fontWeight: isSel
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSel ? AppBrand.primaryColor : cs.onSurface,
                          ),
                        ),
                        selected: isSel,
                        selectedTileColor: AppBrand.primaryColor.withAlpha(20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        horizontalTitleGap: 8,
                        contentPadding: const EdgeInsetsDirectional.fromSTEB(
                          18,
                          0,
                          14,
                          0,
                        ),
                        onTap: () => onNavigate(item.route),
                      );
                    },
                  ),
                ),

                const Divider(height: 1),

                // Footer
                ListTile(
                  leading: Icon(
                    Icons.person_outline,
                    color: cs.onSurfaceVariant,
                    size: 22,
                  ),
                  title: Text(
                    profileLabel,
                    style: TextStyle(fontSize: 14, color: cs.onSurface),
                  ),
                  contentPadding: const EdgeInsetsDirectional.fromSTEB(
                    18,
                    0,
                    14,
                    0,
                  ),
                  horizontalTitleGap: 8,
                  onTap: onProfile,
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: cs.error, size: 22),
                  title: Text(
                    signOutLabel,
                    style: TextStyle(fontSize: 14, color: cs.error),
                  ),
                  contentPadding: const EdgeInsetsDirectional.fromSTEB(
                    18,
                    0,
                    14,
                    0,
                  ),
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
                          Image.asset(
                            AppBrand.logoAsset,
                            width: 160,
                            height: 66,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 4),
                          _ConnectivityDot(isOnline: isOnline),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              AppBrand.logoAsset,
                              width: 52,
                              height: 34,
                              fit: BoxFit.contain,
                            ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
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
                                        color: cs.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    _RoleBadge(role: user!.role, small: true),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Center(child: _UserAvatar(user: user, radius: 14)),
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    final sel = selectedIndex == i;
                    final bg = sel ? cs.secondaryContainer : Colors.transparent;
                    final fg = sel
                        ? cs.onSecondaryContainer
                        : cs.onSurfaceVariant;
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
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Row(
                              children: [
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
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
        backgroundImage: const AssetImage(AppBrand.logoAsset),
      ),
    );
  }
}

// ─── Role Badge ───────────────────────────────────────────────────────────────

class _RoleBadge extends ConsumerWidget {
  final UserRole role;
  final bool small;

  const _RoleBadge({required this.role, this.small = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, color) = switch (role) {
      UserRole.admin => (tr('role_admin', ref), AppBrand.adminRoleColor),
      UserRole.seller => (tr('role_seller', ref), AppBrand.sellerRoleColor),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 1 : 2,
      ),
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

class _BreadcrumbTitle extends ConsumerWidget {
  final String location;
  final bool isOnline;

  const _BreadcrumbTitle({required this.location, required this.isOnline});

  // Segment keys that map to locale keys.
  static const _segmentKeys = <String>[
    'products',
    'routes',
    'shops',
    'inventory',
    'invoices',
    'reports',
    'settings',
    'profile',
    'variants',
    'edit',
    'new',
  ];

  String _buildCrumb(WidgetRef ref) {
    final segments = location.split('/').where((s) => s.isNotEmpty).toList();

    // For leaf entity detail pages (e.g. /shops/{id}): show only the entity
    // name — no parent prefix — to maximise AppBar space.
    if (segments.length == 2 && !_segmentKeys.contains(segments[1])) {
      final entityName = _lookupEntityName(ref, segments[0], segments[1]);
      if (entityName != null) return entityName;
    }

    final labels = <String>[];
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (_segmentKeys.contains(seg)) {
        labels.add(tr(seg, ref));
      } else if (i > 0 && _segmentKeys.contains(segments[i - 1])) {
        // ID segment after a known parent — try to look up entity name.
        final entityName = _lookupEntityName(ref, segments[i - 1], seg);
        labels.add(entityName ?? tr('details', ref));
      }
    }
    return labels.isEmpty ? AppBrand.appName : labels.join(' \u203a ');
  }

  /// Returns the display name for a known entity type, or null if unknown.
  String? _lookupEntityName(WidgetRef ref, String parent, String id) {
    if (parent == 'shops') {
      return ref.watch(shopDetailProvider(id)).value?.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _buildCrumb(ref),
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

class _ConnectivityDot extends ConsumerWidget {
  final bool isOnline;
  const _ConnectivityDot({required this.isOnline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: isOnline ? tr('online', ref) : tr('offline', ref),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isOnline ? AppBrand.successColor : AppBrand.stockColor,
          boxShadow: isOnline
              ? [
                  BoxShadow(
                    color: AppBrand.successColor.withAlpha(100),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
