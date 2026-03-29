import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';
import '../models/seller_inventory_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_transaction_provider.dart';
import '../providers/product_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_sheet.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _search = '';

  void _showAddStockDialog(ProductVariantModel variant, int ppc) {
    final cartonsC = TextEditingController(text: '0');
    final pairsC = TextEditingController(text: '0');
    int previewTotal = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Add Stock: ${variant.variantName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cartonsC,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Cartons',
                    helperText: '1 carton = $ppc pairs',
                  ),
                  onChanged: (_) => setDlgState(() {
                    final c = int.tryParse(cartonsC.text) ?? 0;
                    final p = int.tryParse(pairsC.text) ?? 0;
                    previewTotal = (c * ppc) + p;
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pairsC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Extra pairs',
                  ),
                  onChanged: (_) => setDlgState(() {
                    final c = int.tryParse(cartonsC.text) ?? 0;
                    final p = int.tryParse(pairsC.text) ?? 0;
                    previewTotal = (c * ppc) + p;
                  }),
                ),
                if (previewTotal > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Adding: ${AppFormatters.stock(previewTotal, ppc)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('cancel', ref)),
            ),
            ElevatedButton(
              onPressed: () async {
                final cartons = int.tryParse(cartonsC.text.trim()) ?? 0;
                final extraPairs = int.tryParse(pairsC.text.trim()) ?? 0;
                final totalPairs = (cartons * ppc) + extraPairs;

                if (totalPairs <= 0) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('Enter stock greater than zero')),
                    );
                  }
                  return;
                }

                try {
                  await ref
                      .read(productNotifierProvider.notifier)
                      .adjustStock(variant.id, totalPairs);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Added ${AppFormatters.stock(totalPairs, ppc)} to stock')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    final key = AppErrorMapper.key(e);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(tr(key, ref))));
                  }
                }
              },
              child: Text(tr('save', ref)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final currentUser = ref.watch(authUserProvider).valueOrNull;
    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('inventory', ref))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final isAdmin = currentUser.isAdmin;
    final warehouseVariants = ref.watch(allVariantsProvider);
    final sellerInventoryAsync = currentUser.isSeller
        ? ref.watch(sellerInventoryProvider(currentUser.id))
        : null;
    final ppc = settingsAsync.valueOrNull?.pairsPerCarton ?? 12;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('inventory', ref)),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: tr('transfer_history', ref),
              onPressed: () => _showTransferHistory(context),
            ),
          settingsAsync.when(
            data: (settings) => IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: () => ExportSheet.show(
                context,
                ref,
                title: tr('inventory_report', ref),
                headers: ['Variant Name', 'Quantity Available'],
                rows: isAdmin
                    ? warehouseVariants.valueOrNull
                            ?.map((v) => [
                                  v.variantName,
                                  AppFormatters.stock(v.quantityAvailable,
                                      settings.pairsPerCarton),
                                ])
                            .toList() ??
                        []
                    : sellerInventoryAsync?.valueOrNull
                            ?.map((v) => [
                                  v.variantName,
                                  AppFormatters.stock(v.quantityAvailable,
                                      settings.pairsPerCarton),
                                ])
                            .toList() ??
                        [],
                fileName: 'inventory_report',
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: isAdmin
          ? warehouseVariants.when(
              data: (data) {
                if (data.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2,
                    message: tr('no_variants', ref),
                  );
                }

                final filtered = data
                    .where((v) => v.variantName
                        .toLowerCase()
                        .contains(_search.toLowerCase()))
                    .toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.search,
                    message: tr('no_results', ref),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => ref.refresh(allVariantsProvider.future),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v),
                          decoration: InputDecoration(
                            hintText: tr('search_variants', ref),
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final variant = filtered[i];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                title: Text(
                                  variant.variantName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'Stock: ${AppFormatters.stock(variant.quantityAvailable, ppc)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Stock'),
                                  onPressed: () => settingsAsync.whenData(
                                    (settings) => _showAddStockDialog(
                                      variant,
                                      settings.pairsPerCarton,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            )
          : sellerInventoryAsync?.when(
                data: (data) {
                  if (data.isEmpty) {
                    return const EmptyState(
                      icon: Icons.inventory_2,
                      message: 'No seller inventory yet',
                    );
                  }

                  final filtered = data
                      .where((v) => v.variantName
                          .toLowerCase()
                          .contains(_search.toLowerCase()))
                      .toList();

                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.search,
                      message: tr('no_results', ref),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(
                        sellerInventoryProvider(currentUser.id).future),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'This tab shows your seller inventory only. Use Products to check warehouse stock before planning the next visit.',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            decoration: InputDecoration(
                              hintText: tr('search_variants', ref),
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final variant = filtered[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: ListTile(
                                  title: Text(variant.variantName),
                                  subtitle: Text(
                                    'Stock: ${AppFormatters.stock(variant.quantityAvailable, ppc)}',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.undo,
                                        color: Colors.orange),
                                    tooltip: 'Return to Warehouse',
                                    onPressed: () =>
                                        _showReturnToWarehouseDialog(
                                            variant, ppc),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error: $e')),
              ) ??
              const Center(child: CircularProgressIndicator()),
      floatingActionButton: isAdmin
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'transfer_seller',
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Transfer to Seller'),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _TransferToSellerDialog(
                      currentUserId: currentUser.id,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'add_inventory',
                  icon: const Icon(Icons.add),
                  label: const Text('Add Inventory'),
                  onPressed: _showAddInventoryDialog,
                ),
              ],
            )
          : FloatingActionButton.extended(
              heroTag: 'view_warehouse',
              icon: const Icon(Icons.warehouse),
              label: const Text('Warehouse'),
              onPressed: _showWarehouseStockSheet,
            ),
    );
  }

  void _showReturnToWarehouseDialog(SellerInventoryModel item, int ppc) {
    final qtyC = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Return: ${item.variantName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Available: ${AppFormatters.stock(item.quantityAvailable, ppc)}'),
              const SizedBox(height: 12),
              TextField(
                controller: qtyC,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Pairs to return to warehouse',
                  prefixIcon: Icon(Icons.undo),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('cancel', ref)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final qty = int.tryParse(qtyC.text.trim()) ?? 0;
                if (qty <= 0 || qty > item.quantityAvailable) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Invalid quantity')),
                  );
                  return;
                }
                final user = ref.read(authUserProvider).valueOrNull;
                try {
                  await ref
                      .read(sellerInventoryNotifierProvider.notifier)
                      .returnToWarehouse(
                        sellerInventoryDocId: item.id,
                        variantId: item.variantId,
                        qty: qty,
                        sellerId: item.sellerId,
                        sellerName: item.sellerName,
                        variantName: item.variantName,
                        productId: item.productId,
                        createdBy: user?.id ?? '',
                      );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Returned ${AppFormatters.stock(qty, ppc)} to warehouse')));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    final key = AppErrorMapper.key(e);
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text(tr(key, ref))));
                  }
                }
              },
              child: const Text('Return'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransferHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scrollController) {
          final ppc =
              ref.read(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;
          return Consumer(
            builder: (ctx, cRef, _) {
              final historyAsync = cRef.watch(allInventoryTransactionsProvider);
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(tr('transfer_history', ref),
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  const Divider(),
                  Expanded(
                    child: historyAsync.when(
                      data: (items) {
                        if (items.isEmpty) {
                          return Center(
                              child: Text(tr('no_transactions', ref)));
                        }
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final item = items[i];
                            final isReturn = item.type.contains('return');
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                isReturn ? Icons.undo : Icons.swap_horiz,
                                color: isReturn ? Colors.orange : Colors.blue,
                              ),
                              title: Text(item.variantName),
                              subtitle: Text(
                                '${item.sellerName} • ${AppFormatters.stock(item.quantity, ppc)}',
                              ),
                              trailing: Text(
                                AppFormatters.dateTime(item.createdAt),
                                style: Theme.of(ctx).textTheme.bodySmall,
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
          );
        },
      ),
    );
  }

  void _showWarehouseStockSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scrollController) {
          final settingsAsync = ref.read(settingsProvider);
          final ppc = settingsAsync.valueOrNull?.pairsPerCarton ?? 12;
          return Consumer(
            builder: (ctx, cRef, _) {
              final variantsAsync = cRef.watch(allVariantsProvider);
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Warehouse Stock',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  const Divider(),
                  Expanded(
                    child: variantsAsync.when(
                      data: (variants) => ListView.builder(
                        controller: scrollController,
                        itemCount: variants.length,
                        itemBuilder: (_, i) {
                          final v = variants[i];
                          return ListTile(
                            dense: true,
                            title: Text(v.variantName),
                            trailing: Text(
                              AppFormatters.stock(v.quantityAvailable, ppc),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('$e')),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showAddInventoryDialog() {
    showDialog(
      context: context,
      builder: (_) => const _AddInventoryDialog(),
    );
  }
}

class _AddInventoryDialog extends ConsumerStatefulWidget {
  const _AddInventoryDialog();

  @override
  ConsumerState<_AddInventoryDialog> createState() =>
      _AddInventoryDialogState();
}

class _AddInventoryDialogState extends ConsumerState<_AddInventoryDialog> {
  ProductModel? _selectedProduct;
  ProductVariantModel? _selectedVariant;
  final _cartonsC = TextEditingController();
  final _pairsC = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _cartonsC.dispose();
    _pairsC.dispose();
    super.dispose();
  }

  int get _ppc => ref.read(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;

  int get _total {
    final c = int.tryParse(_cartonsC.text) ?? 0;
    final p = int.tryParse(_pairsC.text) ?? 0;
    return (c * _ppc) + p;
  }

  Future<void> _submit() async {
    if (_selectedVariant == null) return;
    final total = _total;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter stock greater than zero')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(productNotifierProvider.notifier)
          .adjustStock(_selectedVariant!.id, total);
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Added ${AppFormatters.stock(total, _ppc)} to stock')),
        );
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(key, ref))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).valueOrNull ?? [];
    final variants = _selectedProduct != null
        ? ref
                .watch(productVariantsProvider(_selectedProduct!.id))
                .valueOrNull ??
            []
        : <ProductVariantModel>[];
    final ppc = _ppc;

    return AlertDialog(
      title: const Text('Add Inventory'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Product *'),
              child: DropdownButton<ProductModel>(
                value: _selectedProduct,
                hint: const Text('Select product'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: products
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (p) => setState(() {
                  _selectedProduct = p;
                  _selectedVariant = null;
                }),
              ),
            ),
            if (_selectedProduct != null) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Variant *',
                  helperText:
                      variants.isEmpty ? 'No variants for this product' : null,
                ),
                child: DropdownButton<ProductVariantModel>(
                  value: _selectedVariant,
                  hint: const Text('Select variant'),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: variants
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                                '${v.variantName} (${AppFormatters.stock(v.quantityAvailable, ppc)})'),
                          ))
                      .toList(),
                  onChanged: variants.isEmpty
                      ? null
                      : (v) => setState(() => _selectedVariant = v),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _cartonsC,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Cartons',
                helperText: '1 carton = $ppc pairs',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pairsC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Extra pairs (optional)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              'Adding: ${AppFormatters.stock(_total, ppc)}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel', ref)),
        ),
        ElevatedButton(
          onPressed: _saving || _selectedVariant == null ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr('save', ref)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transfer to Seller dialog
// ---------------------------------------------------------------------------

class _TransferToSellerDialog extends ConsumerStatefulWidget {
  final String currentUserId;
  const _TransferToSellerDialog({required this.currentUserId});

  @override
  ConsumerState<_TransferToSellerDialog> createState() =>
      _TransferToSellerDialogState();
}

class _TransferToSellerDialogState
    extends ConsumerState<_TransferToSellerDialog> {
  ProductModel? _selectedProduct;
  ProductVariantModel? _selectedVariant;
  UserModel? _selectedSeller;
  final _cartonsC = TextEditingController();
  final _pairsC = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _cartonsC.dispose();
    _pairsC.dispose();
    super.dispose();
  }

  int get _ppc => ref.read(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;

  int get _total {
    final c = int.tryParse(_cartonsC.text) ?? 0;
    final p = int.tryParse(_pairsC.text) ?? 0;
    return (c * _ppc) + p;
  }

  bool get _exceedsStock =>
      _selectedVariant != null && _total > _selectedVariant!.quantityAvailable;

  Future<void> _submit() async {
    if (_selectedVariant == null || _selectedSeller == null) return;
    final total = _total;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter quantity greater than zero')),
      );
      return;
    }
    if (total > _selectedVariant!.quantityAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough stock. Available: ${AppFormatters.stock(_selectedVariant!.quantityAvailable, _ppc)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(productNotifierProvider.notifier).transferToSeller(
            variantId: _selectedVariant!.id,
            variantName: _selectedVariant!.variantName,
            productId: _selectedVariant!.productId,
            sellerId: _selectedSeller!.id,
            sellerName: _selectedSeller!.displayName,
            quantity: total,
            adminId: widget.currentUserId,
          );
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Transferred ${AppFormatters.stock(total, _ppc)} to ${_selectedSeller!.displayName}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(key, ref))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).valueOrNull ?? [];
    final sellers = ref.watch(sellersProvider).valueOrNull ?? [];
    final variants = _selectedProduct != null
        ? ref
                .watch(productVariantsProvider(_selectedProduct!.id))
                .valueOrNull ??
            []
        : <ProductVariantModel>[];
    final ppc = _ppc;

    return AlertDialog(
      title: const Text('Transfer Inventory to Seller'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Seller dropdown
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Seller *',
                helperText: sellers.isEmpty ? 'No active sellers found' : null,
              ),
              child: DropdownButton<UserModel>(
                value: _selectedSeller,
                hint: const Text('Select seller'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: sellers
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.displayName),
                        ))
                    .toList(),
                onChanged: sellers.isEmpty
                    ? null
                    : (s) => setState(() => _selectedSeller = s),
              ),
            ),
            const SizedBox(height: 12),
            // Product dropdown
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Product *'),
              child: DropdownButton<ProductModel>(
                value: _selectedProduct,
                hint: const Text('Select product'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: products
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (p) => setState(() {
                  _selectedProduct = p;
                  _selectedVariant = null;
                }),
              ),
            ),
            if (_selectedProduct != null) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Variant *',
                  helperText:
                      variants.isEmpty ? 'No variants for this product' : null,
                ),
                child: DropdownButton<ProductVariantModel>(
                  value: _selectedVariant,
                  hint: const Text('Select variant'),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: variants
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              '${v.variantName}  •  ${AppFormatters.stock(v.quantityAvailable, ppc)} in stock',
                            ),
                          ))
                      .toList(),
                  onChanged: variants.isEmpty
                      ? null
                      : (v) => setState(() => _selectedVariant = v),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _cartonsC,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Cartons',
                helperText: '1 carton = $ppc pairs',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pairsC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Extra pairs (optional)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_total > 0) ...[
              Text(
                'Transferring: ${AppFormatters.stock(_total, ppc)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_exceedsStock)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Exceeds available stock (${AppFormatters.stock(_selectedVariant!.quantityAvailable, ppc)})',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel', ref)),
        ),
        ElevatedButton(
          onPressed: (_saving ||
                  _selectedVariant == null ||
                  _selectedSeller == null ||
                  _total <= 0 ||
                  _exceedsStock)
              ? null
              : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Transfer'),
        ),
      ],
    );
  }
}
