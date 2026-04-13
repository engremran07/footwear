import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/snack_helper.dart';
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
import '../widgets/app_search_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_sheet.dart';
import '../widgets/shimmer_loading.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _search = '';
  int _adminTab = 0; // 0 = warehouse, 1 = personal seller stock

  Widget _buildAsyncError(Object error, {Widget? fallback}) {
    if (AppErrorMapper.isPermissionOrAuthError(error)) {
      return fallback ??
          const EmptyState(icon: Icons.lock_outline, message: '');
    }
    return Center(child: Text(tr(AppErrorMapper.key(error), ref)));
  }

  void _showAddStockDialog(ProductVariantModel variant, int ppc) {
    final cartonsC = TextEditingController(text: '0');
    final pairsC = TextEditingController(text: '0');
    final pairsFn = FocusNode();
    int previewTotal = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
            tr(
              'inventory_add_stock_title',
              ref,
            ).replaceAll('%s', variant.variantName),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cartonsC,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => pairsFn.requestFocus(),
                  decoration: InputDecoration(
                    labelText: tr('lbl_cartons', ref),
                    helperText: tr(
                      'lbl_carton_helper',
                      ref,
                    ).replaceAll('%s', '$ppc'),
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
                  focusNode: pairsFn,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: tr('lbl_extra_pairs', ref),
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
                    tr(
                      'lbl_adding_stock',
                      ref,
                    ).replaceAll('%s', AppFormatters.stock(previewTotal, ppc)),
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
                      warningSnackBar(tr('msg_enter_stock_gt_zero', ref)),
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
                      successSnackBar(
                        tr('msg_added_stock', ref).replaceAll(
                          '%s',
                          AppFormatters.stock(totalPairs, ppc),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    final key = AppErrorMapper.key(e);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(errorSnackBar(tr(key, ref)));
                  }
                }
              },
              child: Text(tr('save', ref)),
            ),
          ],
        ),
      ),
    ).then((_) {
      cartonsC.dispose();
      pairsC.dispose();
      pairsFn.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final currentUser = ref.watch(authUserProvider).value;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isAdmin = currentUser.isAdmin;
    final warehouseVariants = ref.watch(allVariantsProvider);
    final sellerInventoryAsync = ref.watch(
      sellerInventoryProvider(currentUser.id),
    );
    final ppc = settingsAsync.value?.pairsPerCarton ?? 12;

    return Scaffold(
      body: Column(
        children: [
          // Action row: history (admin only) + export (all roles)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.history),
                    tooltip: tr('transfer_history', ref),
                    onPressed: () => _showTransferHistory(context),
                  ),
                settingsAsync.when(
                  data: (settings) => IconButton(
                    icon: const Icon(Icons.file_download),
                    tooltip: tr('inventory_export_tooltip', ref),
                    onPressed: () {
                      ExportSheet.show(
                        context,
                        ref,
                        title: tr('inventory_report', ref),
                        headers: [
                          tr('lbl_variant_name', ref),
                          tr('lbl_quantity_available', ref),
                        ],
                        rows: (isAdmin && _adminTab == 0)
                            ? warehouseVariants.value
                                      ?.map(
                                        (v) => [
                                          v.variantName,
                                          AppFormatters.stock(
                                            v.quantityAvailable,
                                            settings.pairsPerCarton,
                                          ),
                                        ],
                                      )
                                      .toList() ??
                                  []
                            : sellerInventoryAsync.value
                                      ?.map(
                                        (v) => [
                                          v.variantName,
                                          AppFormatters.stock(
                                            v.quantityAvailable,
                                            settings.pairsPerCarton,
                                          ),
                                        ],
                                      )
                                      .toList() ??
                                  [],
                        fileName: 'inventory_report',
                      );
                    },
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Expanded(
            child: isAdmin
                ? Column(
                    children: [
                      // Warehouse / Personal stock toggle
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: SegmentedButton<int>(
                          segments: [
                            ButtonSegment(
                              value: 0,
                              label: Text(tr('warehouse_stock', ref)),
                              icon: const Icon(Icons.warehouse),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text(tr('seller_stock', ref)),
                              icon: const Icon(Icons.person),
                            ),
                          ],
                          selected: {_adminTab},
                          onSelectionChanged: (v) =>
                              setState(() => _adminTab = v.first),
                        ),
                      ),
                      Expanded(
                        child: _adminTab == 0
                            ? _buildWarehouseList(
                                warehouseVariants,
                                ppc,
                                settingsAsync,
                              )
                            : _buildSellerList(
                                sellerInventoryAsync,
                                currentUser,
                                ppc,
                              ),
                      ),
                    ],
                  )
                : _buildSellerList(sellerInventoryAsync, currentUser, ppc),
          ),
        ],
      ),
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
                  label: Text(tr('inventory_transfer_to_seller', ref)),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) =>
                        _TransferToSellerDialog(currentUserId: currentUser.id),
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'add_inventory',
                  icon: const Icon(Icons.add),
                  label: Text(tr('inventory_add_inventory', ref)),
                  onPressed: _showAddInventoryDialog,
                ),
              ],
            )
          : FloatingActionButton.extended(
              heroTag: 'view_warehouse',
              icon: const Icon(Icons.warehouse),
              label: Text(tr('lbl_warehouse', ref)),
              onPressed: _showWarehouseStockSheet,
            ),
    );
  }

  Widget _buildWarehouseList(
    AsyncValue<List<ProductVariantModel>> warehouseVariants,
    int ppc,
    AsyncValue<dynamic> settingsAsync,
  ) {
    return warehouseVariants.when(
      data: (data) {
        if (data.isEmpty) {
          return EmptyState(
            icon: Icons.inventory_2,
            message: tr('no_variants', ref),
          );
        }
        final filtered = data
            .where(
              (v) =>
                  v.variantName.toLowerCase().contains(_search.toLowerCase()),
            )
            .toList();
        if (filtered.isEmpty) {
          return EmptyState(icon: Icons.search, message: tr('no_results', ref));
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(allVariantsProvider.future),
          child: Column(
            children: [
              AppSearchBar(
                hintText: tr('search_variants', ref),
                onChanged: (v) => setState(() => _search = v),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final variant = filtered[i];
                    final isLowStock =
                        variant.quantityAvailable > 0 &&
                        variant.quantityAvailable < ppc;
                    final isOutOfStock = variant.quantityAvailable <= 0;
                    final cs = Theme.of(ctx).colorScheme;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: isOutOfStock
                            ? Icon(Icons.cancel, color: cs.error, size: 20)
                            : isLowStock
                            ? Icon(
                                Icons.warning_amber,
                                color: AppTheme.warningFg(cs),
                                size: 20,
                              )
                            : null,
                        title: Text(
                          variant.variantName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          tr('lbl_stock_value', ref).replaceAll(
                            '%s',
                            AppFormatters.stock(variant.quantityAvailable, ppc),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isOutOfStock
                                ? cs.error
                                : isLowStock
                                ? AppTheme.warningFg(cs)
                                : null,
                            fontWeight: isOutOfStock || isLowStock
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                        trailing: ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text(tr('inventory_add_stock', ref)),
                          onPressed: () => _showAddStockDialog(variant, ppc),
                        ),
                      ),
                    ).listEntry(i);
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const ShimmerLoading(),
      error: (e, st) => _buildAsyncError(e),
    );
  }

  Widget _buildSellerList(
    AsyncValue<List<SellerInventoryModel>> sellerInventoryAsync,
    UserModel currentUser,
    int ppc,
  ) {
    return sellerInventoryAsync.when(
      data: (data) {
        if (data.isEmpty) {
          return EmptyState(
            icon: Icons.inventory_2,
            message: tr('no_variants', ref),
          );
        }
        final filtered = data
            .where(
              (v) =>
                  v.variantName.toLowerCase().contains(_search.toLowerCase()),
            )
            .toList();
        if (filtered.isEmpty) {
          return EmptyState(icon: Icons.search, message: tr('no_results', ref));
        }
        return RefreshIndicator(
          onRefresh: () =>
              ref.refresh(sellerInventoryProvider(currentUser.id).future),
          child: Column(
            children: [
              AppSearchBar(
                hintText: tr('search_variants', ref),
                onChanged: (v) => setState(() => _search = v),
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
                          tr('lbl_stock_value', ref).replaceAll(
                            '%s',
                            AppFormatters.stock(variant.quantityAvailable, ppc),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: currentUser.isAdmin
                            ? IconButton(
                                icon: Icon(
                                  Icons.undo,
                                  color: AppTheme.warningFg(
                                    Theme.of(ctx).colorScheme,
                                  ),
                                ),
                                tooltip: tr(
                                  'inventory_return_to_warehouse',
                                  ref,
                                ),
                                onPressed: () =>
                                    _showReturnToWarehouseDialog(variant, ppc),
                              )
                            : null,
                      ),
                    ).listEntry(i);
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const ShimmerLoading(),
      error: (e, st) => _buildAsyncError(e),
    );
  }

  void _showReturnToWarehouseDialog(SellerInventoryModel item, int ppc) {
    final qtyC = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            tr(
              'inventory_return_title',
              ref,
            ).replaceAll('%s', item.variantName),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('lbl_available_stock', ref).replaceAll(
                  '%s',
                  AppFormatters.stock(item.quantityAvailable, ppc),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyC,
                keyboardType: TextInputType.number,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: tr('lbl_pairs_to_return', ref),
                  prefixIcon: const Icon(Icons.undo),
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
                backgroundColor: AppTheme.warningBg(Theme.of(ctx).colorScheme),
                foregroundColor: AppTheme.warningFg(Theme.of(ctx).colorScheme),
              ),
              onPressed: () async {
                final qty = int.tryParse(qtyC.text.trim()) ?? 0;
                if (qty <= 0 || qty > item.quantityAvailable) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    warningSnackBar(tr('msg_invalid_quantity', ref)),
                  );
                  return;
                }
                final user = ref.read(authUserProvider).value;
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
                        createdBy: user!.id,
                      );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      successSnackBar(
                        tr(
                          'msg_returned_stock',
                          ref,
                        ).replaceAll('%s', AppFormatters.stock(qty, ppc)),
                      ),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    final key = AppErrorMapper.key(e);
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(errorSnackBar(tr(key, ref)));
                  }
                }
              },
              child: Text(tr('lbl_return', ref)),
            ),
          ],
        ),
      ),
    ).then((_) => qtyC.dispose());
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
          final ppc = ref.read(settingsProvider).value?.pairsPerCarton ?? 12;
          return Consumer(
            builder: (ctx, cRef, _) {
              final user = cRef.watch(authUserProvider).value;
              final historyAsync = user?.isAdmin == true
                  ? cRef.watch(allInventoryTransactionsProvider)
                  : cRef.watch(
                      sellerInventoryTransactionsProvider(user?.id ?? ''),
                    );
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      tr('transfer_history', ref),
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: historyAsync.when(
                      data: (items) {
                        if (items.isEmpty) {
                          return Center(
                            child: Text(tr('no_transactions', ref)),
                          );
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
                                color: isReturn
                                    ? AppTheme.warningFg(
                                        Theme.of(ctx).colorScheme,
                                      )
                                    : Theme.of(ctx).colorScheme.primary,
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
                      error: (e, _) => _buildAsyncError(
                        e,
                        fallback: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
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
          final ppc = settingsAsync.value?.pairsPerCarton ?? 12;
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
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      tr('inventory_warehouse_stock', ref),
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => _buildAsyncError(
                        e,
                        fallback: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
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
    showDialog(context: context, builder: (_) => const _AddInventoryDialog());
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
  final _pairsFn = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _cartonsC.dispose();
    _pairsC.dispose();
    _pairsFn.dispose();
    super.dispose();
  }

  int get _ppc => ref.read(settingsProvider).value?.pairsPerCarton ?? 12;

  int get _total {
    final c = int.tryParse(_cartonsC.text) ?? 0;
    final p = int.tryParse(_pairsC.text) ?? 0;
    return (c * _ppc) + p;
  }

  Future<void> _submit() async {
    if (_selectedVariant == null) return;
    final total = _total;
    if (total <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('msg_enter_stock_gt_zero', ref)));
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
          successSnackBar(
            tr(
              'msg_added_stock',
              ref,
            ).replaceAll('%s', AppFormatters.stock(total, _ppc)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).value ?? [];
    final variants = _selectedProduct != null
        ? ref.watch(productVariantsProvider(_selectedProduct!.id)).value ?? []
        : <ProductVariantModel>[];
    final ppc = _ppc;

    return AlertDialog(
      title: Text(tr('inventory_add_inventory', ref)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InputDecorator(
              decoration: InputDecoration(
                labelText: tr('lbl_product_required', ref),
              ),
              child: DropdownButton<ProductModel>(
                value: _selectedProduct,
                hint: Text(tr('hint_select_product', ref)),
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
                  labelText: tr('lbl_variant_required', ref),
                  helperText: variants.isEmpty
                      ? tr('msg_no_variants_for_product', ref)
                      : null,
                ),
                child: DropdownButton<ProductVariantModel>(
                  value: _selectedVariant,
                  hint: Text(tr('hint_select_variant', ref)),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: variants
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            '${v.variantName} (${AppFormatters.stock(v.quantityAvailable, ppc)})',
                          ),
                        ),
                      )
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
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _pairsFn.requestFocus(),
              decoration: InputDecoration(
                labelText: tr('lbl_cartons', ref),
                helperText: tr(
                  'lbl_carton_helper',
                  ref,
                ).replaceAll('%s', '$ppc'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pairsC,
              focusNode: _pairsFn,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: tr('lbl_extra_pairs_optional', ref),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'lbl_adding_stock',
                ref,
              ).replaceAll('%s', AppFormatters.stock(_total, ppc)),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
  final _pairsFn = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _cartonsC.dispose();
    _pairsC.dispose();
    _pairsFn.dispose();
    super.dispose();
  }

  int get _ppc => ref.read(settingsProvider).value?.pairsPerCarton ?? 12;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('msg_enter_qty_gt_zero', ref)));
      return;
    }
    if (total > _selectedVariant!.quantityAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        errorSnackBar(
          tr('msg_not_enough_stock', ref).replaceAll(
            '%s',
            AppFormatters.stock(_selectedVariant!.quantityAvailable, _ppc),
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(productNotifierProvider.notifier)
          .transferToSeller(
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
          successSnackBar(
            tr('msg_transferred_stock', ref)
                .replaceFirst('%s', AppFormatters.stock(total, _ppc))
                .replaceFirst('%s', _selectedSeller!.displayName),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).value ?? [];
    // Use allUsersProvider so admin can also select themselves as a recipient
    // (admin loads stock into their own vehicle, same as a seller).
    final sellers = ref.watch(allUsersProvider).value ?? [];
    final variants = _selectedProduct != null
        ? ref.watch(productVariantsProvider(_selectedProduct!.id)).value ?? []
        : <ProductVariantModel>[];
    final ppc = _ppc;

    return AlertDialog(
      title: Text(tr('inventory_transfer_title', ref)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Seller dropdown
            InputDecorator(
              decoration: InputDecoration(
                labelText: tr('lbl_seller_required', ref),
                helperText: sellers.isEmpty
                    ? tr('msg_no_active_sellers', ref)
                    : null,
              ),
              child: DropdownButton<UserModel>(
                value: _selectedSeller,
                hint: Text(tr('hint_select_seller', ref)),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: sellers
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.displayName),
                      ),
                    )
                    .toList(),
                onChanged: sellers.isEmpty
                    ? null
                    : (s) => setState(() => _selectedSeller = s),
              ),
            ),
            const SizedBox(height: 12),
            // Product dropdown
            InputDecorator(
              decoration: InputDecoration(
                labelText: tr('lbl_product_required', ref),
              ),
              child: DropdownButton<ProductModel>(
                value: _selectedProduct,
                hint: Text(tr('hint_select_product', ref)),
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
                  labelText: tr('lbl_variant_required', ref),
                  helperText: variants.isEmpty
                      ? tr('msg_no_variants_for_product', ref)
                      : null,
                ),
                child: DropdownButton<ProductVariantModel>(
                  value: _selectedVariant,
                  hint: Text(tr('hint_select_variant', ref)),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: variants
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            '${v.variantName}  •  ${AppFormatters.stock(v.quantityAvailable, ppc)} ${tr('lbl_in_stock', ref)}',
                          ),
                        ),
                      )
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
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _pairsFn.requestFocus(),
              decoration: InputDecoration(
                labelText: tr('lbl_cartons', ref),
                helperText: tr(
                  'lbl_carton_helper',
                  ref,
                ).replaceAll('%s', '$ppc'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pairsC,
              focusNode: _pairsFn,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: tr('lbl_extra_pairs_optional', ref),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_total > 0) ...[
              Text(
                tr(
                  'lbl_transferring',
                  ref,
                ).replaceAll('%s', AppFormatters.stock(_total, ppc)),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_exceedsStock)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr('msg_exceeds_stock', ref).replaceAll(
                      '%s',
                      AppFormatters.stock(
                        _selectedVariant!.quantityAvailable,
                        ppc,
                      ),
                    ),
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
          onPressed:
              (_saving ||
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
              : Text(tr('lbl_transfer', ref)),
        ),
      ],
    );
  }
}
