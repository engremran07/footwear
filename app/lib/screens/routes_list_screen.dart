import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../models/route_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';

class RoutesListScreen extends ConsumerStatefulWidget {
  const RoutesListScreen({super.key});

  @override
  ConsumerState<RoutesListScreen> createState() => _RoutesListScreenState();
}

class _RoutesListScreenState extends ConsumerState<RoutesListScreen> {
  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final user = ref.watch(authUserProvider).value;
    final isAdmin = user?.isAdmin ?? false;
    final routesAsync = isAdmin
        ? ref.watch(routesProvider)
        : ref.watch(routesBySellerProvider(user?.id ?? ''));

    return Scaffold(
      body: routesAsync.when(
        data: (routes) {
          if (routes.isEmpty) {
            return EmptyState(icon: Icons.route, message: tr('no_routes', ref));
          }
          return AppPullRefresh(
            onRefresh: () async {
              if (isAdmin) {
                ref.invalidate(routesProvider);
              } else {
                ref.invalidate(routesBySellerProvider(user?.id ?? ''));
              }
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: routes.length,
              itemBuilder: (_, i) => _RouteTile(route: routes[i]).listEntry(i),
            ),
          );
        },
        loading: () => const ShimmerLoading(),
        error: (e, _) => mappedErrorState(
          error: e,
          ref: ref,
          onRetry: () {
            if (isAdmin) {
              ref.invalidate(routesProvider);
            } else {
              ref.invalidate(routesBySellerProvider(user?.id ?? ''));
            }
          },
        ),
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
    final cs = theme.colorScheme;
    return Card(
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            '${route.routeNumber}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          route.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              [
                if (route.area != null) route.area,
                '${route.totalShops} ${tr('shops', ref)}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (route.assignedSellerName != null)
              Row(
                children: [
                  Icon(Icons.person, size: 12, color: cs.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      route.assignedSellerName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.primary),
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${route.totalShops}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        onTap: () => context.push('/routes/${route.id}'),
      ),
    );
  }
}
