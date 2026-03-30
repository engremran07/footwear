import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/snack_helper.dart';
import '../models/seller_inventory_model.dart';
import '../models/shop_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';

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
  final _saleAmountC = TextEditingController();
  final _amountReceivedC = TextEditingController();
  final _discountC = TextEditingController();
  final _notesC = TextEditingController();
  final Map<String, int> _selectedQtys = {};
  bool _submitting = false;

  @override
  void dispose() {
    _saleAmountC.dispose();
    _amountReceivedC.dispose();
    _discountC.dispose();
    _notesC.dispose();
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('create_sale_invoice', ref))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final routeId = user.assignedRouteId ?? '';
    final shopsAsync = user.isAdmin
        ? ref.watch(shopsProvider)
        : (routeId.isNotEmpty
            ? ref.watch(shopsByRouteProvider(routeId))
            : const AsyncData<List<ShopModel>>([]));
    // Admin has no seller inventory — list will be empty and items optional
    final inventoryAsync = user.isSeller
        ? ref.watch(sellerInventoryProvider(user.id))
        : const AsyncData<List<SellerInventoryModel>>([]);

    // Auto-select shop if preselected
    if (widget.preselectedShopId != null && _selectedShop == null) {
      shopsAsync.whenData((shops) {
        final match = shops.where((s) => s.id == widget.preselectedShopId);
        if (match.isNotEmpty && _selectedShop == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedShop = match.first);
          });
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('create_sale_invoice', ref)),
      ),
      body: inventoryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (inventory) {
          final available =
              inventory.where((i) => i.quantityAvailable > 0).toList();
          return _buildBody(context, user, shopsAsync, available);
        },
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
    final ppc = ref.watch(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;

    // Calculate totals from selected items
    final selectedEntries =
        _selectedQtys.entries.where((e) => e.value > 0).toList();
    final totalPairs = selectedEntries.fold<int>(0, (acc, e) => acc + e.value);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Shop selector ──
                Text(tr('select_shop', ref),
                    style:
                        ts.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                shopsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
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
                Text(tr('select_items', ref),
                    style:
                        ts.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (inventory.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(tr('no_inventory_items', ref),
                          style: ts.bodyMedium),
                    ),
                  )
                else
                  ...inventory.map((item) {
                    final qty = _selectedQtys[item.id] ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        title: Text(item.variantName,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${tr("available", ref)}: ${AppFormatters.stock(item.quantityAvailable, ppc)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 22),
                              onPressed: qty <= 0
                                  ? null
                                  : () => setState(
                                      () => _selectedQtys[item.id] = qty - 1),
                            ),
                            SizedBox(
                              width: 32,
                              child: Text('$qty',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 22),
                              onPressed: qty >= item.quantityAvailable
                                  ? null
                                  : () => setState(
                                      () => _selectedQtys[item.id] = qty + 1),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('sale_amount', ref),
                    prefixIcon: const Icon(Icons.currency_exchange),
                    hintText: '0.00',
                  ),
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: 12),

                // ── Discount ──
                TextField(
                  controller: _discountC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('discount', ref),
                    prefixIcon: const Icon(Icons.percent),
                  ),
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: 12),

                // ── Amount Received ──
                TextField(
                  controller: _amountReceivedC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('amount_received', ref),
                    prefixIcon: const Icon(Icons.payments),
                    hintText: '0.00',
                  ),
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: 16),

                // ── Payment Summary Card ──
                if (_selectedShop != null) _buildPaymentSummary(cs, ts),

                const SizedBox(height: 12),

                // ── Notes ──
                TextField(
                  controller: _notesC,
                  decoration: InputDecoration(
                    labelText: tr('notes', ref),
                    prefixIcon: const Icon(Icons.notes),
                  ),
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
                color: Colors.black.withAlpha(20),
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
                    Text('${tr("items", ref)}: $totalPairs ${tr("pairs", ref)}',
                        style: ts.bodyMedium),
                    _buildSaleTypeChip(ts),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppBrand.primaryColor,
                      foregroundColor: AppBrand.onPrimary,
                    ),
                    onPressed: _submitting ? null : () => _submit(context),
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
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
            Text(tr('payment_summary', ref),
                style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            _summaryRow(tr('previous_balance', ref),
                AppFormatters.currency(prevBal), ts,
                color: prevBal > 0 ? AppBrand.errorColor : null),
            const SizedBox(height: 4),
            _summaryRow(
                tr('current_sale', ref), AppFormatters.currency(sale), ts),
            if (_discountAmount > 0) ...[
              const SizedBox(height: 4),
              _summaryRow(tr('discount', ref),
                  '- ${AppFormatters.currency(_discountAmount)}', ts,
                  color: AppBrand.successColor),
            ],
            const Divider(height: 12),
            _summaryRow(tr('total_outstanding', ref),
                AppFormatters.currency(totalDue), ts,
                bold: true),
            const SizedBox(height: 4),
            _summaryRow(tr('amount_received', ref),
                '- ${AppFormatters.currency(received)}', ts,
                color: received > 0 ? AppBrand.successColor : null),
            const Divider(height: 12),
            _summaryRow(
                tr('new_balance', ref), AppFormatters.currency(newBal), ts,
                bold: true,
                color:
                    newBal > 0 ? AppBrand.errorColor : AppBrand.successColor),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, TextTheme ts,
      {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: ts.bodySmall),
        Text(value,
            style: ts.bodySmall?.copyWith(
              fontWeight: bold ? FontWeight.bold : null,
              color: color,
            )),
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
      child: Text(label,
          style:
              ts.labelSmall?.copyWith(color: bg, fontWeight: FontWeight.bold)),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;

    if (_selectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        warningSnackBar(tr('select_shop', ref)),
      );
      return;
    }

    final deductions = Map<String, int>.fromEntries(
      _selectedQtys.entries.where((e) => e.value > 0),
    );
    // Sellers must select inventory items; admins can create manual invoices
    if (user.isSeller && deductions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        warningSnackBar(tr('select_at_least_one_item', ref)),
      );
      return;
    }

    final saleAmount = _saleAmount;
    if (saleAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        warningSnackBar(tr('sale_amount_required', ref)),
      );
      return;
    }

    // Build line items from selected inventory
    final inventoryList =
        ref.read(sellerInventoryProvider(user.id)).valueOrNull ?? [];
    final inventoryMap = {for (final i in inventoryList) i.id: i};

    final items = <Map<String, dynamic>>[];
    for (final entry in deductions.entries) {
      final inv = inventoryMap[entry.key];
      if (inv == null) continue;
      items.add({
        'variant_id': inv.variantId,
        'sku': '',
        'product_name': inv.variantName,
        'size': '',
        'color': '',
        'qty': entry.value,
        'unit_price': 0.0,
        'subtotal': 0.0,
      });
    }

    final discount = _discountAmount;
    final total = _invoiceTotal;
    final amountReceived = _amountReceived;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      final invoiceId =
          await ref.read(invoiceNotifierProvider.notifier).createSaleInvoice(
                customerId: _selectedShop!.id,
                customerName: _selectedShop!.name,
                shopId: _selectedShop!.id,
                shopName: _selectedShop!.name,
                routeId: _selectedShop!.routeId.isNotEmpty
                    ? _selectedShop!.routeId
                    : (user.assignedRouteId ?? ''),
                sellerId: user.isSeller ? user.id : '',
                sellerName: user.isSeller ? user.displayName : '',
                items: items,
                subtotal: saleAmount,
                discount: discount,
                total: total,
                amountReceived: amountReceived,
                notes: _notesC.text.trim().isEmpty ? null : _notesC.text.trim(),
                createdBy: user.id,
                sellerInventoryDeductions: deductions,
              );

      if (mounted) {
        messenger.showSnackBar(
          successSnackBar(tr('invoice_created', ref)),
        );
        router.go('/invoices/$invoiceId');
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
