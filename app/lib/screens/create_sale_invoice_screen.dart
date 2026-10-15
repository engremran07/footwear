import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/action_guard.dart';
import '../core/utils/app_sanitizer.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/input_formatters.dart';
import '../core/utils/snack_helper.dart';
import '../models/invoice_model.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';
import '../models/seller_inventory_model.dart';
import '../models/settings_model.dart';
import '../models/shop_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/network_provider.dart';
import '../providers/product_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/route_provider.dart';
import '../providers/shop_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/error_state.dart';

// =============================================================================
enum InvoiceEntryMode { stock, nonStock, cashReceipt }

// CreateSaleInvoiceScreen — used ONLY for sales where stock is being deducted.
//
// PREREQUISITES:
//   - Seller must have items in seller_inventory (loaded via sellerInventoryProvider)
//   - At least 1 item must be selected with qty > 0
//   - Sale amount > 0
//
// ON SUBMIT → InvoiceNotifier.createSaleInvoice():
//   - Atomically creates: invoice doc + cash_out transaction
//   - If amountReceived > 0: also creates a cash_in transaction
//   - Deducts seller_inventory quantities for selected items
//   - Updates shop.balance (balance += total - amountReceived)
//
// DO NOT use this screen for collecting cash from old debt — that is done via
// ShopDetailScreen quick cash_in (no invoice, no stock movement).
// =============================================================================
class CreateSaleInvoiceScreen extends ConsumerStatefulWidget {
  final String? preselectedShopId;
  const CreateSaleInvoiceScreen({super.key, this.preselectedShopId});

  @override
  ConsumerState<CreateSaleInvoiceScreen> createState() =>
      _CreateSaleInvoiceScreenState();
}

