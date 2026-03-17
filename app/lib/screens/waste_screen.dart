import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/qc_provider.dart';
import '../models/waste_record_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class WasteScreen extends ConsumerStatefulWidget {
  const WasteScreen({super.key});

  @override
  ConsumerState<WasteScreen> createState() => _WasteScreenState();
}

class _WasteScreenState extends ConsumerState<WasteScreen> {
  bool _showDisposed = false;

  @override
  Widget build(BuildContext context) {
    final wasteAsync = ref.watch(wasteRecordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('waste_records', ref)),
        actions: [
          if (wasteAsync.valueOrNull != null &&
              wasteAsync.valueOrNull!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: tr('export_share', ref),
              onPressed: () {
                final list = wasteAsync.valueOrNull!;
                ExportSheet.show(
                  context,
                  ref,
                  title: 'Waste',
                  fileName: 'waste_records',
                  headers: [
                    'ID',
                    tr('batch_id', ref),
                    tr('size', ref),
                    tr('reason', ref),
                    tr('disposed', ref),
                    tr('created_at', ref)
                  ],
                  rows: list
                      .map((r) => [
                            r.id,
                            r.batchId,
                            r.size ?? '',
                            r.reason,
                            r.disposed ? 'Yes' : 'No',
                            AppFormatters.date(r.createdAt),
                          ])
                      .toList(),
                );
              },
            ),
          FilterChip(
            label: Text(tr('show_disposed', ref)),
            selected: _showDisposed,
            onSelected: (v) => setState(() => _showDisposed = v),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wasteAsync.when(
        data: (list) {
          final filtered =
              _showDisposed ? list : list.where((r) => !r.disposed).toList();
          if (filtered.isEmpty) {
            return EmptyState(
              message: _showDisposed
                  ? tr('no_waste_records', ref)
                  : tr('no_undisposed_waste', ref),
              icon: Icons.delete_outline,
            );
          }
          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) => _WasteTile(record: filtered[i]),
          );
        },
        loading: () => const ShimmerLoading(),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
    );
  }
}

class _WasteTile extends ConsumerWidget {
  final WasteRecordModel record;
  const _WasteTile({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: record.disposed
            ? Colors.grey
            : Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          record.disposed ? Icons.check : Icons.warning_amber,
          size: 18,
          color: record.disposed
              ? Colors.grey[600]
              : Theme.of(context).colorScheme.error,
        ),
      ),
      title: Text(record.reason),
      subtitle: Text(
        [
          if (record.size != null) 'Size: ${record.size}',
          AppFormatters.date(record.createdAt),
        ].join(' · '),
      ),
      trailing: record.disposed
          ? Chip(label: Text(tr('disposed', ref)))
          : RoleGuard(
              allowed: (u) => u.isAdmin,
              child: OutlinedButton(
                onPressed: () => _markDisposed(context, ref),
                child: Text(tr('dispose', ref)),
              ),
            ),
    );
  }

  Future<void> _markDisposed(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(qcNotifierProvider.notifier).markDisposed(record.id);
      if (context.mounted) {
        AppMessage.success(context, ref, 'success_waste_disposed');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }
}
