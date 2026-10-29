import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design/app_tokens.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/snack_helper.dart';
import '../core/utils/role_names.dart';
import '../models/notification_model.dart';
import '../providers/auth_provider.dart';
import '../providers/android_notification_provider.dart';
import '../providers/notification_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/app_contextual_actions.dart';

// =============================================================================
// NotificationCenterScreen — admin and supervisor in-app notification feed.
//
// PERMISSION RULES:
//   • The router and widget require notification access; sellers are
//     redirected before this widget renders.
//   • The widget repeats the role/context check as defense in depth.
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

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  bool _markingAllRead = false;
  String? _lastTenantId;
  List<NotificationModel> _lastNotifications = const [];

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final userState = ref.watch(authUserProvider);

    if (userState.hasError) {
      return Scaffold(
        body: mappedErrorState(
          error: userState.error!,
          ref: ref,
          onRetry: () => ref.invalidate(authUserProvider),
        ),
      );
    }
    if (userState.isLoading && userState.value == null) {
      return const Scaffold(body: ShimmerLoading());
    }
    final user = userState.value;
    if (user == null) {
      return Scaffold(
        body: ErrorState(
          message: tr('err_account_not_assigned', ref),
          errorType: ErrorType.permission,
          onRetry: () => ref.invalidate(authUserProvider),
          retryLabel: tr('retry', ref),
        ),
      );
    }

    // Route guard should prevent sellers reaching here, but double-check.
    if (!user.canAccessNotifications) {
      return Scaffold(body: Center(child: Text(tr('no_access', ref))));
    }
    final tenantId = notificationTenantIdFor(user);
    if (tenantId == null) {
      if (userState.isLoading) {
        return const Scaffold(body: ShimmerLoading());
      }
      final key = !user.active
          ? 'err_user_disabled'
          : user.isSuperAdmin
          ? 'workspace_support_context_required'
          : 'err_account_not_assigned';
      return Scaffold(
        body: ErrorState(
          message: tr(key, ref),
          errorType: ErrorType.permission,
        ),
      );
    }
    final authorizedTenantId = ref.watch(notificationTenantScopeProvider);
    if (authorizedTenantId != tenantId) {
      if (userState.isLoading) {
        return const Scaffold(body: ShimmerLoading());
      }
      return Scaffold(
        body: ErrorState(
          message: tr('err_account_not_assigned', ref),
          errorType: ErrorType.permission,
          onRetry: () => ref.invalidate(authUserProvider),
          retryLabel: tr('retry', ref),
        ),
      );
    }

    final notifAsync = ref.watch(visibleNotificationsProvider);
    if (_lastTenantId != tenantId) {
      _lastTenantId = tenantId;
      _lastNotifications = const [];
    }
    if (!notifAsync.hasError && notifAsync.hasValue) {
      _lastNotifications = notifAsync.value ?? const [];
    }
    final unreadCount = _lastNotifications
        .where((notification) => !notification.read)
        .length;

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                tr('notification_center', ref),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: AppTokens.s8),
              _UnreadBadge(count: unreadCount),
            ],
          ],
        ),
        actions: [
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            IconButton(
              key: const Key('enable_android_notifications'),
              tooltip: tr('android_notifications_foreground_only', ref),
              onPressed: _enableAndroidNotifications,
              icon: const Icon(Icons.notifications_active_outlined),
            ),
          if (unreadCount > 0)
            TextButton.icon(
              onPressed: _markingAllRead ? null : _markAllRead,
              icon: _markingAllRead
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_read, size: 18),
              label: Text(tr('mark_all_read', ref)),
              style: TextButton.styleFrom(
                foregroundColor:
                    theme.appBarTheme.titleTextStyle?.color ??
                    theme.colorScheme.onPrimary,
              ),
            ),
        ],
      ),
      body: _notificationBody(notifAsync, tenantId, ref),
    );
  }

  Widget _notificationBody(
    AsyncValue<List<NotificationModel>> state,
    String? tenantId,
    WidgetRef ref,
  ) {
    if (state.hasError) {
      final error = state.error!;
      final failure = error is NotificationStreamFailure ? error : null;
      final cause = failure?.cause ?? error;
      if (_lastNotifications.isEmpty) {
        return Column(
          children: [
            Expanded(
              child: mappedErrorState(
                error: cause,
                ref: ref,
                onRetry: () => _retryFeed(tenantId),
              ),
            ),
            if (failure != null) _notificationStreamSource(failure, ref),
          ],
        );
      }
      return Column(
        children: [
          MaterialBanner(
            key: const Key('notification_feed_error'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(AppErrorMapper.key(cause), ref)),
                if (failure != null) _notificationStreamSource(failure, ref),
              ],
            ),
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            actions: [
              TextButton(
                onPressed: () => _retryFeed(tenantId),
                child: Text(tr('retry', ref)),
              ),
            ],
          ),
          Expanded(child: _notificationList(_lastNotifications, ref)),
        ],
      );
    }
    if (state.isLoading && _lastNotifications.isEmpty) {
      return const ShimmerLoading();
    }
    return _notificationList(_lastNotifications, ref);
  }

  Widget _notificationList(
    List<NotificationModel> notifications,
    WidgetRef ref,
  ) {
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
  }

  Widget _notificationStreamSource(
    NotificationStreamFailure failure,
    WidgetRef ref,
  ) {
    final sourceKey = switch (failure.source) {
      NotificationStreamSource.notifications => 'notification_feed_source',
      NotificationStreamSource.shops => 'notification_shop_visibility_source',
    };
    final code = switch (failure.cause) {
      FirebaseException(:final code) => code,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s4),
      child: Text(
        code == null ? tr(sourceKey, ref) : '${tr(sourceKey, ref)} ($code)',
        key: const Key('notification_stream_source'),
      ),
    );
  }

  void _retryFeed(String? tenantId) {
    if (tenantId == null) {
      ref.invalidate(authUserProvider);
      return;
    }
    ref.invalidate(notificationsProvider(tenantId));
    ref.invalidate(activeNotificationShopIdsProvider(tenantId));
  }

  Future<void> _enableAndroidNotifications() async {
    try {
      final enabled = await ref
          .read(androidNotificationPermissionProvider.notifier)
          .request();
      if (!mounted) return;
      final message = enabled
          ? tr('android_notifications_enabled', ref)
          : tr('android_notifications_permission_denied', ref);
      ScaffoldMessenger.of(context).showSnackBar(
        enabled ? successSnackBar(message) : errorSnackBar(message),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAllRead = true);
    try {
      await ref
          .read(notificationNotifierProvider.notifier)
          .markAllAsRead(
            _lastNotifications
                .where((notification) => !notification.read)
                .map((notification) => notification.id)
                .toSet(),
          );
    } catch (error) {
      if (!mounted) return;
      final key = AppErrorMapper.key(error);
      ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
    } finally {
      if (mounted) setState(() => _markingAllRead = false);
    }
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: AppTokens.brFull,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: colorScheme.onErrorContainer,
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
    final dayOffset = today.difference(day).inDays;
    final offset = dayOffset < 0 ? 0 : dayOffset;
    byOffset.putIfAbsent(offset, () => []).add(n);
  }

  final sorted = byOffset.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  return sorted
      .map((e) => _DayGroup(notificationDayLabel(e.key), e.value))
      .toList();
}

