import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/return_provider.dart';
import '../providers/auth_provider.dart';
import '../models/order_return_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';
import '../core/constants/app_brand.dart';

class ReturnsListScreen extends ConsumerStatefulWidget {
  const ReturnsListScreen({super.key});

  @override
  ConsumerState<ReturnsListScreen> createState() => _ReturnsListScreenState();
}

class _ReturnsListScreenState extends ConsumerState<ReturnsListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _statusKeys = const [
    '',
    'pending',
    'approved',
    'rejected',
    'completed'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusKeys.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('returns', ref)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = ref.read(returnsProvider).valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Returns',
                fileName: 'returns',
                headers: [
                  tr('return', ref),
                  tr('customer', ref),
                  tr('type', ref),
                  tr('status', ref),
                  tr('qty_returned', ref),
                  tr('refund_amount', ref),
                  tr('created_at', ref)
                ],
                rows: data
                    .map((r) => [
                          r.id,
                          r.customerName,
                          r.type,
                          r.status,
                          r.totalQtyReturned,
                          r.refundAmount,
                          AppFormatters.date(r.createdAt)
                        ])
                    .toList(),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppBrand.onPrimary,
          unselectedLabelColor: AppBrand.onPrimaryMuted,
          indicatorColor: AppBrand.onPrimary,
          tabs: [
            Tab(text: tr('all', ref)),
            Tab(text: tr('pending', ref)),
            Tab(text: tr('approved', ref)),
            Tab(text: tr('rejected', ref)),
            Tab(text: tr('completed', ref)),
          ],
        ),
      ),
      floatingActionButton: (user?.isManager ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/returns/new'),
              icon: const Icon(Icons.add),
              label: Text(tr('new_return', ref)),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: List.generate(_statusKeys.length, (i) {
          final status = _statusKeys[i];
          return _ReturnsList(status: status);
        }),
      ),
    );
  }
}

class _ReturnsList extends ConsumerWidget {
  final String status;
  const _ReturnsList({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<OrderReturnModel>> asyncReturns;
    if (status.isEmpty) {
      asyncReturns = ref.watch(returnsProvider);
    } else {
      asyncReturns = ref.watch(returnsByStatusProvider(status));
    }

    return asyncReturns.when(
      data: (returns) {
        if (returns.isEmpty) {
          return EmptyState(
            message: tr('no_returns_found', ref),
            icon: Icons.assignment_return_outlined,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: returns.length,
          itemBuilder: (_, i) => _ReturnCard(ret: returns[i]),
        );
      },
      loading: () => const ShimmerLoading(),
      error: (e, _) => ErrorState(message: e.toString()),
    );
  }
}

class _ReturnCard extends ConsumerWidget {
  final OrderReturnModel ret;
  const _ReturnCard({required this.ret});

  Color _statusColor(String status) {
    return switch (status) {
      'pending' => Colors.orange,
      'approved' => Colors.blue,
      'rejected' => Colors.red,
      'completed' => Colors.green,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = DateFormat('dd MMM yyyy').format(ret.createdAt.toDate());

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => context.push('/returns/${ret.id}'),
        leading: const Icon(Icons.assignment_return_outlined),
        title: Text(ret.customerName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${tr('order', ref)}: ${ret.orderId}  |  ${ret.totalQtyReturned} ${tr('pairs', ref)}'),
            Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        isThreeLine: true,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(ret.status).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            ret.status.toUpperCase(),
            style: TextStyle(
              color: _statusColor(ret.status),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
