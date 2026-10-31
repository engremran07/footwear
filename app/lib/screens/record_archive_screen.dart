import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_locale.dart';
import '../providers/archive_provider.dart';
import '../widgets/error_state.dart';

class RecordArchiveScreen extends ConsumerWidget {
  const RecordArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedRecords = ref.watch(archivedBusinessRecordsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('record_archive_title', ref))),
      body: archivedRecords.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => mappedErrorState(
          error: error,
          ref: ref,
          onRetry: () => ref.invalidate(archivedBusinessRecordsProvider),
        ),
        data: (records) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _DeletionPolicyCard(
                  subtitle: tr('record_archive_subtitle', ref),
                  explanation: tr('archive_purge_unavailable', ref),
                  deleteLabel: tr('archive_delete_permanently', ref),
                ),
              ),
            ),
            ..._sectionSlivers(
              title: tr('archive_shops', ref),
              emptyLabel: tr('archive_empty_category', ref),
              records: records.shops,
              nameOf: (shop) => shop.name,
            ),
            ..._sectionSlivers(
              title: tr('archive_routes', ref),
              emptyLabel: tr('archive_empty_category', ref),
              records: records.routes,
              nameOf: (route) => route.name,
            ),
            ..._sectionSlivers(
              title: tr('archive_products', ref),
              emptyLabel: tr('archive_empty_category', ref),
              records: records.products,
              nameOf: (product) => product.name,
            ),
            ..._sectionSlivers(
              title: tr('archive_variants', ref),
              emptyLabel: tr('archive_empty_category', ref),
              records: records.variants,
              nameOf: (variant) => variant.variantName,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _sectionSlivers<T>({
    required String title,
    required String emptyLabel,
    required List<T> records,
    required String Function(T record) nameOf,
  }) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
          child: Text(
            '$title (${records.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      if (records.isEmpty)
        SliverToBoxAdapter(
          child: ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: Text(emptyLabel),
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => ListTile(
              dense: true,
              title: Text(
                nameOf(records[index]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            childCount: records.length,
          ),
        ),
    ];
  }
}

class _DeletionPolicyCard extends StatelessWidget {
  const _DeletionPolicyCard({
    required this.subtitle,
    required this.explanation,
    required this.deleteLabel,
  });

  final String subtitle;
  final String explanation;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(subtitle)),
              ],
            ),
            const SizedBox(height: 12),
            Text(explanation),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('archive_permanent_delete_unavailable'),
              onPressed: null,
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(deleteLabel),
            ),
          ],
        ),
      ),
    );
  }
}
