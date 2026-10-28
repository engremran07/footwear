import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_animations.dart';
import '../core/design/app_tokens.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../core/utils/snack_helper.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

Future<void> copyContextualText({
  required BuildContext context,
  required WidgetRef ref,
  required String text,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(successSnackBar(tr('copied', ref)));
}

enum ContextualEntity {
  shop,
  route,
  product,
  invoice,
  transaction,
  notification,
  user,
  inventory,
}

enum ContextualActionId {
  viewDetails,
  edit,
  createInvoice,
  copyPhone,
  copyReference,
  markAsRead,
  approveEdit,
  rejectEdit,
  delete,
}

@immutable
class AppContextualAction {
  final ContextualEntity entity;
  final ContextualActionId id;
  final String label;
  final IconData icon;
  final AppCapability requiredCapability;
  final bool enabled;
  final bool destructive;
  final FutureOr<void> Function() onSelected;

  const AppContextualAction({
    required this.entity,
    required this.id,
    required this.label,
    required this.icon,
    required this.requiredCapability,
    required this.onSelected,
    this.enabled = true,
    this.destructive = false,
  });
}

List<AppContextualAction> resolveContextualActions({
  required UserModel? user,
  required ContextualEntity entity,
  required List<AppContextualAction> actions,
  String? tenantId,
}) {
  if (user == null || !user.active) return const [];
  final effectiveTenantId = tenantId ?? user.tenantId ?? user.activeWorkspaceId;
  return actions
      .where(
        (action) =>
            action.entity == entity &&
            action.enabled &&
            PermissionPolicy.can(
              user,
              action.requiredCapability,
              tenantId: effectiveTenantId,
            ),
      )
      .toList(growable: false);
}

class AppContextualActions extends ConsumerStatefulWidget {
  final ContextualEntity entity;
  final String? tenantId;
  final List<AppContextualAction> actions;
  final Widget child;

  const AppContextualActions({
    required this.entity,
    required this.actions,
    required this.child,
    this.tenantId,
    super.key,
  });

  static void openMenu(BuildContext context) {
    _ContextualActionScope.maybeOf(context)?.openMenu();
  }

  @override
  ConsumerState<AppContextualActions> createState() =>
      _AppContextualActionsState();
}

class _AppContextualActionsState extends ConsumerState<AppContextualActions> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final actions = resolveContextualActions(
      user: user,
      entity: widget.entity,
      actions: widget.actions,
      tenantId: widget.tenantId,
    );
    if (actions.isEmpty) return widget.child;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (context, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final isContextMenu = key == LogicalKeyboardKey.contextMenu;
        final isShiftF10 =
            key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed;
        if (!isContextMenu && !isShiftF10) return KeyEventResult.ignored;
        _openMenu();
        return KeyEventResult.handled;
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        customSemanticsActions: {
          for (final action in actions)
            CustomSemanticsAction(label: action.label): () =>
                _invokeAction(action),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: _openMenu,
          onSecondaryTap: _openMenu,
          child: _ContextualActionScope(
            openMenu: _openMenu,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  void _openMenu() {
    if (_menuOpen) return;
    unawaited(_showActions());
  }

  Future<void> _showActions() async {
    setState(() => _menuOpen = true);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      HapticFeedback.selectionClick();
    }

    try {
      final selectedAction = await showModalBottomSheet<AppContextualAction>(
        context: context,
        useSafeArea: true,
        sheetAnimationStyle: AnimationStyle(
          duration: AppMotion.duration(context, AppTokens.durNormal),
          reverseDuration: AppMotion.duration(context, AppTokens.durNormal),
        ),
        builder: (sheetContext) => _ActionSheet(
          entityLabel: tr(_entityLabelKey(widget.entity), ref),
          actions: resolveContextualActions(
            user: ref.read(authUserProvider).value,
            entity: widget.entity,
            actions: widget.actions,
            tenantId: widget.tenantId,
          ),
        ),
      );
      if (selectedAction != null && mounted) {
        await _invokeAction(selectedAction);
      }
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  Future<void> _invokeAction(AppContextualAction action) async {
    try {
      final currentUser = await ref.read(authUserProvider.future);
      final currentAction = resolveContextualActions(
        user: currentUser,
        entity: widget.entity,
        actions: widget.actions,
        tenantId: widget.tenantId,
      ).where((candidate) => candidate.id == action.id).firstOrNull;
      if (currentAction == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(errorSnackBar(tr('no_access', ref)));
        }
        return;
      }
      await currentAction.onSelected();
    } catch (error) {
      if (!mounted) return;
      final errorKey = AppErrorMapper.key(error);
      ScaffoldMessenger.of(context)
          .showSnackBar(errorSnackBar(tr(errorKey, ref)));
    }
  }

  String _entityLabelKey(ContextualEntity entity) => switch (entity) {
    ContextualEntity.shop => 'shops',
    ContextualEntity.route => 'routes',
    ContextualEntity.product => 'products',
    ContextualEntity.invoice => 'invoices',
    ContextualEntity.transaction => 'history',
    ContextualEntity.notification => 'notification_center',
    ContextualEntity.user => 'users',
    ContextualEntity.inventory => 'inventory',
  };
}

class AppContextualActionsButton extends ConsumerWidget {
  final ContextualEntity entity;
  final String? tenantId;
  final List<AppContextualAction> actions;

  const AppContextualActionsButton({
    required this.entity,
    required this.actions,
    this.tenantId,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = resolveContextualActions(
      user: ref.watch(authUserProvider).value,
      entity: entity,
      actions: actions,
      tenantId: tenantId,
    );
    if (resolved.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: tr('menu', ref),
      icon: const Icon(Icons.more_vert),
      onPressed: () => AppContextualActions.openMenu(context),
    );
  }
}

class _ContextualActionScope extends InheritedWidget {
  final VoidCallback openMenu;

  const _ContextualActionScope({required this.openMenu, required super.child});

  static _ContextualActionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ContextualActionScope>();

  @override
  bool updateShouldNotify(_ContextualActionScope oldWidget) =>
      openMenu != oldWidget.openMenu;
}

class _ActionSheet extends StatelessWidget {
  final String entityLabel;
  final List<AppContextualAction> actions;

  const _ActionSheet({required this.entityLabel, required this.actions});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppTokens.s8),
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppTokens.s20,
                AppTokens.s16,
                AppTokens.s20,
                AppTokens.s8,
              ),
              child: Text(
                entityLabel,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            for (final action in actions)
              ListTile(
                minTileHeight: AppTokens.minTouchTarget,
                leading: Icon(
                  action.icon,
                  color: action.destructive
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
                title: Text(
                  action.label,
                  maxLines: 2,
                  style: action.destructive
                      ? TextStyle(color: colorScheme.error)
                      : null,
                ),
                onTap: () => Navigator.of(context).pop(action),
              ),
          ],
        ),
      ),
    );
  }
}
