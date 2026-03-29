import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/shop_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

class RouteDetailScreen extends ConsumerWidget {
  final String routeId;
  const RouteDetailScreen({super.key, required this.routeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeAsync = ref.watch(routeDetailProvider(routeId));
    final shopsAsync = ref.watch(shopsByRouteProvider(routeId));
    final user = ref.watch(authUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;
    final canAddShop =
        isAdmin || (user?.isSeller == true && user?.assignedRouteId == routeId);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: routeAsync.when(
          data: (r) => Text(r?.name ?? tr('route', ref)),
          loading: () => Text(tr('route', ref)),
          error: (_, __) => Text(tr('route', ref)),
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => context.push('/routes/$routeId/edit'),
            ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final ok = await ConfirmDialog.show(
                  context,
                  title: tr('delete', ref),
                  message: 'Delete this route?',
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
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(tr(key, ref))));
                  }
                }
              },
            ),
        ],
      ),
      body: routeAsync.when(
        data: (route) {
          if (route == null) {
            return Center(child: Text(tr('not_found', ref)));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                            child: Text('${route.routeNumber}',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        theme.colorScheme.onPrimaryContainer)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(route.name,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold)),
                                if (route.area != null || route.city != null)
                                  Text(
                                    [route.area, route.city]
                                        .where((e) => e != null)
                                        .join(', '),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
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
                            Text(
                                '${tr('assigned_seller', ref)}: ${route.assignedSellerName}'),
                          ],
                        ),
                      ],
                      if (route.description != null &&
                          route.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(route.description!,
                            style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(tr('shops', ref),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              // Shops list
              Expanded(
                child: shopsAsync.when(
                  data: (shops) {
                    if (shops.isEmpty) {
                      return EmptyState(
                          icon: Icons.store, message: tr('no_shops', ref));
                    }
                    return ListView.builder(
                      itemCount: shops.length,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemBuilder: (_, i) {
                        final shop = shops[i];
                        final hasDebt = shop.balance > 0;
                        final cs = Theme.of(context).colorScheme;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: hasDebt
                                  ? AppTheme.debtBg(cs)
                                  : AppTheme.clearBg(cs),
                              child: Icon(Icons.store,
                                  color: hasDebt
                                      ? AppTheme.debtFg(cs)
                                      : AppTheme.clearFg(cs)),
                            ),
                            title: Text(shop.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(shop.phone ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  error: (e, _) => Center(child: Text('$e')),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
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
