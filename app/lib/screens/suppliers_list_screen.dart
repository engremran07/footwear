import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/supplier_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/role_guard.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';

class SuppliersListScreen extends ConsumerStatefulWidget {
  const SuppliersListScreen({super.key});

  @override
  ConsumerState<SuppliersListScreen> createState() =>
      _SuppliersListScreenState();
}

class _SuppliersListScreenState extends ConsumerState<SuppliersListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('suppliers', ref)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = suppliers.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Suppliers',
                fileName: 'suppliers',
                headers: [
                  tr('name', ref),
                  tr('contact_name', ref),
                  tr('phone', ref),
                  tr('email', ref),
                  tr('address', ref),
                  tr('payment_terms', ref),
                  tr('total_purchased', ref),
                  tr('active', ref)
                ],
                rows: data
                    .map((s) => [
                          s.name,
                          s.contactName,
                          s.phone,
                          s.email ?? '',
                          s.address ?? '',
                          s.paymentTerms,
                          s.totalPurchased,
                          s.active ? 'Yes' : 'No'
                        ])
                    .toList(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              hintText: tr('search_suppliers', ref),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              leading: const Icon(Icons.search),
            ),
          ),
          Expanded(
            child: suppliers.when(
              data: (list) {
                final filtered = _search.isEmpty
                    ? list
                    : list
                        .where((s) =>
                            s.name.toLowerCase().contains(_search) ||
                            s.contactName.toLowerCase().contains(_search))
                        .toList();
                if (filtered.isEmpty) {
                  return EmptyState(message: tr('no_suppliers_found', ref));
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final s = filtered[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.business)),
                      title: Text(s.name),
                      subtitle: Text('${s.contactName} · ${s.phone}'),
                      onTap: () => context.push('/suppliers/${s.id}'),
                    );
                  },
                );
              },
              loading: () => const ShimmerLoading(),
              error: (e, _) => ErrorState(message: e.toString()),
            ),
          ),
        ],
      ),
      floatingActionButton: RoleGuard(
        allowed: (u) => u.isManager,
        child: FloatingActionButton(
          onPressed: () => context.push('/suppliers/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
