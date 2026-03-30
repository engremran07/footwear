import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../models/route_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../widgets/empty_state.dart';

class RoutesListScreen extends ConsumerStatefulWidget {
  const RoutesListScreen({super.key});

  @override
  ConsumerState<RoutesListScreen> createState() => _RoutesListScreenState();
}

class _RoutesListScreenState extends ConsumerState<RoutesListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final user = ref.watch(authUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;
    final routesAsync = isAdmin
        ? ref.watch(routesProvider)
        : ref.watch(routesBySellerProvider(user?.id ?? ''));

    return Scaffold(
      appBar: AppBar(title: Text(tr('routes', ref))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: tr('search', ref),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) =>
                  setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: routesAsync.when(
              data: (routes) {
                final filtered = _search.isEmpty
                    ? routes
                    : routes
                        .where((r) =>
                            r.name.toLowerCase().contains(_search) ||
                            (r.area?.toLowerCase().contains(_search) ??
                                false) ||
                            (r.assignedSellerName
                                    ?.toLowerCase()
                                    .contains(_search) ??
                                false) ||
                            r.routeNumber.toString().contains(_search))
                        .toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.route,
                    message: tr('no_routes', ref),
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _RouteTile(route: filtered[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
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
              Text(
                route.assignedSellerName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/routes/${route.id}'),
      ),
    );
  }
}
