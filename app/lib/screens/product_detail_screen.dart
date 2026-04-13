import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';

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
    final user = ref.watch(authUserProvider).value;
    final settings = ref.watch(settingsProvider).value;
    final cs = Theme.of(context).colorScheme;

    return productAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: mappedErrorState(
          error: e,
          ref: ref,
          onRetry: () => ref.invalidate(productDetailProvider(productId)),
        ),
      ),
      data: (product) {
        if (product == null) {
          return Scaffold(body: Center(child: Text(tr('not_found', ref))));
        }
        return Scaffold(
          body: Column(
            children: [
              // Action row: share + edit
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share),
                      tooltip: 'Share product info',
                      onPressed: () {
                        final variants = variantsAsync.value ?? [];
                        final ppc = settings?.pairsPerCarton ?? 12;
                        final totalStock = variants.fold<int>(
                          0,
                          (s, v) => s + v.quantityAvailable,
                        );
                        final buf = StringBuffer()
                          ..writeln(product.name)
                          ..writeln(
                            '${tr('category', ref)}: ${product.category}',
                          )
                          ..writeln(
                            '${tr('total_variants', ref)}: ${variants.length}',
                          )
                          ..writeln(
                            '${tr('stock_pairs', ref)}: ${_stockLabel(totalStock, ppc)}',
                          );
                        for (final v in variants) {
                          buf.writeln(
                            '  ${v.variantName}: ${_stockLabel(v.quantityAvailable, ppc)}',
                          );
                        }
                        SharePlus.instance.share(
                          ShareParams(text: buf.toString()),
                        );
                        HapticFeedback.lightImpact();
                      },
                    ),
                    if (user?.isAdmin == true)
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit product',
                        onPressed: () =>
                            context.push('/products/$productId/edit'),
                      ),
                  ],
                ),
              ),
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
                            errorBuilder: (_, _, _) => _productAvatar(cs),
                          ),
                        )
                      else
                        _productAvatar(cs),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
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
              // Stock summary strip
              variantsAsync.whenOrNull(
                    data: (variants) {
                      if (variants.isEmpty) return const SizedBox.shrink();
                      final ppc = settings?.pairsPerCarton ?? 12;
                      final totalStock = variants.fold<int>(
                        0,
                        (s, v) => s + v.quantityAvailable,
                      );
                      final inStock = variants
                          .where((v) => v.quantityAvailable > 0)
                          .length;
                      final outOfStock = variants.length - inStock;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _PStatChip(
                              icon: Icons.inventory,
                              label: tr('stock_pairs', ref),
                              value: _stockLabel(totalStock, ppc),
                              color: cs.primary,
                            ),
                            _PStatChip(
                              icon: Icons.check_circle,
                              label: 'In Stock',
                              value: '$inStock',
                              color: AppTheme.clearFg(cs),
                            ),
                            if (outOfStock > 0)
                              _PStatChip(
                                icon: Icons.cancel,
                                label: 'Out',
                                value: '$outOfStock',
                                color: AppTheme.debtFg(cs),
                              ),
                          ],
                        ),
                      );
                    },
                  ) ??
                  const SizedBox.shrink(),
              const SizedBox(height: 8),
              // Variants header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      tr('variants', ref),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    variantsAsync.whenOrNull(
                          data: (v) => Text(
                            '${v.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
                  error: (e, _) => mappedErrorState(
                    error: e,
                    ref: ref,
                    onRetry: () =>
                        ref.invalidate(productVariantsProvider(productId)),
                  ),
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
                        final cs = Theme.of(context).colorScheme;
                        return Card(
                          child: ListTile(
                            title: Text(
                              v.variantName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Quantity: ${AppFormatters.number(v.quantityAvailable)} pairs',
                            ),
                            trailing: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 130),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: v.quantityAvailable > 0
                                      ? AppTheme.clearBg(cs)
                                      : AppTheme.debtBg(cs),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _stockLabel(
                                    v.quantityAvailable,
                                    settings?.pairsPerCarton ?? 12,
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: v.quantityAvailable > 0
                                        ? AppTheme.clearFg(cs)
                                        : AppTheme.debtFg(cs),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            onTap: user?.isAdmin == true
                                ? () => context.push(
                                    '/products/$productId/variants/${v.id}/edit',
                                  )
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

class _PStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _PStatChip({
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