class _CreateSaleInvoiceScreenState
    extends ConsumerState<CreateSaleInvoiceScreen> {
  ShopModel? _selectedShop;
  bool _shopAutoSelected = false;
  final _saleAmountC = TextEditingController();
  final _amountReceivedC = TextEditingController();
  final _receiptAmountC = TextEditingController();
  final _receiptReferenceC = TextEditingController();
  final _discountC = TextEditingController();
  final _notesC = TextEditingController();
  final _discountFn = FocusNode();
  final _amountReceivedFn = FocusNode();
  final _notesFn = FocusNode();
  // _selectedQtys stores DOZENS per inventory item (primary UI unit)
  final Map<String, int> _selectedQtys = {};
  final Map<String, int> _nonStockQtys = {};
  final Map<String, TextEditingController> _nonStockUnitPriceCs = {};
  // _selectedExtraPairs stores extra pairs (0–11) per inventory item beyond full dozens
  final Map<String, int> _selectedExtraPairs = {};
  bool _submitting = false;
  InvoiceEntryMode _entryMode = InvoiceEntryMode.nonStock;
  String? _selectedProductId;
  String _paymentMethod = 'cash';
  bool _isDirty = false;
  String? _pendingInvoiceIdempotencyKey;
  String? _pendingInvoiceFingerprint;
  final ActionGuard _submitGuard = ActionGuard();

  /// Builds invoice line items.
  /// [ppc] = pairs per dozen (always 12 from settings).
  /// qty in each item = dozens (user-visible unit); extra_pairs records optional overage.
  /// Prices are distributed proportionally by pair count so that
  /// subtotal is always exactly preserved in the last item.
  List<Map<String, dynamic>> _buildInvoiceItems(
    List<SellerInventoryModel> inventoryList,
    double subtotal,
    int ppc,
  ) {
    final dozenEntries = _selectedQtys.entries
        .where((entry) => entry.value > 0)
        .toList();
    if (dozenEntries.isEmpty || subtotal <= 0) return const [];

    final inventoryMap = {for (final item in inventoryList) item.id: item};
    // Distribute price proportionally by total pairs (dozens * ppc + extra)
    final totalPairs = dozenEntries.fold<int>(
      0,
      (sum, entry) =>
          sum + entry.value * ppc + (_selectedExtraPairs[entry.key] ?? 0),
    );
    if (totalPairs <= 0) return const [];

    final pricePerPair = subtotal / totalPairs;
    final items = <Map<String, dynamic>>[];
    double allocatedSubtotal = 0;

    for (var index = 0; index < dozenEntries.length; index++) {
      final entry = dozenEntries[index];
      final inventory = inventoryMap[entry.key];
      if (inventory == null) continue;

      final dozens = entry.value;
      final extraPairs = _selectedExtraPairs[entry.key] ?? 0;
      final linePairs = dozens * ppc + extraPairs;
      final isLast = index == dozenEntries.length - 1;
      final lineSubtotal = isLast
          ? subtotal - allocatedSubtotal
          : pricePerPair * linePairs;
      allocatedSubtotal += lineSubtotal;

      items.add({
        'variant_id': inventory.variantId,
        'sku': '',
        'product_name': inventory.variantName,
        'size': '',
        'color': '',
        'qty': dozens, // invoice line qty = dozens (selling unit)
        'extra_pairs': extraPairs,
        'unit_price': dozens > 0
            ? (lineSubtotal / dozens)
            : 0.0, // price per dozen
        'subtotal': lineSubtotal,
      });
    }

    return items;
  }

  List<Map<String, dynamic>> _buildNonStockInvoiceItems(
    List<ProductModel> products,
    List<ProductVariantModel> variants,
  ) {
    final productsById = {for (final product in products) product.id: product};
    return variants
        .where((variant) => (_nonStockQtys[variant.id] ?? 0) > 0)
        .map((variant) {
          final quantity = _nonStockQtys[variant.id] ?? 0;
          final unitPrice =
              AppFormatters.parseAmountText(
                _nonStockUnitPriceCs[variant.id]?.text ?? '',
              ) ??
              0;
          final productName =
              productsById[variant.productId]?.name.trim() ?? '';
          final description = [
            productName,
            variant.variantName.trim(),
          ].where((value) => value.isNotEmpty).join(' · ');
          return <String, dynamic>{
            'variant_id': variant.id,
            'sku': '',
            'product_name': description,
            'size': '',
            'color': '',
            'qty': quantity,
            'unit_price': unitPrice,
            'subtotal': quantity * unitPrice,
          };
        })
        .toList();
  }

  @override
  void dispose() {
    _saleAmountC.dispose();
    _amountReceivedC.dispose();
    _receiptAmountC.dispose();
    _receiptReferenceC.dispose();
    _discountC.dispose();
    _notesC.dispose();
    _discountFn.dispose();
    _amountReceivedFn.dispose();
    _notesFn.dispose();
    for (final controller in _nonStockUnitPriceCs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _saleAmount =>
      AppFormatters.parseAmountText(_saleAmountC.text) ?? 0;

  double get _discountAmount =>
      AppFormatters.parseAmountText(_discountC.text) ?? 0;

  double get _amountReceived =>
      AppFormatters.parseAmountText(_amountReceivedC.text) ?? 0;

  double get _previousBalance => _selectedShop?.balance ?? 0;

  String _currentInvoiceFingerprint(
    Map<String, int> deductions,
    List<Map<String, dynamic>> items,
  ) {
    final entries = deductions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final deductionSignature = entries
        .map((e) => '${e.key}:${e.value}')
        .join('|');
    final itemSignature = items.map((item) {
      final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
      return '${item['variant_id'] ?? ''}:${item['qty'] ?? 0}:${unitPrice.toStringAsFixed(2)}';
    }).toList()..sort();
    return [
      _entryMode.name,
      _selectedShop?.id ?? '',
      _saleAmount.toStringAsFixed(2),
      _discountAmount.toStringAsFixed(2),
      _amountReceived.toStringAsFixed(2),
      AppSanitizer.text(_notesC.text, maxLength: 300),
      _receiptAmountC.text,
      _paymentMethod,
      _receiptReferenceC.text,
      deductionSignature,
      itemSignature.join('|'),
    ].join('::');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final routeIds = user.assignedRouteIds;
    final shopsAsync = user.isAdmin
        ? ref.watch(shopsProvider)
        : (routeIds.isNotEmpty
              ? ref.watch(sellerAllShopsProvider)
              : const AsyncData<List<ShopModel>>([]));
    // Both admin and seller use their own seller_inventory (vehicle stock).
    // Admin loads stock from warehouse to their own seller_inventory via the
    // Inventory screen transfer, then selects items here to create an invoice.
    final inventoryAsync = ref.watch(sellerInventoryProvider(user.id));
    final settingsAsync = ref.watch(settingsProvider);
    final isCatalogMode = _entryMode == InvoiceEntryMode.nonStock;
    final productsAsync = isCatalogMode
        ? ref.watch(productsProvider)
        : const AsyncData<List<ProductModel>>([]);
    final variantsAsync = isCatalogMode
        ? ref.watch(allVariantsProvider)
        : const AsyncData<List<ProductVariantModel>>([]);

    // Auto-select shop if preselected.
    if (widget.preselectedShopId != null && !_shopAutoSelected) {
      shopsAsync.whenData((shops) {
        final match = shops.where((s) => s.id == widget.preselectedShopId);
        if (match.isNotEmpty && _selectedShop == null) {
          _shopAutoSelected = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedShop = match.first);
          });
        }
      });
    }

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await ConfirmDialog.show(
          context,
          title: tr('unsaved_changes', ref),
          message: tr('discard_changes_message', ref),
        );
        if (leave == true && context.mounted) context.pop();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          body: settingsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => mappedErrorState(
              error: error,
              ref: ref,
              onRetry: () => ref.invalidate(settingsProvider),
            ),
            data: (settings) {
              if (!settings.allowNonStockInvoices &&
                  _entryMode == InvoiceEntryMode.nonStock) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _entryMode == InvoiceEntryMode.nonStock) {
                    setState(() => _entryMode = InvoiceEntryMode.stock);
                  }
                });
                return const Center(child: CircularProgressIndicator());
              }
              if (_entryMode == InvoiceEntryMode.stock) {
                return inventoryAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => mappedErrorState(
                    error: error,
                    ref: ref,
                    onRetry: () =>
                        ref.invalidate(sellerInventoryProvider(user.id)),
                  ),
                  data: (inventory) => _buildBody(
                    context,
                    user,
                    shopsAsync,
                    settings,
                    inventory
                        .where((item) => item.quantityAvailable > 0)
                        .toList(),
                    const AsyncData<List<ProductModel>>([]),
                    const AsyncData<List<ProductVariantModel>>([]),
                  ),
                );
              }
              return _buildBody(
                context,
                user,
                shopsAsync,
                settings,
                const <SellerInventoryModel>[],
                productsAsync,
                variantsAsync,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    UserModel user,
    AsyncValue<List<ShopModel>> shopsAsync,
    SettingsModel settings,
    List<SellerInventoryModel> inventory,
    AsyncValue<List<ProductModel>> productsAsync,
    AsyncValue<List<ProductVariantModel>> variantsAsync,
  ) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final ppc = settings.pairsPerCarton;
    final products = productsAsync.value ?? const <ProductModel>[];
    final selectedVariants = _selectedProductId == null
        ? const <ProductVariantModel>[]
        : (variantsAsync.value ?? const <ProductVariantModel>[])
              .where(
                (variant) =>
                    variant.productId == _selectedProductId && variant.active,
              )
              .toList();
    final nonStockItems = _buildNonStockInvoiceItems(
      products,
      selectedVariants,
    );
    final nonStockSubtotal = nonStockItems.fold<double>(
      0,
      (sum, item) => sum + (item['subtotal'] as num).toDouble(),
    );
    final displayedSubtotal = switch (_entryMode) {
      InvoiceEntryMode.stock => _saleAmount,
      InvoiceEntryMode.nonStock => nonStockSubtotal,
      InvoiceEntryMode.cashReceipt =>
        AppFormatters.parseAmountText(_receiptAmountC.text) ?? 0,
    };
    final displayedDiscount = _entryMode == InvoiceEntryMode.cashReceipt
        ? 0.0
        : _discountAmount;
    final displayedTotal = (displayedSubtotal - displayedDiscount).clamp(
      0.0,
      double.infinity,
    );
    // Resolve currency from the selected shop's route. Defaults to SAR.
    final routeIdForCurrency = _selectedShop != null
        ? (_selectedShop!.routeId.isNotEmpty
              ? _selectedShop!.routeId
              : (user.assignedRouteIds.firstOrNull ?? ''))
        : '';
    final currency = ref.watch(routeCurrencyProvider(routeIdForCurrency));

    // Calculate totals from selected items (_selectedQtys = dozens, quantity_available = pairs)
    final selectedEntries = _selectedQtys.entries
        .where((e) => e.value > 0)
        .toList();
    final totalDozens = selectedEntries.fold<int>(0, (acc, e) => acc + e.value);
    final totalExtraPairs = selectedEntries.fold<int>(
      0,
      (acc, e) => acc + (_selectedExtraPairs[e.key] ?? 0),
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('invoice_mode', ref),
                  style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SegmentedButton<InvoiceEntryMode>(
                  segments: [
                    ButtonSegment(
                      value: InvoiceEntryMode.stock,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(tr('invoice_stock_mode', ref)),
                    ),
                    if (settings.allowNonStockInvoices)
                      ButtonSegment(
                        value: InvoiceEntryMode.nonStock,
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: Text(tr('invoice_non_stock_mode', ref)),
                      ),
                    ButtonSegment(
                      value: InvoiceEntryMode.cashReceipt,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(tr('cash_receipt', ref)),
                    ),
                  ],
                  selected: {_entryMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setState(() {
                      _entryMode = selection.first;
                      _isDirty = true;
                    });
                  },
                ),
                const SizedBox(height: 20),
                // ── Shop selector ──
                Text(
                  tr('select_shop', ref),
                  style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                shopsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => mappedErrorState(
                    error: e,
                    ref: ref,
                    onRetry: () {
                      if (user.isAdmin) {
                        ref.invalidate(shopsProvider);
                      } else if (user.assignedRouteIds.isNotEmpty) {
                        ref.invalidate(sellerAllShopsProvider);
                      }
                    },
                  ),
                  data: (shops) {
                    if (shops.isEmpty) {
                      return Text(tr('no_data', ref));
                    }
                    final matchedShop = _selectedShop == null
                        ? null
                        : shops
                              .where((s) => s.id == _selectedShop!.id)
                              .firstOrNull;
                    return GestureDetector(
                      onTap: () => _pickShop(context, shops),
                      child: InputDecorator(
                        isEmpty: matchedShop == null,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.store),
                          hintText: tr('select_shop', ref),
                          isDense: true,
                          suffixIcon: matchedShop != null
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  tooltip: tr('clear', ref),
                                  onPressed: () => setState(() {
                                    _selectedShop = null;
                                    _isDirty = true;
                                  }),
                                )
                              : const Icon(Icons.arrow_drop_down),
                        ),
                        child: matchedShop != null
                            ? Text(
                                matchedShop.name,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              )
                            : const SizedBox.shrink(),
                      ),
                    );
                  },
                ),
                if (_selectedShop != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${tr('previous_balance', ref)}: ${AppFormatters.currency(_previousBalance, currency)}',
                    style: ts.bodySmall?.copyWith(
                      color: _previousBalance > 0
                          ? AppBrand.errorColor
                          : AppBrand.successColor,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Items ──
                if (_entryMode == InvoiceEntryMode.stock) ...[
                  Text(
                    tr('select_items', ref),
                    style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (inventory.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          tr('no_inventory_items', ref),
                          style: ts.bodyMedium,
                        ),
                      ),
                    )
                  else
                    ...inventory.map((item) {
                      final maxDozens = item.quantityAvailable ~/ ppc;
                      final dozens = _selectedQtys[item.id] ?? 0;
                      final extraPairs = _selectedExtraPairs[item.id] ?? 0;
                      final maxExtraPairs =
                          (item.quantityAvailable - dozens * ppc).clamp(
                            0,
                            ppc - 1,
                          );
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.variantName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${tr("available", ref)}: ${AppFormatters.stock(item.quantityAvailable, ppc)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              // ── Dozens stepper ──
                              Row(
                                children: [
                                  Text(
                                    tr('lbl_cartons', ref),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 22,
                                    ),
                                    tooltip: tr('tooltip_decrease_qty', ref),
                                    onPressed: dozens <= 0
                                        ? null
                                        : () => setState(() {
                                            _selectedQtys[item.id] = dozens - 1;
                                            _isDirty = true;
                                            if (dozens - 1 == 0) {
                                              _selectedExtraPairs.remove(
                                                item.id,
                                              );
                                            }
                                          }),
                                  ),
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '$dozens',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 22,
                                    ),
                                    tooltip: tr('tooltip_increase_qty', ref),
                                    onPressed: dozens >= maxDozens
                                        ? null
                                        : () => setState(() {
                                            _selectedQtys[item.id] = dozens + 1;
                                            _isDirty = true;
                                          }),
                                  ),
                                ],
                              ),
                              // ── Extra pairs stepper (optional, shown when dozens > 0) ──
                              if (dozens > 0)
                                Row(
                                  children: [
                                    Text(
                                      tr('lbl_extra_pairs', ref),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 20,
                                      ),
                                      tooltip: tr('tooltip_decrease_qty', ref),
                                      onPressed: extraPairs <= 0
                                          ? null
                                          : () => setState(() {
                                              _selectedExtraPairs[item.id] =
                                                  extraPairs - 1;
                                              _isDirty = true;
                                            }),
                                    ),
                                    SizedBox(
                                      width: 32,
                                      child: Text(
                                        '$extraPairs',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        size: 20,
                                      ),
                                      tooltip: tr('tooltip_increase_qty', ref),
                                      // max extra pairs = ppc - 1 (a full dozen would be a new dozen)
                                      onPressed: extraPairs >= maxExtraPairs
                                          ? null
                                          : () => setState(() {
                                              _selectedExtraPairs[item.id] =
                                                  extraPairs + 1;
                                              _isDirty = true;
                                            }),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
                if (_entryMode == InvoiceEntryMode.nonStock) ...[
                  Text(
                    tr('invoice_catalog_items', ref),
                    style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  productsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, _) => mappedErrorState(
                      error: error,
                      ref: ref,
                      onRetry: () => ref.invalidate(productsProvider),
                    ),
                    data: (catalog) {
                      if (catalog.isEmpty) {
                        return Text(tr('no_products_available', ref));
                      }
                      final validProductIds = catalog
                          .map((product) => product.id)
                          .toSet();
                      final selectedProductId =
                          validProductIds.contains(_selectedProductId)
                          ? _selectedProductId
                          : null;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: selectedProductId,
                            decoration: InputDecoration(
                              labelText: tr('select_product', ref),
                              prefixIcon: const Icon(Icons.category_outlined),
                            ),
                            items: catalog
                                .map(
                                  (product) => DropdownMenuItem(
                                    value: product.id,
                                    child: Text(
                                      product.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (productId) {
                              for (final controller
                                  in _nonStockUnitPriceCs.values) {
                                controller.dispose();
                              }
                              setState(() {
                                _selectedProductId = productId;
                                _nonStockQtys.clear();
                                _nonStockUnitPriceCs.clear();
                                _isDirty = true;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          if (_selectedProductId != null)
                            variantsAsync.when(
                              loading: () => const LinearProgressIndicator(),
                              error: (error, _) => mappedErrorState(
                                error: error,
                                ref: ref,
                                onRetry: () =>
                                    ref.invalidate(allVariantsProvider),
                              ),
                              data: (allVariants) {
                                final variants = allVariants
                                    .where(
                                      (variant) =>
                                          variant.productId ==
                                              _selectedProductId &&
                                          variant.active,
                                    )
                                    .toList();
                                if (variants.isEmpty) {
                                  return Text(tr('no_variants_available', ref));
                                }
                                return Column(
                                  children: variants.map((variant) {
                                    final quantity =
                                        _nonStockQtys[variant.id] ?? 0;
                                    final priceController = _nonStockUnitPriceCs
                                        .putIfAbsent(
                                          variant.id,
                                          TextEditingController.new,
                                        );
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              variant.variantName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Text(tr('qty', ref)),
                                                const Spacer(),
                                                IconButton(
                                                  tooltip: tr(
                                                    'tooltip_decrease_qty',
                                                    ref,
                                                  ),
                                                  onPressed: quantity <= 0
                                                      ? null
                                                      : () => setState(() {
                                                          _nonStockQtys[variant
                                                                  .id] =
                                                              quantity - 1;
                                                          _isDirty = true;
                                                        }),
                                                  icon: const Icon(
                                                    Icons.remove_circle_outline,
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 32,
                                                  child: Text(
                                                    '$quantity',
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: tr(
                                                    'tooltip_increase_qty',
                                                    ref,
                                                  ),
                                                  onPressed: () => setState(() {
                                                    _nonStockQtys[variant.id] =
                                                        quantity + 1;
                                                    _isDirty = true;
                                                  }),
                                                  icon: const Icon(
                                                    Icons.add_circle_outline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (quantity > 0)
                                              TextField(
                                                controller: priceController,
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                inputFormatters: [
                                                  AppInputFormatters
                                                      .amountFormatter,
                                                ],
                                                decoration: InputDecoration(
                                                  labelText: tr(
                                                    'unit_price',
                                                    ref,
                                                  ),
                                                  prefixIcon: const Icon(
                                                    Icons.currency_exchange,
                                                  ),
                                                ),
                                                onChanged: (_) => setState(() {
                                                  _isDirty = true;
                                                }),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                  if (nonStockItems.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        '${tr('subtotal', ref)}: ${AppFormatters.currency(nonStockSubtotal, currency)}',
                        style: ts.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
                if (_entryMode == InvoiceEntryMode.cashReceipt) ...[
                  Text(
                    tr('cash_receipt_details', ref),
                    style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _receiptAmountC,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [AppInputFormatters.amountFormatter],
                    decoration: InputDecoration(
                      labelText: tr('amount_received', ref),
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                    onChanged: (_) => setState(() => _isDirty = true),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: InputDecoration(
                      labelText: tr('payment_method', ref),
                      prefixIcon: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    items: [
                      for (final method in ['cash', 'bank_transfer', 'cheque'])
                        DropdownMenuItem(
                          value: method,
                          child: Text(tr('payment_method_$method', ref)),
                        ),
                    ],
                    onChanged: (method) {
                      if (method != null) {
                        setState(() {
                          _paymentMethod = method;
                          _isDirty = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _receiptReferenceC,
                    decoration: InputDecoration(
                      labelText: tr('payment_reference', ref),
                      prefixIcon: const Icon(Icons.tag),
                    ),
                    onChanged: (_) => setState(() => _isDirty = true),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Sale Amount ──
                if (_entryMode == InvoiceEntryMode.stock) ...[
                  TextField(
                    controller: _saleAmountC,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr('sale_amount', ref),
                      prefixIcon: const Icon(Icons.currency_exchange),
                      hintText: '0.00',
                    ),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _discountFn.requestFocus(),
                    inputFormatters: [AppInputFormatters.amountFormatter],
                    onChanged: (_) {
                      if (!_isDirty) _isDirty = true;
                      setState(() {});
                    },
                  ),
                ],

                const SizedBox(height: 12),

                // ── Discount ──
                if (_entryMode != InvoiceEntryMode.cashReceipt)
                  TextField(
                    controller: _discountC,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr('discount_amount', ref),
                      prefixIcon: const Icon(Icons.money_off),
                    ),
                    focusNode: _discountFn,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _amountReceivedFn.requestFocus(),
                    inputFormatters: [AppInputFormatters.amountFormatter],
                    onChanged: (_) {
                      if (!_isDirty) _isDirty = true;
                      setState(() {});
                    },
                  ),

                const SizedBox(height: 12),

                // ── Amount Received ──
                if (_entryMode != InvoiceEntryMode.cashReceipt)
                  TextField(
                    controller: _amountReceivedC,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr('amount_received', ref),
                      prefixIcon: const Icon(Icons.payments),
                      hintText: '0.00',
                    ),
                    focusNode: _amountReceivedFn,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _notesFn.requestFocus(),
                    inputFormatters: [AppInputFormatters.amountFormatter],
                    onChanged: (_) {
                      if (!_isDirty) _isDirty = true;
                      setState(() {});
                    },
                  ),

                const SizedBox(height: 16),

                // ── Payment Summary Card ──
                if (_selectedShop != null &&
                    _entryMode != InvoiceEntryMode.cashReceipt)
                  _buildPaymentSummary(
                    cs,
                    ts,
                    currency,
                    saleAmount: displayedSubtotal,
                    discount: displayedDiscount,
                    amountReceived: _amountReceived,
                  ),
                if (_selectedShop != null &&
                    _entryMode == InvoiceEntryMode.cashReceipt)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _summaryRow(
                            tr('balance_before', ref),
                            AppFormatters.currency(_previousBalance, currency),
                            ts,
                          ),
                          _summaryRow(
                            tr('amount_received', ref),
                            '- ${AppFormatters.currency(displayedTotal, currency)}',
                            ts,
                          ),
                          const Divider(),
                          _summaryRow(
                            tr('balance_after', ref),
                            AppFormatters.currency(
                              _previousBalance - displayedTotal,
                              currency,
                            ),
                            ts,
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // ── Notes ──
                TextField(
                  controller: _notesC,
                  focusNode: _notesFn,
                  decoration: InputDecoration(
                    labelText: tr('notes', ref),
                    prefixIcon: const Icon(Icons.notes),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(context),
                  inputFormatters: [AppInputFormatters.maxLength(300)],
                  onChanged: (_) {
                    if (!_isDirty) setState(() => _isDirty = true);
                  },
                ),
              ],
            ),
          ),
        ),

        // ── Bottom submit bar ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: cs.surface,
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Builder(
                      builder: (context) {
                        final extraLabel = totalExtraPairs > 0
                            ? ' $totalExtraPairs ${tr("pairs", ref)}'
                            : '';
                        final summary = switch (_entryMode) {
                          InvoiceEntryMode.stock =>
                            '${tr("items", ref)}: $totalDozens ${tr("lbl_cartons", ref)}$extraLabel',
                          InvoiceEntryMode.nonStock =>
                            '${tr("items", ref)}: ${nonStockItems.length}',
                          InvoiceEntryMode.cashReceipt =>
                            '${tr("amount_received", ref)}: ${AppFormatters.currency(displayedTotal, currency)}',
                        };
                        return Text(summary, style: ts.bodyMedium);
                      },
                    ),
                    if (_entryMode != InvoiceEntryMode.cashReceipt)
                      _buildSaleTypeChip(
                        ts,
                        total: displayedTotal,
                        received: _amountReceived,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppBrand.primaryColor,
                      foregroundColor: AppBrand.onPrimary,
                    ),
                    onPressed: _submitting ? null : () => _submit(context),
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppBrand.onPrimary,
                            ),
                          )
                        : const Icon(Icons.receipt_long),
                    label: Text(switch (_entryMode) {
                      InvoiceEntryMode.stock => tr('create_sale_invoice', ref),
                      InvoiceEntryMode.nonStock => tr(
                        'create_non_stock_invoice',
                        ref,
                      ),
                      InvoiceEntryMode.cashReceipt => tr(
                        'create_cash_receipt',
                        ref,
                      ),
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Payment summary card showing balance breakdown.
  Widget _buildPaymentSummary(
    ColorScheme cs,
    TextTheme ts,
    String currency, {
    required double saleAmount,
    required double discount,
    required double amountReceived,
  }) {
    final prevBal = _previousBalance;
    final sale = (saleAmount - discount).clamp(0.0, double.infinity);
    final totalDue = prevBal + sale;
    final received = amountReceived;
    final newBal = totalDue - received;

    return Card(
      color: AppTheme.clearBg(cs),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              tr('payment_summary', ref),
              style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(height: 16),
            _summaryRow(
              tr('previous_balance', ref),
              AppFormatters.currency(prevBal, currency),
              ts,
              color: prevBal > 0 ? AppBrand.errorColor : null,
            ),
            const SizedBox(height: 4),
            _summaryRow(
              tr('current_sale', ref),
              AppFormatters.currency(sale, currency),
              ts,
            ),
            if (discount > 0) ...[
              const SizedBox(height: 4),
              _summaryRow(
                tr('discount', ref),
                '- ${AppFormatters.currency(discount, currency)}',
                ts,
                color: AppBrand.successColor,
              ),
            ],
            const Divider(height: 12),
            _summaryRow(
              tr('total_outstanding', ref),
              AppFormatters.currency(totalDue, currency),
              ts,
              bold: true,
            ),
            const SizedBox(height: 4),
            _summaryRow(
              tr('amount_received', ref),
              '- ${AppFormatters.currency(received, currency)}',
              ts,
              color: received > 0 ? AppBrand.successColor : null,
            ),
            const Divider(height: 12),
            _summaryRow(
              tr('new_balance', ref),
              AppFormatters.currency(newBal, currency),
              ts,
              bold: true,
              color: newBal > 0 ? AppBrand.errorColor : AppBrand.successColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value,
    TextTheme ts, {
    bool bold = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: ts.bodySmall),
        Text(
          value,
          style: ts.bodySmall?.copyWith(
            fontWeight: bold ? FontWeight.bold : null,
            color: color,
          ),
        ),
      ],
    );
  }

  /// Auto-derived sale type chip.
  Widget _buildSaleTypeChip(
    TextTheme ts, {
    required double total,
    required double received,
  }) {
    final String label;
    final Color bg;

    if (received >= total && total > 0) {
      label = tr('sale_cash', ref);
      bg = AppBrand.successColor;
    } else if (received > 0) {
      label = tr('partial', ref);
      bg = AppBrand.warningColor;
    } else {
      label = tr('sale_credit', ref);
      bg = AppBrand.errorColor;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg.withAlpha(80)),
      ),
      child: Text(
        label,
        style: ts.labelSmall?.copyWith(color: bg, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _pickShop(BuildContext context, List<ShopModel> shops) async {
    final selected = await showModalBottomSheet<ShopModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ShopPickerSheet(shops: shops),
    );
    if (selected != null) {
      setState(() {
        _selectedShop = selected;
        _isDirty = true;
      });
    }
  }

  Future<void> _submit(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final UserModel? user;
    try {
      user = await ref.read(authUserProvider.future);
    } catch (error) {
      if (mounted) {
        final key = AppErrorMapper.key(error);
        messenger.showSnackBar(errorSnackBar(tr(key, ref)));
      }
      return;
    }
    if (!mounted) return;
    if (user == null) {
      messenger.showSnackBar(errorSnackBar(tr('err_unauthenticated', ref)));
      return;
    }
    final isOnline = ref.read(isOnlineProvider).value ?? true;
    if (!isOnline) {
      HapticFeedback.vibrate();
      messenger.showSnackBar(warningSnackBar(tr('warn_offline', ref)));
      return;
    }
    final SettingsModel settings;
    try {
      settings = await ref.read(settingsProvider.future);
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          errorSnackBar(tr(AppErrorMapper.key(error), ref)),
        );
      }
      return;
    }
    if (!mounted) return;

    if (_selectedShop == null) {
      HapticFeedback.vibrate();
      messenger.showSnackBar(warningSnackBar(tr('select_shop', ref)));
      return;
    }

    final ppc = settings.pairsPerCarton;
    final routeId = _selectedShop!.routeId.isNotEmpty
        ? _selectedShop!.routeId
        : (user.assignedRouteIds.firstOrNull ?? '');
    final currency = ref.read(routeCurrencyProvider(routeId));
    final List<Map<String, dynamic>> items;
    final Map<String, int> deductions;
    final double subtotal;
    final double discount;
    final double total;
    final double amountReceived;

    switch (_entryMode) {
      case InvoiceEntryMode.stock:
        deductions = Map<String, int>.fromEntries(
          _selectedQtys.entries
              .where((entry) => entry.value > 0)
              .map(
                (entry) => MapEntry(
                  entry.key,
                  entry.value * ppc + (_selectedExtraPairs[entry.key] ?? 0),
                ),
              ),
        );
        if (deductions.isEmpty) {
          HapticFeedback.vibrate();
          messenger.showSnackBar(
            warningSnackBar(tr('select_at_least_one_item', ref)),
          );
          return;
        }
        subtotal = _saleAmount;
        items = _buildInvoiceItems(
          ref.read(sellerInventoryProvider(user.id)).value ?? [],
          subtotal,
          ppc,
        );
        discount = _discountAmount;
        amountReceived = _amountReceived;
        total = subtotal - discount;
        break;
      case InvoiceEntryMode.nonStock:
        if (!settings.allowNonStockInvoices) {
          HapticFeedback.vibrate();
          messenger.showSnackBar(
            warningSnackBar(tr('allow_non_stock_invoices', ref)),
          );
          return;
        }
        deductions = const {};
        final products = ref.read(productsProvider).value ?? const [];
        final variants = (ref.read(allVariantsProvider).value ?? const [])
            .where(
              (variant) =>
                  variant.productId == _selectedProductId && variant.active,
            )
            .toList();
        items = _buildNonStockInvoiceItems(products, variants);
        subtotal = items.fold<double>(
          0,
          (sum, item) => sum + (item['subtotal'] as num).toDouble(),
        );
        discount = _discountAmount;
        amountReceived = _amountReceived;
        total = subtotal - discount;
        if (items.isEmpty) {
          HapticFeedback.vibrate();
          messenger.showSnackBar(
            warningSnackBar(tr('select_at_least_one_item', ref)),
          );
          return;
        }
        break;
      case InvoiceEntryMode.cashReceipt:
        final receiptAmount =
            AppFormatters.parseAmountText(_receiptAmountC.text) ?? 0;
        if (receiptAmount <= 0) {
          HapticFeedback.vibrate();
          messenger.showSnackBar(
            warningSnackBar(tr('sale_amount_required', ref)),
          );
          return;
        }
        items = const [];
        deductions = const {};
        subtotal = 0;
        discount = 0;
        total = receiptAmount;
        amountReceived = receiptAmount;
        break;
    }

    if (total <= 0) {
      HapticFeedback.vibrate();
      messenger.showSnackBar(warningSnackBar(tr('sale_amount_required', ref)));
      return;
    }

    if (_entryMode != InvoiceEntryMode.cashReceipt) {
      if (subtotal <= 0) {
        HapticFeedback.vibrate();
        messenger.showSnackBar(
          warningSnackBar(tr('sale_amount_required', ref)),
        );
        return;
      }
      if (discount < 0 || discount > subtotal) {
        HapticFeedback.vibrate();
        messenger.showSnackBar(warningSnackBar(tr('discount', ref)));
        return;
      }
      if (items.any((item) => (item['unit_price'] as num).toDouble() <= 0)) {
        HapticFeedback.vibrate();
        messenger.showSnackBar(
          warningSnackBar(tr('sale_amount_required', ref)),
        );
        return;
      }
    }

    if (amountReceivedExceedsInvoiceTotal(
      amountReceived: amountReceived,
      total: total,
    )) {
      HapticFeedback.vibrate();
      messenger.showSnackBar(
        warningSnackBar(tr('invoice_payment_exceeds_total', ref)),
      );
      return;
    }
    final invoiceFingerprint = _currentInvoiceFingerprint(deductions, items);
    if (_pendingInvoiceFingerprint != invoiceFingerprint ||
        _pendingInvoiceIdempotencyKey == null) {
      _pendingInvoiceFingerprint = invoiceFingerprint;
      _pendingInvoiceIdempotencyKey = const Uuid().v4();
    }

    if (!_submitGuard.tryStart()) {
      messenger.showSnackBar(infoSnackBar(tr('action_in_progress', ref)));
      return;
    }

    setState(() => _submitting = true);

    try {
      final notifier = ref.read(invoiceNotifierProvider.notifier);
      final invoiceId = switch (_entryMode) {
        InvoiceEntryMode.cashReceipt => await notifier.createCashReceipt(
          shopId: _selectedShop!.id,
          shopName: _selectedShop!.name,
          routeId: routeId,
          sellerId: user.id,
          sellerName: user.displayName,
          amount: total,
          createdBy: user.id,
          currency: currency,
          notes: _notesC.text.trim().isEmpty
              ? null
              : AppSanitizer.text(_notesC.text, maxLength: 300),
          paymentMethod: _paymentMethod,
          referenceNumber: _receiptReferenceC.text.trim().isEmpty
              ? null
              : AppSanitizer.text(_receiptReferenceC.text, maxLength: 100),
          idempotencyKey: _pendingInvoiceIdempotencyKey,
        ),
        InvoiceEntryMode.stock ||
        InvoiceEntryMode.nonStock => await notifier.createSaleInvoice(
          shopId: _selectedShop!.id,
          shopName: _selectedShop!.name,
          routeId: routeId,
          sellerId: user.id,
          sellerName: user.displayName,
          items: items,
          subtotal: subtotal,
          discount: discount,
          total: total,
          amountReceived: amountReceived,
          notes: _notesC.text.trim().isEmpty
              ? null
              : AppSanitizer.text(_notesC.text, maxLength: 300),
          createdBy: user.id,
          currency: currency,
          sellerInventoryDeductions: deductions,
          fulfillmentMode: _entryMode == InvoiceEntryMode.stock
              ? InvoiceModel.fulfillmentStock
              : InvoiceModel.fulfillmentNonStock,
          idempotencyKey: _pendingInvoiceIdempotencyKey,
        ),
      };

      if (mounted) {
        HapticFeedback.mediumImpact();
        _isDirty = false;
        _pendingInvoiceIdempotencyKey = null;
        _pendingInvoiceFingerprint = null;
        messenger.showSnackBar(successSnackBar(tr('invoice_created', ref)));
        final from = widget.preselectedShopId != null
            ? '/shops/${widget.preselectedShopId}'
            : '/invoices';
        router.go('/invoices/$invoiceId?from=${Uri.encodeComponent(from)}');
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        messenger.showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      _submitGuard.finish();
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ── Shop search picker bottom-sheet ──────────────────────────────────────────
class _ShopPickerSheet extends ConsumerStatefulWidget {
  final List<ShopModel> shops;
  const _ShopPickerSheet({required this.shops});

  @override
  ConsumerState<_ShopPickerSheet> createState() => _ShopPickerSheetState();
}

class _ShopPickerSheetState extends ConsumerState<_ShopPickerSheet> {
  String _query = '';
  final _searchC = TextEditingController();

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.shops
        : widget.shops
              .where(
                (s) =>
                    s.name.toLowerCase().contains(_query.toLowerCase()) ||
                    (s.area?.toLowerCase().contains(_query.toLowerCase()) ??
                        false),
              )
              .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (ctx, scrollC) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchC,
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('search', ref),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchC.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text(tr('no_data', ref)))
                : ListView.builder(
                    controller: scrollC,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final shop = filtered[i];
                      return ListTile(
                        leading: const Icon(Icons.store),
                        title: Text(shop.name),
                        subtitle: shop.area?.isNotEmpty == true
                            ? Text(shop.area!)
                            : null,
                        onTap: () => Navigator.pop(ctx, shop),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