@visibleForTesting
String notificationDayLabel(int daysAgo) {
  if (daysAgo <= 0) return '__today__';
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
    final cs = theme.colorScheme;
    final Color accentColor;
    final IconData leadIcon;
    switch (n.transactionType) {
      case 'cash_in':
        accentColor = AppTheme.success;
        leadIcon = isInvoice ? Icons.receipt_long : Icons.arrow_downward;
      case 'cash_out':
        accentColor = cs.error;
        leadIcon = isInvoice ? Icons.receipt_long : Icons.arrow_upward;
      case 'return':
        accentColor = cs.tertiary;
        leadIcon = Icons.assignment_return;
      case 'write_off':
        accentColor = cs.secondary;
        leadIcon = Icons.money_off;
      default:
        accentColor = cs.tertiary;
        leadIcon = Icons.notifications_outlined;
    }

    // Unread tiles use theme-surface semantics, not hardcoded legacy colors.
    final tileBg = isUnread
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.surface;

    // Build subtitle: "New invoice #INV-042 • SAR 1,200" or "New transaction • SAR 500"
    final eventLabel = isInvoice
        ? tr('notification_new_invoice', ref)
        : tr('notification_new_transaction', ref);
    final subtitle = n.invoiceNumber != null && n.invoiceNumber!.isNotEmpty
        ? '$eventLabel  #${n.invoiceNumber}'
        : eventLabel;

    return AppContextualActions(
      entity: ContextualEntity.notification,
      actions: [
        if (n.shopId.isNotEmpty)
          AppContextualAction(
            entity: ContextualEntity.notification,
            id: ContextualActionId.viewDetails,
            label: tr('details', ref),
            icon: Icons.open_in_new,
            requiredCapability: AppCapability.viewNotifications,
            onSelected: () => _onTap(context, ref, n),
          ),
        if (isUnread)
          AppContextualAction(
            entity: ContextualEntity.notification,
            id: ContextualActionId.markAsRead,
            label: tr('mark_as_read', ref),
            icon: Icons.mark_email_read_outlined,
            requiredCapability: AppCapability.viewNotifications,
            onSelected: () => ref
                .read(notificationNotifierProvider.notifier)
                .markAsRead(n.id),
          ),
      ],
      child: Material(
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
                              n.shopName.isNotEmpty
                                  ? n.shopName
                                  : tr('shop', ref),
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
                              decoration: BoxDecoration(
                                color: theme.colorScheme.tertiary,
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
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: isUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppTokens.s4),
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
                if (n.shopId.isNotEmpty)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
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
    if (!n.read) {
      try {
        await ref.read(notificationNotifierProvider.notifier).markAsRead(n.id);
      } catch (error) {
        if (!context.mounted) return;
        final key = AppErrorMapper.key(error);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    }
    if (!context.mounted) return;
    context.push('/shops/${n.shopId}');
  }
}
