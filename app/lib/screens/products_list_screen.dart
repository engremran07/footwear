import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/shimmer_loading.dart';

class ProductsListScreen extends ConsumerStatefulWidget {
  const ProductsListScreen({super.key});
  @override
  ConsumerState<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends ConsumerState<ProductsListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final user = ref.watch(authUserProvider).value;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          AppSearchBar(
            hintText: tr('search_products', ref),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const ShimmerLoading(),
              error: (e, _) =>
                  Center(child: Text(tr(AppErrorMapper.key(e), ref))),
              data: (products) {
                final filtered = _search.isEmpty
                    ? products
                    : products
                          .where(
                            (p) =>
                                p.name.toLowerCase().contains(_search) ||
                                p.category.toLowerCase().contains(_search),
                          )
                          .toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2,
                    message: tr('no_products', ref),
                  );
                }
                return AppPullRefresh(
                  onRefresh: () async {
                    ref.invalidate(productsProvider);
                    await Future.delayed(const Duration(milliseconds: 300));
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return Card(
                        child: ListTile(
                          leading: p.imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    p.imageUrl!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => _productIcon(cs),
                                  ),
                                )
                              : _productIcon(cs),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(p.category),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () => context.push('/products/${p.id}'),
                        ),
                      ).listEntry(i);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: user?.isAdmin == true
          ? FloatingActionButton(
              onPressed: () => context.push('/products/new'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _productIcon(ColorScheme cs) => CircleAvatar(
    radius: 24,
    backgroundColor: cs.primaryContainer,
    child: Icon(Icons.inventory_2, color: cs.primary),
  );
}
