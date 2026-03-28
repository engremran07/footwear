import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/formatters.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/empty_state.dart';

String _stockLabel(int qty, int ppc) {
  if (qty <= 0) return '0 prs';
  final cartons = qty ~/ ppc;
  final rem1 = qty % ppc;
  final dozens = rem1 ~/ 12;
  final pairs = rem1 % 12;
  final parts = <String>[];
  if (cartons > 0) parts.add('$cartons ctn');
  if (dozens > 0) parts.add('$dozens dz');
  if (pairs > 0 || parts.isEmpty) parts.add('$pairs prs');
  return parts.join(' ');
}

class ProductDetailScreen extends ConsumerWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailProvider(productId));
    final variantsAsync = ref.watch(productVariantsProvider(productId));
    final user = ref.watch(authUserProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;

    return productAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('${tr('error', ref)}: $e'))),
      data: (product) {
        if (product == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr('not_found', ref))),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(product.name),
            actions: [
              if (user?.isAdmin == true)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => context.push('/products/$productId/edit'),
                ),
            ],
          ),
          body: Column(
            children: [
              // Product info card
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (product.imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            product.imageUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _productAvatar(cs),
                          ),
                        )
                      else
                        _productAvatar(cs),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Chip(
                              label: Text(product.category),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Variants header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(tr('variants', ref),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    variantsAsync.whenOrNull(
                          data: (v) => Text('${v.length}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ) ??
                        const SizedBox.shrink(),
                  ],
                ),
              ),
              const Divider(),
              // Variants list
              Expanded(
                child: variantsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (variants) {
                    if (variants.isEmpty) {
                      return EmptyState(
                        icon: Icons.style,
                        message: tr('no_variants', ref),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: variants.length,
                      itemBuilder: (_, i) {
                        final v = variants[i];
                        return Card(
                          child: ListTile(
                            title: Text(v.variantName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                'Quantity: ${AppFormatters.number(v.quantityAvailable)} pairs'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: v.quantityAvailable > 0
                                    ? Colors.green.withAlpha(20)
                                    : Colors.red.withAlpha(20),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _stockLabel(
                                    v.quantityAvailable, settings?.pairsPerCarton ?? 12),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: v.quantityAvailable > 0
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            onTap: user?.isAdmin == true
                                ? () => context.push(
                                    '/products/$productId/variants/${v.id}/edit')
                                : null,
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
                  onPressed: () =>
                      context.push('/products/$productId/variants/new'),
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }

  Widget _productAvatar(ColorScheme cs) => CircleAvatar(
        radius: 40,
        backgroundColor: cs.primaryContainer,
        child: Icon(Icons.inventory_2, size: 32, color: cs.primary),
      );
}
