import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/product_provider.dart';
import '../models/product_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';

class ProductsListScreen extends ConsumerStatefulWidget {
  const ProductsListScreen({super.key});

  @override
  ConsumerState<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends ConsumerState<ProductsListScreen> {
  String _search = '';
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final products =
        _showAll ? ref.watch(allProductsProvider) : ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('products', ref)),
        actions: [
          IconButton(
            icon: Icon(_showAll ? Icons.toggle_on : Icons.toggle_off),
            tooltip: _showAll ? tr('showing_all', ref) : tr('only_active', ref),
            onPressed: () => setState(() => _showAll = !_showAll),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = products.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Products',
                fileName: 'products',
                headers: [
                  tr('sku', ref),
                  tr('name', ref),
                  tr('category', ref),
                  tr('cost_price', ref),
                  tr('sell_price', ref),
                  tr('stock_count', ref),
                  tr('active', ref)
                ],
                rows: data
                    .map((p) => [
                          p.sku,
                          p.name,
                          p.category,
                          p.costPriceDozenPkr,
                          p.sellPriceDozenSar,
                          p.stockCount,
                          p.active ? 'Yes' : 'No'
                        ])
                    .toList(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              hintText: tr('search_products', ref),
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: products.when(
              data: (list) {
                final filtered = list
                    .where((p) =>
                        _search.isEmpty ||
                        p.name.toLowerCase().contains(_search) ||
                        p.sku.toLowerCase().contains(_search))
                    .toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    message: tr('no_products_found', ref),
                    icon: Icons.inventory_2_outlined,
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _ProductTile(product: filtered[i]),
                );
              },
              loading: () => const ShimmerLoading(),
              error: (e, _) => ErrorState(message: e.toString()),
            ),
          ),
        ],
      ),
      floatingActionButton: RoleGuard(
        allowed: (u) => u.isManager,
        child: FloatingActionButton(
          onPressed: () => context.push('/products/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  final ProductModel product;
  const _ProductTile({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: product.imageUrl != null
          ? Hero(
              tag: 'product-img-${product.id}',
              child: CircleAvatar(
                  backgroundImage: NetworkImage(product.imageUrl!)),
            )
          : const CircleAvatar(child: Icon(Icons.inventory_2)),
      title: Text(product.name),
      subtitle: Text('${product.sku} · ${product.stockCount}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(AppFormatters.sar(product.sellPriceDozenSar),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
              '${tr('cost_short', ref)}: ${AppFormatters.pkr(product.costPriceDozenPkr)}',
              style: const TextStyle(fontSize: 11)),
        ],
      ),
      onTap: () => context.push('/products/${product.id}'),
    );
  }
}
