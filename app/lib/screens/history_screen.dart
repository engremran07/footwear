import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_brand.dart';
import '../core/design/app_tokens.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/name_resolver.dart';
import '../core/utils/formatters.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/history_provider.dart';
import '../providers/route_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/shimmer_loading.dart';

// =============================================================================
// HistoryScreen — 7-day live transaction feed.
//
// ROLE BEHAVIOUR:
//   Admin  → sees all transactions; seller name shown in subtitle.
//   Seller → sees route-scoped transactions only (enforced at provider level).
//
// NAVIGATION:
//   Tap tile → context.push('/shops/<shopId>').
//   Permission: ShopDetailScreen enforces its own role guards; this screen
//   only pushes the route. Sellers cannot tap to a shop outside their route
//   because history_provider already filters to their assigned routes.
// =============================================================================

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  Future<void> _onRefresh() async {
    ref.invalidate(recentTransactionsProvider);
    // Wait for the new stream to emit at least once.
    await ref
        .read(recentTransactionsProvider.future)
        .timeout(const Duration(seconds: 5), onTimeout: () => []);
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(recentTransactionsProvider);
    final user = ref.watch(authUserProvider).value;
    final isAdmin = user?.isAdmin ?? false;
    List<UserModel> allUsers = const <UserModel>[];
    if (isAdmin) {
      allUsers = ref.watch(allUsersExportProvider).value ?? const <UserModel>[];
    }

    final unknownUserLabel = tr('unknown_user', ref);
    final entryByMap = NameResolver(
      users: allUsers,
      extra: {
        if (user != null && user.id.isNotEmpty) user.id: user.displayName,
      },
      unknownLabel: unknownUserLabel,
    ).map;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: txAsync.when(
          loading: () => const ShimmerLoading(),
          error: (e, _) => _HistoryErrorView(error: e),
          data: (txs) {
            if (txs.isEmpty) {
              return _emptyView(context);
            }
            final groups = _groupByDay(txs);
            return _HistoryList(
              groups: groups,
              isAdmin: isAdmin,
              entryByMap: entryByMap,
              unknownUserLabel: unknownUserLabel,
            );
          },
        ),
      ),
    );
  }

  Widget _emptyView(BuildContext context) {
    return ListView(
      // Allows pull-to-refresh even on empty state.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: EmptyState(
            icon: Icons.history,
            message: tr('all_caught_up', ref),
          ),
        ),
      ],
    );
  }
}

// ─── Grouping ─────────────────────────────────────────────────────────────────

class _DayGroup {
  final String label; // "Today", "Yesterday", "3 days ago", …
  final List<TransactionModel> txs;
  const _DayGroup(this.label, this.txs);
}

List<_DayGroup> _groupByDay(List<TransactionModel> txs) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final Map<int, List<TransactionModel>> byOffset = {};
  for (final tx in txs) {
    final date = tx.createdAt.toDate();
    final day = DateTime(date.year, date.month, date.day);
    final offset = today.difference(day).inDays;
    byOffset.putIfAbsent(offset, () => []).add(tx);
  }

  final sorted = byOffset.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  return sorted.map((e) => _DayGroup(_dayLabel(e.key), e.value)).toList();
}

String _dayLabel(int daysAgo) {
  if (daysAgo == 0) return '__today__';
  if (daysAgo == 1) return '__yesterday__';
  return '__n_days_ago:${daysAgo}__';
}

// ─── List ────────────────────────────────────────────────────────────────────

class _HistoryList extends ConsumerWidget {
  final List<_DayGroup> groups;
  final bool isAdmin;
  final Map<String, String> entryByMap;
  final String unknownUserLabel;

