import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_brand.dart';
import '../core/design/app_tokens.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/formatters.dart';
import '../models/notification_model.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/shimmer_loading.dart';

// =============================================================================
// NotificationCenterScreen — admin-only in-app notification feed.
//
// PERMISSION RULES:
//   • This route ('/notifications') is in _isAdminOnlyPath() → sellers are
//     redirected to '/' by go_router before this widget renders.
//   • The widget double-checks isAdmin as defense-in-depth and shows nothing
//     if the role is absent (auth warm-up race guard).
//
// NAVIGATION:
//   • Tap tile → markAsRead(n.id) + context.push('/shops/<shopId>').
//   • Both operations happen regardless of read state: tapping an already-read
//     notification still pushes the shop; re-marking is a no-op in Firestore.
//
// MARK ALL READ:
//   • AppBar trailing action calls notificationNotifier.markAllAsRead().
//   • Batch write capped at 50 (matches provider query limit).
// =============================================================================

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;

    // Defense-in-depth: render nothing while role is resolving.
    if (user == null) return const Scaffold(body: ShimmerLoading());

    // Route guard should prevent sellers reaching here, but double-check.
    if (!user.isAdmin) {
      return Scaffold(body: Center(child: Text(tr('no_access', ref))));
    }

    final notifAsync = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(tr('notification_center', ref)),
            if (unreadCount > 0) ...[
              const SizedBox(width: AppTokens.s8),
              _UnreadBadge(count: unreadCount),
            ],
          ],
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () => _markAllRead(context, ref),
              child: Text(
                tr('mark_all_read', ref),
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
      ),
      body: notifAsync.when(
        loading: () => const ShimmerLoading(),
        error: (e, _) => _ErrorView(error: e),
        data: (notifications) {
          if (notifications.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_none_outlined,
              message: tr('all_caught_up', ref),
            );
          }
          final groups = _groupByDay(notifications);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AppTokens.s32),
            itemCount: _listItemCount(groups),
            itemBuilder: (_, i) => _listItem(context, ref, groups, i),
          );
        },
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    await ref.read(notificationNotifierProvider.notifier).markAllAsRead();
  }

  // ─── List helpers ──────────────────────────────────────────────────────────

  int _listItemCount(List<_DayGroup> groups) {
    return groups.fold<int>(0, (acc, g) => acc + 1 + g.notifications.length);
  }

  Widget _listItem(
    BuildContext context,
    WidgetRef ref,
    List<_DayGroup> groups,
    int index,
  ) {
    int cursor = 0;
    for (final group in groups) {
      if (index == cursor) {
        return _DayHeader(rawLabel: group.label);
      }
      cursor++;
      for (final n in group.notifications) {
        if (index == cursor) {
          return _NotificationTile(notification: n);
        }
        cursor++;
      }
    }
    return const SizedBox.shrink();
  }
}

// ─── Unread badge (AppBar) ────────────────────────────────────────────────────

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppBrand.errorAccent,
        borderRadius: AppTokens.brFull,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppBrand.onPrimary,
        ),
      ),
    );
  }
}

// ─── Grouping ─────────────────────────────────────────────────────────────────

class _DayGroup {
  final String label;
  final List<NotificationModel> notifications;
  const _DayGroup(this.label, this.notifications);
}

List<_DayGroup> _groupByDay(List<NotificationModel> notifications) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final Map<int, List<NotificationModel>> byOffset = {};

  for (final n in notifications) {
    final date = n.createdAt.toDate();
    final day = DateTime(date.year, date.month, date.day);
    final offset = today.difference(day).inDays;
    byOffset.putIfAbsent(offset, () => []).add(n);
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

// ─── Notification tile ────────────────────────────────────────────────────────

class _NotificationTile extends ConsumerWidget {
  final NotificationModel notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final theme = Theme.of(context);
    final isUnread = !n.read;
    final isInvoice = n.type == 'invoice';

    // Determine icon + colors from transaction type.
    final Color accentColor;
    final IconData leadIcon;
    switch (n.transactionType) {
      case 'cash_in':
        accentColor = AppBrand.successColor;
        leadIcon = Icons.arrow_downward;
      case 'cash_out':
        accentColor = AppBrand.errorColor;
        leadIcon = isInvoice ? Icons.receipt_long : Icons.arrow_upward;
      case 'return':
        accentColor = AppBrand.infoFg;
        leadIcon = Icons.assignment_return;
      case 'write_off':
        accentColor = AppBrand.warningColor;
        leadIcon = Icons.money_off;
      default:
        accentColor = AppBrand.infoFg;
        leadIcon = Icons.notifications_outlined;
    }

    // Unread tiles get a subtle info-tinted background.
    final tileBg = isUnread
        ? AppBrand.infoBg.withValues(alpha: 0.55)
        : Colors.transparent;

    // Build subtitle: "New invoice #INV-042 • SAR 1,200" or "New transaction • SAR 500"
    final eventLabel = isInvoice
        ? tr('notification_new_invoice', ref)
        : tr('notification_new_transaction', ref);
    final subtitle = n.invoiceNumber != null && n.invoiceNumber!.isNotEmpty
        ? '$eventLabel  #${n.invoiceNumber}'
        : eventLabel;

    return Material(
      color: tileBg,
      child: InkWell(
        onTap: n.shopId.isNotEmpty ? () => _onTap(context, ref, n) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s12,
            vertical: AppTokens.s8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading icon — filled circle to make unread pop
              CircleAvatar(
                radius: 20,
                backgroundColor: accentColor.withValues(
                  alpha: isUnread ? 0.2 : 0.1,
                ),
                child: Icon(leadIcon, color: accentColor, size: 18),
              ),
              const SizedBox(width: AppTokens.s12),
              // Body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop name
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.shopName.isNotEmpty ? n.shopName : n.shopId,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppBrand.infoAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.s2),
                    // Event label + amount
                    Text(
                      '$subtitle  •  ${AppFormatters.currency(n.amount)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isUnread
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isUnread
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppTokens.s2),
                    // Seller name
                    if (n.sellerName.isNotEmpty)
                      Text(
                        n.sellerName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: AppTokens.s2),
                    // Timestamp
                    Text(
                      AppFormatters.dateTime(n.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.s4),
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

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    NotificationModel n,
  ) async {
    // Mark as read (best-effort — navigation proceeds regardless).
    if (!n.read) {
      ref.read(notificationNotifierProvider.notifier).markAsRead(n.id).ignore();
    }
    // Navigate to the shop.
    context.push('/shops/${n.shopId}');
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends ConsumerWidget {
  final Object error;
  const _ErrorView({required this.error});

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
