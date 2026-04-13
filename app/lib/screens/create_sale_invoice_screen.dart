import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/app_sanitizer.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/input_formatters.dart';
import '../core/utils/snack_helper.dart';
import '../models/seller_inventory_model.dart';
import '../models/shop_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/network_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/error_state.dart';

// =============================================================================
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
  final _discountC = TextEditingController();
  final _notesC = TextEditingController();
  final _discountFn = FocusNode();
  final _amountReceivedFn = FocusNode();
  final _notesFn = FocusNode();
  // _selectedQtys stores DOZENS per inventory item (primary UI unit)
  final Map<String, int> _selectedQtys = {};
  // _selectedExtraPairs stores extra pairs (0–11) per inventory item beyond full dozens
  final Map<String, int> _selectedExtraPairs = {};
  bool _submitting = false;
  bool _isDirty = false;
  String? _pendingInvoiceIdempotencyKey;
  String? _pendingInvoiceFingerprint;

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

  @override
  void dispose() {
    _saleAmountC.dispose();
    _amountReceivedC.dispose();
    _discountC.dispose();
    _notesC.dispose();
    _discountFn.dispose();
    _amountReceivedFn.dispose();
    _notesFn.dispose();
    super.dispose();
  }

  double get _saleAmount => double.tryParse(_saleAmountC.text.trim()) ?? 0;

  double get _discountAmount => double.tryParse(_discountC.text.trim()) ?? 0;

  double get _invoiceTotal {
    final t = _saleAmount - _discountAmount;
    return t > 0 ? t : 0;
  }

  double get _amountReceived =>
      double.tryParse(_amountReceivedC.text.trim()) ?? 0;

  double get _previousBalance => _selectedShop?.balance ?? 0;

  double get _totalOutstanding => _previousBalance + _invoiceTotal;

  double get _newBalance => _totalOutstanding - _amountReceived;

  String _currentInvoiceFingerprint(Map<String, int> deductions) {
    final entries = deductions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final deductionSignature = entries
        .map((e) => '${e.key}:${e.value}')
        .join('|');
    return [
      _selectedShop?.id ?? '',
      _saleAmount.toStringAsFixed(2),
      _discountAmount.toStringAsFixed(2),
      _amountReceived.toStringAsFixed(2),
      AppSanitizer.text(_notesC.text, maxLength: 300),
      deductionSignature,
    ].join('::');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final routeId = user.assignedRouteId ?? '';
    final shopsAsync = user.isAdmin
        ? ref.watch(shopsProvider)
        : (routeId.isNotEmpty
              ? ref.watch(shopsByRouteProvider(routeId))
              : const AsyncData<List<ShopModel>>([]));
    // Both admin and seller use their own seller_inventory (vehicle stock).
    // Admin loads stock from warehouse to their own seller_inventory via the
    // Inventory screen transfer, then selects items here to create an invoice.
    final inventoryAsync = ref.watch(sellerInventoryProvider(user.id));

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
          body: inventoryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => mappedErrorState(
              error: e,
              ref: ref,
              onRetry: () => ref.invalidate(sellerInventoryProvider(user.id)),
            ),
            data: (inventory) {
              final available = inventory
                  .where((i) => i.quantityAvailable > 0)
                  .toList();
              return _buildBody(context, user, shopsAsync, available);
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
    List<SellerInventoryModel> inventory,
  ) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final ppc = ref.watch(settingsProvider).value?.pairsPerCarton ?? 12;

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
                      final assignedRouteId = user.assignedRouteId ?? '';
                      if (user.isAdmin) {
                        ref.invalidate(shopsProvider);
                      } else if (assignedRouteId.isNotEmpty) {
                        ref.invalidate(shopsByRouteProvider(assignedRouteId));
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
                    return DropdownButtonFormField<ShopModel>(
                      initialValue: matchedShop,
                      isExpanded: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.store),
                        hintText: tr('select_shop', ref),
                        isDense: true,
                      ),
                      items: shops.map((s) {
                        return DropdownMenuItem(
                          value: s,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedShop = v),
                    );
                  },
                ),
                if (_selectedShop != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${tr('previous_balance', ref)}: ${AppFormatters.currency(_previousBalance)}',
                    style: ts.bodySmall?.copyWith(
                      color: _previousBalance > 0
                          ? AppBrand.errorColor
                          : AppBrand.successColor,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Items ──
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
                                  style: Theme.of(context).textTheme.bodySmall,
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
                                          if (dozens - 1 == 0) {
                                            _selectedExtraPairs.remove(item.id);
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
                                      : () => setState(
                                          () => _selectedQtys[item.id] =
                                              dozens + 1,
                                        ),
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
                                        : () => setState(
                                            () => _selectedExtraPairs[item.id] =
                                                extraPairs - 1,
                                          ),
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
                                    onPressed: extraPairs >= ppc - 1
                                        ? null
                                        : () => setState(
                                            () => _selectedExtraPairs[item.id] =
                                                extraPairs + 1,
                                          ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 16),

                // ── Sale Amount ──
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

                const SizedBox(height: 12),

                // ── Discount ──
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
                if (_selectedShop != null) _buildPaymentSummary(cs, ts),

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
                        return Text(
                          '${tr("items", ref)}: $totalDozens ${tr("lbl_cartons", ref)}$extraLabel',
                          style: ts.bodyMedium,
                        );
                      },
                    ),
                    _buildSaleTypeChip(ts),
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
                    label: Text(tr('create_sale_invoice', ref)),
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
  Widget _buildPaymentSummary(ColorScheme cs, TextTheme ts) {
    final prevBal = _previousBalance;
    final sale = _invoiceTotal;
    final totalDue = _totalOutstanding;
    final received = _amountReceived;
    final newBal = _newBalance;

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
              AppFormatters.currency(prevBal),
              ts,
              color: prevBal > 0 ? AppBrand.errorColor : null,
            ),
            const SizedBox(height: 4),
            _summaryRow(
              tr('current_sale', ref),
              AppFormatters.currency(sale),
              ts,
            ),
            if (_discountAmount > 0) ...[
              const SizedBox(height: 4),
              _summaryRow(
                tr('discount', ref),
                '- ${AppFormatters.currency(_discountAmount)}',
                ts,
                color: AppBrand.successColor,
              ),
            ],
            const Divider(height: 12),
            _summaryRow(
              tr('total_outstanding', ref),
              AppFormatters.currency(totalDue),
              ts,
              bold: true,
            ),
            const SizedBox(height: 4),
            _summaryRow(
              tr('amount_received', ref),
              '- ${AppFormatters.currency(received)}',
              ts,
              color: received > 0 ? AppBrand.successColor : null,
            ),
            const Divider(height: 12),
            _summaryRow(
              tr('new_balance', ref),
              AppFormatters.currency(newBal),
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
  Widget _buildSaleTypeChip(TextTheme ts) {
    final received = _amountReceived;
    final total = _invoiceTotal;
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

  Future<void> _submit(BuildContext context) async {
    final user = ref.read(authUserProvider).value;
    if (user == null) return;
    final isOnline = ref.read(isOnlineProvider).value ?? true;
    if (!isOnline) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('warn_offline', ref)));
      return;
    }
    final ppc = ref.read(settingsProvider).value?.pairsPerCarton ?? 12;

    if (_selectedShop == null) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('select_shop', ref)));
      return;
    }

    // Convert dozens → pairs for inventory deduction (quantity_available stores pairs)
    final deductions = Map<String, int>.fromEntries(
      _selectedQtys.entries
          .where((e) => e.value > 0)
          .map(
            (e) => MapEntry(
              e.key,
              e.value * ppc + (_selectedExtraPairs[e.key] ?? 0),
            ),
          ),
    );
    // Invoices are exclusively for stock sales — at least one item is required for all roles
    if (deductions.isEmpty) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('select_at_least_one_item', ref)));
      return;
    }

    final saleAmount = _saleAmount;
    if (saleAmount <= 0) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('sale_amount_required', ref)));
      return;
    }

    final discount = _discountAmount;
    if (discount < 0 || discount > saleAmount) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('discount', ref)));
      return;
    }

    // Build line items from selected inventory
    final inventoryList =
        ref.read(sellerInventoryProvider(user.id)).value ?? [];
    final total = _invoiceTotal;
    final items = _buildInvoiceItems(inventoryList, saleAmount, ppc);
    final amountReceived = _amountReceived;
    final invoiceFingerprint = _currentInvoiceFingerprint(deductions);
    if (_pendingInvoiceFingerprint != invoiceFingerprint ||
        _pendingInvoiceIdempotencyKey == null) {
      _pendingInvoiceFingerprint = invoiceFingerprint;
      _pendingInvoiceIdempotencyKey = const Uuid().v4();
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      final invoiceId = await ref
          .read(invoiceNotifierProvider.notifier)
          .createSaleInvoice(
            shopId: _selectedShop!.id,
            shopName: _selectedShop!.name,
            routeId: _selectedShop!.routeId.isNotEmpty
                ? _selectedShop!.routeId
                : (user.assignedRouteId ?? ''),
            sellerId: user.id,
            sellerName: user.displayName,
            items: items,
            subtotal: saleAmount,
            discount: discount,
            total: total,
            amountReceived: amountReceived,
            notes: _notesC.text.trim().isEmpty
                ? null
                : AppSanitizer.text(_notesC.text, maxLength: 300),
            createdBy: user.id,
            sellerInventoryDeductions: deductions,
            idempotencyKey: _pendingInvoiceIdempotencyKey,
          );

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
      if (mounted) setState(() => _submitting = false);
    }
  }
}