  const _HistoryList({
    required this.groups,
    required this.isAdmin,
    required this.entryByMap,
    required this.unknownUserLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <Widget>[];

    for (final group in groups) {
      items.add(_DayHeader(rawLabel: group.label));
      for (final tx in group.txs) {
        items.add(
          _HistoryTile(
            tx: tx,
            showSellerName: isAdmin,
            entryByMap: entryByMap,
            unknownUserLabel: unknownUserLabel,
          ),
        );
      }
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppTokens.s32),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}

// ─── Day header ───────────────────────────────────────────────────────────────

class _DayHeader extends ConsumerWidget {
  final String rawLabel;
  const _DayHeader({required this.rawLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final String display;
    if (rawLabel == '__today__') {
      display = tr('today', ref);
    } else if (rawLabel == '__yesterday__') {
      display = tr('yesterday', ref);
    } else if (rawLabel.startsWith('__n_days_ago:')) {
      final n = rawLabel.replaceFirst('__n_days_ago:', '');
      display = tr('n_days_ago', ref).replaceFirst('%n%', n);
    } else {
      display = rawLabel;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s16,
        AppTokens.s16,
        AppTokens.s16,
        AppTokens.s4,
      ),
      child: Text(
        display,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Tile ────────────────────────────────────────────────────────────────────

class _HistoryTile extends ConsumerWidget {
  final TransactionModel tx;
  final bool showSellerName;
  final Map<String, String> entryByMap;
  final String unknownUserLabel;

  const _HistoryTile({
    required this.tx,
    required this.showSellerName,
    required this.entryByMap,
    required this.unknownUserLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reducesBalance = tx.reducesBalance;
    final isWriteOff = tx.isWriteOff;
    final isReturn = tx.isReturn;

    final Color accentColor;
    final IconData leadIcon;
    if (tx.deleted) {
      accentColor = theme.colorScheme.onSurfaceVariant;
      leadIcon = Icons.remove_circle_outline;
    } else if (isWriteOff) {
      accentColor = AppBrand.warningColor;
      leadIcon = Icons.money_off;
    } else if (isReturn) {
      accentColor = AppBrand.infoFg;
      leadIcon = Icons.assignment_return;
    } else if (reducesBalance) {
      accentColor = AppBrand.successColor;
      leadIcon = Icons.arrow_downward;
    } else {
      accentColor = AppBrand.errorColor;
      leadIcon = Icons.arrow_upward;
    }

    final currency = ref.watch(routeCurrencyProvider(tx.routeId));
    final sign = reducesBalance ? '+' : '−';
    final amountText = '$sign ${AppFormatters.currency(tx.amount, currency)}';
    final entryByName = tx.createdBy.isEmpty
        ? unknownUserLabel
        : (entryByMap[tx.createdBy] ?? unknownUserLabel);

    // Invoice link badge
    final bool hasInvoice = tx.invoiceId != null && tx.invoiceId!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTokens.s12,
        vertical: AppTokens.s4,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.brMD,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: AppTokens.brMD,
        onTap: tx.shopId.isNotEmpty
            ? () => context.push('/shops/${tx.shopId}')
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s12,
            vertical: AppTokens.s8,
          ),
          child: Row(
            children: [
              // Leading icon
              CircleAvatar(
                radius: 20,
                backgroundColor: accentColor.withValues(alpha: 0.12),
                child: Icon(leadIcon, color: accentColor, size: 18),
              ),
              const SizedBox(width: AppTokens.s12),
              // Body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop name + invoice badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tx.shopName.isNotEmpty ? tx.shopName : tx.shopId,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasInvoice) ...[
                          const SizedBox(width: AppTokens.s4),
                          _SmallBadge(
                            label: tx.invoiceNumber ?? 'INV',
                            bgColor: AppBrand.infoBg,
                            fgColor: AppBrand.infoFg,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppTokens.s2),
                    // Type label + seller (admin only)
                    Row(
                      children: [
                        _TypeChip(type: tx.type),
                        if (showSellerName && tx.createdBy.isNotEmpty) ...[
                          const SizedBox(width: AppTokens.s4),
                          Expanded(
                            child: Text(
                              entryByName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppTokens.s2),
                    Text(
                      AppFormatters.dateTime(tx.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.s8),
              // Amount
              Text(
                amountText,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              // Chevron
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Type chip ────────────────────────────────────────────────────────────────

class _TypeChip extends ConsumerWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color bg;
    final Color fg;
    final String label;

    switch (type) {
      case TransactionModel.typeCashIn:
        bg = AppBrand.successBg;
        fg = AppBrand.successFg;
        label = tr('cash_in', ref);
      case TransactionModel.typeCashOut:
        bg = AppBrand.errorBg;
        fg = AppBrand.errorFg;
        label = tr('cash_out', ref);
      case TransactionModel.typeReturn:
        bg = AppBrand.infoBg;
        fg = AppBrand.infoFg;
        label = tr('return', ref);
      case TransactionModel.typePayment:
        bg = AppBrand.successBg;
        fg = AppBrand.successFg;
        label = tr('payment', ref);
      case TransactionModel.typeWriteOff:
        bg = AppBrand.warningBg;
        fg = AppBrand.warningFg;
        label = tr('write_off', ref);
      default:
        bg = AppBrand.infoBg;
        fg = AppBrand.infoFg;
        label = type;
    }

    return _SmallBadge(label: label, bgColor: bg, fgColor: fg);
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color fgColor;

  const _SmallBadge({
    required this.label,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: AppTokens.s2,
      ),
      decoration: BoxDecoration(color: bgColor, borderRadius: AppTokens.brFull),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fgColor,
          height: 1.3,
        ),
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _HistoryErrorView extends ConsumerWidget {
  final Object error;
  const _HistoryErrorView({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppTokens.s12),
            Text(
              tr('error', ref),
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
