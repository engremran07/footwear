import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../models/route_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../widgets/empty_state.dart';

class RoutesListScreen extends ConsumerWidget {
  const RoutesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;
    final routesAsync = isAdmin
        ? ref.watch(routesProvider)
        : ref.watch(routesBySellerProvider(user?.id ?? ''));

    return Scaffold(
      appBar: AppBar(title: Text(tr('routes', ref))),
      body: routesAsync.when(
        data: (routes) {
          if (routes.isEmpty) {
            return EmptyState(
              icon: Icons.route,
              message: tr('no_routes', ref),
            );
          }
          return ListView.builder(
            itemCount: routes.length,
            itemBuilder: (_, i) => _RouteTile(route: routes[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => context.push('/routes/new'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _RouteTile extends ConsumerWidget {
  final RouteModel route;
  const _RouteTile({required this.route});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text('${route.routeNumber}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer)),
        ),
        title: Text(route.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (route.area != null) route.area,
            '${route.totalShops} ${tr('shops', ref)}',
            if (route.assignedSellerName != null) route.assignedSellerName,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/routes/${route.id}'),
      ),
    );
  }
}
