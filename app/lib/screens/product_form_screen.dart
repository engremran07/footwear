import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../models/product_model.dart';
import '../models/settings_model.dart';
import '../core/utils/validators.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _sellCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final List<String> _sizes = [];
  bool _loading = false;
  String? _imageUrl;

  bool get _isEdit => widget.productId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadProduct());
    }
  }

  void _loadProduct() {
    final product =
        ref.read(productDetailProvider(widget.productId!)).valueOrNull;
    if (product != null) _populateForm(product);
  }

  void _populateForm(ProductModel p) {
    _skuCtrl.text = p.sku;
    _nameCtrl.text = p.name;
    _categoryCtrl.text = p.category;
    _costCtrl.text = p.costPriceDozenPkr.toString();
    _sellCtrl.text = p.sellPriceDozenSar.toString();
    _sizes.addAll(p.sizes);
    _imageUrl = p.imageUrl;
    setState(() {});
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _costCtrl.dispose();
    _sellCtrl.dispose();
    _sizeCtrl.dispose();
    super.dispose();
  }

  void _addSize() {
    final s = _sizeCtrl.text.trim();
    if (s.isNotEmpty && !_sizes.contains(s)) {
      setState(() {
        _sizes.add(s);
        _sizeCtrl.clear();
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null) return;
    setState(() => _loading = true);
    try {
      final id = const Uuid().v4();
      final bytes = await picked.readAsBytes();
      final url = await ref
          .read(productNotifierProvider.notifier)
          .uploadImage(id, bytes);
      setState(() => _imageUrl = url);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final data = {
        'sku': _skuCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'category': _categoryCtrl.text.trim(),
        'cost_price_dozen_pkr': double.parse(_costCtrl.text.trim()),
        'sell_price_dozen_sar': double.parse(_sellCtrl.text.trim()),
        'sizes': _sizes,
        if (_imageUrl != null) 'image_url': _imageUrl,
      };

      final notifier = ref.read(productNotifierProvider.notifier);
      if (_isEdit) {
        await notifier.save(widget.productId!, data);
      } else {
        await notifier.create(data);
      }
      if (mounted) {
        AppMessage.success(
            context, ref, _isEdit ? 'success_updated' : 'success_created');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              Text(_isEdit ? tr('edit_product', ref) : tr('new_product', ref))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                    image: _imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_imageUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _imageUrl == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined,
                                size: 40),
                            const SizedBox(height: 8),
                            Text(tr('tap_add_image', ref)),
                          ],
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _skuCtrl,
                decoration: InputDecoration(labelText: '${tr('sku', ref)} *'),
                validator: AppValidators.sku,
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: '${tr('name', ref)} *'),
                validator: AppValidators.required('Name'),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              _CategoryDropdown(
                value: _categoryCtrl.text.isEmpty ? null : _categoryCtrl.text,
                onChanged: (v) => setState(() => _categoryCtrl.text = v ?? ''),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: '${tr('cost_price', ref)} *'),
                      validator: AppValidators.positiveNumber,
                      enabled: !_loading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sellCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: '${tr('sell_price', ref)} *'),
                      validator: AppValidators.positiveNumber,
                      enabled: !_loading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(tr('sizes', ref),
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sizeCtrl,
                      decoration:
                          InputDecoration(hintText: tr('add_size_hint', ref)),
                      onFieldSubmitted: (_) => _addSize(),
                      enabled: !_loading,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _addSize,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_sizes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    children: _sizes
                        .map((s) => Chip(
                              label: Text(s),
                              onDeleted: _loading
                                  ? null
                                  : () => setState(() => _sizes.remove(s)),
                            ))
                        .toList(),
                  ),
                ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit
                          ? tr('update_product', ref)
                          : tr('create_product', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryDropdown extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  const _CategoryDropdown({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).valueOrNull;
    final cats = s?.productCategories ?? SettingsModel.defaultProductCategories;
    final effectiveValue =
        (value != null && cats.contains(value)) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      decoration: InputDecoration(labelText: '${tr('category', ref)} *'),
      items:
          cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: enabled ? onChanged : null,
      validator: (v) =>
          (v == null || v.isEmpty) ? tr('category_required', ref) : null,
    );
  }
}
