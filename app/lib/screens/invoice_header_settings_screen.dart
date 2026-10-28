import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/l10n/financial_document_localization.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/snack_helper.dart';
import '../models/invoice_model.dart';
import '../models/settings_model.dart';
import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/error_state.dart';

class InvoiceHeaderSettingsScreen extends ConsumerStatefulWidget {
  const InvoiceHeaderSettingsScreen({super.key});

  @override
  ConsumerState<InvoiceHeaderSettingsScreen> createState() =>
      _InvoiceHeaderSettingsScreenState();
}

class _InvoiceHeaderSettingsScreenState
    extends ConsumerState<InvoiceHeaderSettingsScreen> {
  static const _fieldKeys = <String, String>{
    'name_en': 'invoice_name_en',
    'name_ar': 'invoice_name_ar',
    'name_ur': 'invoice_name_ur',
    'subtitle_en': 'invoice_subtitle_en',
    'subtitle_ar': 'invoice_subtitle_ar',
    'subtitle_ur': 'invoice_subtitle_ur',
    'address_en': 'invoice_address_en',
    'address_ar': 'invoice_address_ar',
    'address_ur': 'invoice_address_ur',
    'phone': 'phone',
    'receipt_phone_2': 'receipt_phone_2',
    'receipt_phone_3': 'receipt_phone_3',
    'email': 'email',
    'tax_number': 'tax_registration_number',
    'commercial_registration_number': 'commercial_registration_number',
  };
  static const _visibilityKeys = <String, String>{
    'logo': 'invoice_show_logo',
    'subtitle': 'invoice_show_subtitle',
    'address': 'invoice_show_address',
    'phone': 'invoice_show_phone',
    'email': 'invoice_show_email',
    'tax_number': 'invoice_show_tax_number',
    'commercial_registration_number': 'invoice_show_commercial_registration',
  };
  static const _accentColors = ['#315C4C', '#1F4E79', '#8A3A3A', '#222222'];

  late final Map<String, TextEditingController> _controllers = {
    for (final key in _fieldKeys.keys) key: TextEditingController(),
  };
  bool _isDirty = false;
  bool _saving = false;
  bool _savingNonStockInvoices = false;
  bool _allowNonStockInvoices = false;
  String _template = 'classic';
  String _titleScale = 'normal';
  String _accentColor = _accentColors.first;
  FinancialDocumentLanguagePair _documentLanguagePair =
      FinancialDocumentLanguagePair.englishArabic;
  Set<String> _visibleFields = const {
    'logo',
    'phone',
    'email',
    'tax_number',
    'commercial_registration_number',
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _load(SettingsModel settings) {
    if (_isDirty) return;
    final header = settings.invoiceHeader;
    final values = <String, String>{
      'name_en': header.nameEn,
      'name_ar': header.nameAr,
      'name_ur': header.nameUr,
      'subtitle_en': header.subtitleEn,
      'subtitle_ar': header.subtitleAr,
      'subtitle_ur': header.subtitleUr,
      'address_en': header.addressEn,
      'address_ar': header.addressAr,
      'address_ur': header.addressUr,
      'phone': header.phone,
      'receipt_phone_2': header.receiptPhone2,
      'receipt_phone_3': header.receiptPhone3,
      'email': header.email,
      'tax_number': header.taxNumber,
      'commercial_registration_number': header.commercialRegistrationNumber,
    };
    for (final entry in values.entries) {
      _controllers[entry.key]!.value = TextEditingValue(
        text: entry.value,
        selection: TextSelection.collapsed(offset: entry.value.length),
      );
    }
    _allowNonStockInvoices = settings.allowNonStockInvoices;
    _template = header.template;
    _titleScale = header.titleScale;
    _documentLanguagePair = header.documentLanguagePair;
    _accentColor = _accentColors.contains(header.accentColor)
        ? header.accentColor
        : _accentColors.first;
    _visibleFields = header.visibleFields;
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  InvoiceHeaderConfig _config() => InvoiceHeaderConfig(
    nameEn: _controllers['name_en']!.text.trim(),
    nameAr: _controllers['name_ar']!.text.trim(),
    nameUr: _controllers['name_ur']!.text.trim(),
    subtitleEn: _controllers['subtitle_en']!.text.trim(),
    subtitleAr: _controllers['subtitle_ar']!.text.trim(),
    subtitleUr: _controllers['subtitle_ur']!.text.trim(),
    addressEn: _controllers['address_en']!.text.trim(),
    addressAr: _controllers['address_ar']!.text.trim(),
    addressUr: _controllers['address_ur']!.text.trim(),
    phone: _controllers['phone']!.text.trim(),
    receiptPhone2: _controllers['receipt_phone_2']!.text.trim(),
    receiptPhone3: _controllers['receipt_phone_3']!.text.trim(),
    email: _controllers['email']!.text.trim(),
    taxNumber: _controllers['tax_number']!.text.trim(),
    commercialRegistrationNumber:
        _controllers['commercial_registration_number']!.text.trim(),
    template: _template,
    accentColor: _accentColor,
    titleScale: _titleScale,
    documentLanguagePair: _documentLanguagePair,
    visibleFields: _visibleFields,
  );

  Future<void> _save() async {
    if (_saving || _savingNonStockInvoices) return;
    setState(() => _saving = true);
    try {
      final config = _config();
      await ref.read(settingsNotifierProvider.notifier).save({
        'allow_non_stock_invoices': _allowNonStockInvoices,
        'invoice_header': config.toJson(),
      });
      if (mounted) {
        setState(() {
          _isDirty = false;
        });
        ref.invalidate(settingsProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(successSnackBar(tr('saved_successfully', ref)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setAllowNonStockInvoices(bool value) async {
    if (_saving || _savingNonStockInvoices || value == _allowNonStockInvoices) {
      return;
    }
    final previousValue = _allowNonStockInvoices;
    setState(() {
      _allowNonStockInvoices = value;
      _savingNonStockInvoices = true;
    });
    try {
      await ref.read(settingsNotifierProvider.notifier).save({
        'allow_non_stock_invoices': value,
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _allowNonStockInvoices = previousValue;
          _savingNonStockInvoices = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
      }
      return;
    }
    if (mounted) setState(() => _savingNonStockInvoices = false);
  }

  Future<void> _preview(SettingsModel settings) async {
    final config = _config();
    final companyName = config.nameEn.isEmpty
        ? settings.companyName
        : config.nameEn;
    final headerSnapshot = <String, dynamic>{
      ...config.toJson(),
      if (settings.logoBase64 != null) 'logo_base64': settings.logoBase64,
    };
    final now = Timestamp.now();
    final invoice = InvoiceModel(
      id: 'preview',
      invoiceNumber: 'INV-2026-0001',
      type: InvoiceModel.typeSale,
      fulfillmentMode: InvoiceModel.fulfillmentNonStock,
      shopId: 'preview-shop',
      shopName: tr('invoice_preview_shop', ref),
      routeId: 'preview-route',
      sellerId: 'preview-seller',
      sellerName: tr('invoice_preview_seller', ref),
      items: const [
        TransactionItem(
          variantId: 'preview-variant',
          sku: 'SKU-001',
          productName: 'Classic Model · 40',
          size: '40',
          color: 'Black',
          qty: 2,
          unitPrice: 175,
          subtotal: 350,
        ),
      ],
      subtotal: 350,
      total: 350,
      amountReceived: 100,
      outstandingAmount: 250,
      status: InvoiceModel.statusPartial,
      createdBy: 'preview',
      createdAt: now,
      updatedAt: now,
      currency: settings.currency,
      headerSnapshot: headerSnapshot,
    );
    final locale = ref.read(appLocaleProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: PdfPreview(
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          onError: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr(AppErrorMapper.key(error), ref),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          build: (_) => generateInvoicePdf(
            invoice: invoice,
            companyName: companyName,
            currency: settings.currency,
            locale: locale,
            logoBytes: settings.logoBytes,
            header: config,
          ),
        ),
      ),
    );
  }

  Widget _textField(String field, {bool rtl = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: ValueKey('invoice_header_field_$field'),
        controller: _controllers[field],
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        maxLines: maxLines,
        maxLength: field.startsWith('receipt_phone_') ? 40 : 180,
        decoration: InputDecoration(
          labelText: tr(_fieldKeys[field]!, ref),
          counterText: '',
        ),
        onChanged: (_) => _markDirty(),
      ),
    );
  }

  Widget _sectionTitle(String key) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      tr(key, ref),
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final settingsAsync = ref.watch(settingsProvider);
    if (user?.isAdmin != true || user?.tenantId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('invoice_header_settings', ref))),
        body: Center(child: Text(tr('permission_denied', ref))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('invoice_header_settings', ref))),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => mappedErrorState(
          error: error,
          ref: ref,
          onRetry: () => ref.invalidate(settingsProvider),
        ),
        data: (settings) {
          _load(settings);
          return AppPullRefresh(
            onRefresh: () async {
              ref.invalidate(settingsProvider);
              await ref.read(settingsProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _allowNonStockInvoices,
                  title: Text(tr('allow_non_stock_invoices', ref)),
                  subtitle: Text(tr('allow_non_stock_invoices_hint', ref)),
                  secondary: _savingNonStockInvoices
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onChanged: _saving || _savingNonStockInvoices
                      ? null
                      : _setAllowNonStockInvoices,
                ),
                DropdownButtonFormField<FinancialDocumentLanguagePair>(
                  key: const ValueKey('financial_document_language_pair'),
                  initialValue: _documentLanguagePair,
                  decoration: InputDecoration(
                    labelText: tr('financial_document_language_pair', ref),
                    helperText: tr(
                      'financial_document_language_pair_hint',
                      ref,
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: FinancialDocumentLanguagePair.englishArabic,
                      child: Text(
                        tr('financial_document_language_english_arabic', ref),
                      ),
                    ),
                    DropdownMenuItem(
                      value: FinancialDocumentLanguagePair.englishUrdu,
                      child: Text(
                        tr('financial_document_language_english_urdu', ref),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _documentLanguagePair = value;
                        _isDirty = true;
                      });
                    }
                  },
                ),
                _sectionTitle('invoice_header_english'),
                _textField('name_en'),
                _textField('subtitle_en'),
                _textField('address_en', maxLines: 2),
                _sectionTitle('invoice_header_arabic'),
                _textField('name_ar', rtl: true),
                _textField('subtitle_ar', rtl: true),
                _textField('address_ar', rtl: true, maxLines: 2),
                _sectionTitle('invoice_header_urdu'),
                _textField('name_ur', rtl: true),
                _textField('subtitle_ur', rtl: true),
                _textField('address_ur', rtl: true, maxLines: 2),
                _sectionTitle('invoice_header_contact'),
                _textField('phone'),
                _textField('receipt_phone_2'),
                _textField('receipt_phone_3'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tr('receipt_contact_numbers_hint', ref),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                _textField('email'),
                _textField('tax_number'),
                _textField('commercial_registration_number'),
                _sectionTitle('invoice_header_template'),
                DropdownButtonFormField<String>(
                  initialValue: _template,
                  decoration: InputDecoration(
                    labelText: tr('invoice_header_template', ref),
                  ),
                  items: [
                    for (final template in ['classic', 'compact', 'centered'])
                      DropdownMenuItem(
                        value: template,
                        child: Text(tr('invoice_template_$template', ref)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _template = value;
                        _isDirty = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _titleScale,
                  decoration: InputDecoration(
                    labelText: tr('invoice_header_title_scale', ref),
                  ),
                  items: [
                    for (final scale in ['small', 'normal', 'large'])
                      DropdownMenuItem(
                        value: scale,
                        child: Text(
                          tr('invoice_header_title_scale_$scale', ref),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _titleScale = value;
                        _isDirty = true;
                      });
                    }
                  },
                ),
                _sectionTitle('invoice_header_accent'),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final color in _accentColors)
                      Semantics(
                        label: color,
                        selected: _accentColor == color,
                        child: InkWell(
                          onTap: () => setState(() {
                            _accentColor = color;
                            _isDirty = true;
                          }),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(
                                int.parse(color.substring(1), radix: 16) |
                                    0xFF000000,
                              ),
                              child: _accentColor == color
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: AppBrand.onPrimary,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                _sectionTitle('invoice_header_visible_fields'),
                for (final entry in _visibilityKeys.entries)
                  CheckboxListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _visibleFields.contains(entry.key),
                    title: Text(tr(entry.value, ref)),
                    onChanged: (value) => setState(() {
                      _visibleFields = {..._visibleFields};
                      if (value == true) {
                        _visibleFields.add(entry.key);
                      } else {
                        _visibleFields.remove(entry.key);
                      }
                      _isDirty = true;
                    }),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _preview(settings),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('invoice_header_preview', ref)),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving || _savingNonStockInvoices ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(tr('save', ref)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
