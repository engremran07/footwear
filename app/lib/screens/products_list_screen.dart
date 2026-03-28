import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/empty_state.dart';

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
    final user = ref.watch(authUserProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('products', ref))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: tr('search_products', ref),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (products) {
                final filtered = _search.isEmpty
                    ? products
                    : products
                        .where((p) =>
                            p.name.toLowerCase().contains(_search) ||
                            p.category.toLowerCase().contains(_search))
                        .toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2,
                    message: tr('no_products', ref),
                  );
                }
                return ListView.builder(
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
                                  errorBuilder: (_, __, ___) =>
                                      _productIcon(cs),
                                ),
                              )
                            : _productIcon(cs),
                        title: Text(p.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(p.category),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => context.push('/products/${p.id}'),
                      ),
                    );
                  },
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
