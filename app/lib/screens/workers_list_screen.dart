import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/worker_provider.dart';
import '../models/worker_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';

class WorkersListScreen extends ConsumerStatefulWidget {
  const WorkersListScreen({super.key});

  @override
  ConsumerState<WorkersListScreen> createState() => _WorkersListScreenState();
}

class _WorkersListScreenState extends ConsumerState<WorkersListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workers = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('workers', ref)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = workers.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Workers',
                fileName: 'workers',
                headers: [
                  'Name',
                  'Type',
                  'Rate/Pair',
                  'Currency',
                  'Pairs Produced',
                  'Total Earned',
                  'Active'
                ],
                rows: data
                    .map((w) => [
                          w.name,
                          w.type,
                          w.ratePerPair,
                          w.currency,
                          w.pairsProduced,
                          w.totalEarned,
                          w.active ? 'Yes' : 'No'
                        ])
                    .toList(),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppBrand.onPrimary,
          unselectedLabelColor: AppBrand.onPrimaryMuted,
          indicatorColor: AppBrand.onPrimary,
          tabs: [
            Tab(text: tr('pakistan_pk', ref)),
            Tab(text: tr('saudi_ksa', ref)),
          ],
        ),
      ),
      body: workers.when(
        data: (list) => TabBarView(
          controller: _tabController,
          children: [
            _WorkerList(workers: list.where((w) => w.type == 'pk').toList()),
            _WorkerList(workers: list.where((w) => w.type == 'ksa').toList()),
          ],
        ),
        loading: () => const ShimmerLoading(),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
      floatingActionButton: RoleGuard(
        allowed: (u) => u.isAdmin,
        child: FloatingActionButton(
          onPressed: () => context.push('/workers/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _WorkerList extends StatelessWidget {
  final List<WorkerModel> workers;
  const _WorkerList({required this.workers});

  @override
  Widget build(BuildContext context) {
    if (workers.isEmpty) {
      return const EmptyState(
        message: 'No workers in this region',
        icon: Icons.person_outline,
      );
    }
    return ListView.builder(
      itemCount: workers.length,
      itemBuilder: (_, i) => _WorkerTile(worker: workers[i]),
    );
  }
}

class _WorkerTile extends StatelessWidget {
  final WorkerModel worker;
  const _WorkerTile({required this.worker});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text(worker.name[0].toUpperCase())),
      title: Text(worker.name),
      subtitle: Text(
          'Rate: ${AppFormatters.currency(worker.ratePerPair, worker.currency)}/pair · Produced: ${worker.pairsProduced}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(AppFormatters.currency(worker.totalEarned, worker.currency),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(worker.active ? 'Active' : 'Inactive',
              style: TextStyle(
                  fontSize: 11,
                  color: worker.active ? Colors.green : Colors.grey)),
        ],
      ),
      onTap: () => context.push('/workers/${worker.id}'),
    );
  }
}
