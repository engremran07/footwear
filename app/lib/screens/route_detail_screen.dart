import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/snack_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/shop_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';

class RouteDetailScreen extends ConsumerWidget {
  final String routeId;
  const RouteDetailScreen({super.key, required this.routeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeAsync = ref.watch(routeDetailProvider(routeId));
    final shopsAsync = ref.watch(shopsByRouteProvider(routeId));
    final user = ref.watch(authUserProvider).value;
    final isAdmin = user?.isAdmin ?? false;
    final canAddShop =
        isAdmin || (user?.isSeller == true && user?.assignedRouteId == routeId);
    final theme = Theme.of(context);

    return Scaffold(
      body: routeAsync.when(
        data: (route) {
          if (route == null) {
            return Center(child: Text(tr('not_found', ref)));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isAdmin)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4, top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: tr('tooltip_edit_route', ref),
                        onPressed: () => context.push('/routes/$routeId/edit'),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: AppBrand.errorColor,
                        ),
                        tooltip: tr('tooltip_delete_route', ref),
                        onPressed: () async {
                          final ok = await ConfirmDialog.show(
                            context,
                            title: tr('delete', ref),
                            message: tr('confirm_delete_route', ref),
                          );
                          if (ok != true) return;
                          try {
                            await ref
                                .read(routeNotifierProvider.notifier)
                                .delete(routeId);
                            if (context.mounted) context.go('/routes');
                          } catch (e) {
                            if (context.mounted) {
                              final key = AppErrorMapper.key(e);
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(errorSnackBar(tr(key, ref)));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              // Route info card
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            radius: 24,
                            child: Text(
                              '${route.routeNumber}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  route.name,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (route.area != null || route.city != null)
                                  Text(
                                    [
                                      route.area,
                                      route.city,
                                    ].where((e) => e != null).join(', '),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (route.assignedSellerName != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${tr('assigned_seller', ref)}: ${route.assignedSellerName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (route.description != null &&
                          route.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          route.description!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Route performance strip
              shopsAsync.whenOrNull(
                    data: (shops) {
                      if (shops.isEmpty) return const SizedBox.shrink();
                      final totalOutstanding = shops.fold<double>(
                        0,
                        (s, shop) => s + (shop.balance > 0 ? shop.balance : 0),
                      );
                      final shopsWithDebt = shops
                          .where((s) => s.balance > 0)
                          .length;
                      final cs = Theme.of(context).colorScheme;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _RStat(
                              icon: Icons.store,
                              label: tr('shops', ref),
                              value: '${shops.length}',
                              color: cs.primary,
                            ),
                            _RStat(
                              icon: Icons.warning_amber,
                              label: tr('outstanding', ref),
                              value: AppFormatters.sar(totalOutstanding),
                              color: totalOutstanding > 0
                                  ? AppTheme.debtFg(cs)
                                  : AppTheme.clearFg(cs),
                            ),
                            _RStat(
                              icon: Icons.account_balance_wallet,
                              label: tr('route_with_debt', ref),
                              value: '$shopsWithDebt',
                              color: shopsWithDebt > 0
                                  ? AppBrand.warningColor
                                  : AppTheme.clearFg(cs),
                            ),
                          ],
                        ),
                      );
                    },
                  ) ??
                  const SizedBox.shrink(),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  tr('shops', ref),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Shops list
              Expanded(
                child: shopsAsync.when(
                  data: (shops) {
                    if (shops.isEmpty) {
                      return EmptyState(
                        icon: Icons.store,
                        message: tr('no_shops', ref),
                      );
                    }
                    // Sort by outstanding balance (highest first)
                    final sorted = [...shops]
                      ..sort((a, b) => b.balance.compareTo(a.balance));
                    return ListView.builder(
                      itemCount: sorted.length,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemBuilder: (_, i) {
                        final shop = sorted[i];
                        final hasDebt = shop.balance > 0;
                        final cs = Theme.of(context).colorScheme;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: hasDebt
                                  ? AppTheme.debtBg(cs)
                                  : AppTheme.clearBg(cs),
                              child: Icon(
                                Icons.store,
                                color: hasDebt
                                    ? AppTheme.debtFg(cs)
                                    : AppTheme.clearFg(cs),
                              ),
                            ),
                            title: Text(
                              shop.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              shop.phone ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              AppFormatters.sar(shop.balance),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: hasDebt
                                    ? AppTheme.debtFg(cs)
                                    : AppTheme.clearFg(cs),
                              ),
                            ),
                            onTap: () => context.push('/shops/${shop.id}'),
                          ),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => mappedErrorState(
                    error: e,
                    ref: ref,
                    onRetry: () =>
                        ref.invalidate(shopsByRouteProvider(routeId)),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => mappedErrorState(
          error: e,
          ref: ref,
          onRetry: () => ref.invalidate(routeDetailProvider(routeId)),
        ),
      ),
      floatingActionButton: canAddShop
          ? FloatingActionButton(
              onPressed: () => context.push('/shops/new?routeId=$routeId'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _RStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _RStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
