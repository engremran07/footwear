import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/product_provider.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../widgets/confirm_dialog.dart';
import '../core/utils/formatters.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_message.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productDetailProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('product', ref)),
        actions: [
          RoleGuard(
            allowed: (u) => u.isManager,
            child: product.when(
              data: (p) => p != null
                  ? Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () =>
                              context.push('/products/$productId/edit'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.block),
                          tooltip: tr('deactivate', ref),
                          onPressed: () async {
                            final ok = await ConfirmDialog.show(
                              context,
                              title: tr('deactivate', ref),
                              message: tr('deactivate_product_msg', ref),
                              confirmLabel: tr('deactivate', ref),
                              cancelLabel: tr('cancel', ref),
                              confirmColor: Theme.of(context).colorScheme.error,
                            );
                            if (!ok) return;
                            await ref
                                .read(productNotifierProvider.notifier)
                                .deactivate(productId);
                            if (context.mounted) {
                              AppMessage.success(
                                  context, ref, 'success_deactivated');
                              context.pop();
                            }
                          },
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      body: product.when(
        data: (p) {
          if (p == null) {
            return Center(child: Text(tr('not_found', ref)));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.imageUrl != null)
                  Hero(
                    tag: 'product-img-${p.id}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: p.imageUrl!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        memCacheWidth: 800,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: Text(p.name,
                            style: Theme.of(context).textTheme.headlineSmall)),
                    StatusChip(status: p.active ? 'active' : 'inactive'),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${tr('sku', ref)}: ${p.sku}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                const Divider(),
                _InfoRow(label: tr('category', ref), value: p.category),
                _InfoRow(
                    label: tr('sell_price', ref),
                    value: AppFormatters.sar(p.sellPriceDozenSar)),
                _InfoRow(
                    label: tr('cost_price', ref),
                    value: AppFormatters.pkr(p.costPriceDozenPkr)),
                _InfoRow(
                    label: tr('stock_count', ref),
                    value: p.stockCount.toString()),
                _InfoRow(label: tr('sizes', ref), value: p.sizes.join(', ')),
                _InfoRow(
                    label: tr('created_date', ref),
                    value: AppFormatters.date(p.createdAt)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${tr('error', ref)}: $e')),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
              child:
                  Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
