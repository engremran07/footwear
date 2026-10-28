import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/role_names.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/widgets/app_contextual_actions.dart';

void main() {
  final timestamp = Timestamp.fromDate(DateTime.utc(2026, 10, 28));

  UserModel user(UserRole role, {bool active = true}) => UserModel(
    id: 'user-1',
    email: 'user@example.test',
    displayName: 'Test User',
    role: role,
    tenantId: 'workspace-a',
    active: active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  AppContextualAction action({
    required ContextualEntity entity,
    required ContextualActionId id,
    required AppCapability capability,
    bool enabled = true,
  }) => AppContextualAction(
    entity: entity,
    id: id,
    label: id.name,
    icon: Icons.open_in_new,
    requiredCapability: capability,
    enabled: enabled,
    onSelected: () {},
  );

  test('resolver scopes actions by entity, state, and role capability', () {
    final candidates = [
      action(
        entity: ContextualEntity.shop,
        id: ContextualActionId.viewDetails,
        capability: AppCapability.viewShops,
      ),
      action(
        entity: ContextualEntity.shop,
        id: ContextualActionId.edit,
        capability: AppCapability.manageShops,
      ),
      action(
        entity: ContextualEntity.invoice,
        id: ContextualActionId.viewDetails,
        capability: AppCapability.viewInvoices,
      ),
      action(
        entity: ContextualEntity.shop,
        id: ContextualActionId.copyReference,
        capability: AppCapability.viewShops,
        enabled: false,
      ),
      action(
        entity: ContextualEntity.notification,
        id: ContextualActionId.markAsRead,
        capability: AppCapability.viewNotifications,
      ),
    ];

    final supervisorActions = resolveContextualActions(
      user: user(UserRole.supervisor),
      entity: ContextualEntity.shop,
      actions: candidates,
      tenantId: 'workspace-a',
    );
    final sellerActions = resolveContextualActions(
      user: user(UserRole.seller),
      entity: ContextualEntity.shop,
      actions: candidates,
      tenantId: 'workspace-a',
    );

    expect(supervisorActions.map((action) => action.id), [
      ContextualActionId.viewDetails,
      ContextualActionId.edit,
    ]);
    expect(sellerActions.map((action) => action.id), [
      ContextualActionId.viewDetails,
      ContextualActionId.edit,
    ]);
    expect(
      resolveContextualActions(
        user: user(UserRole.supervisor),
        entity: ContextualEntity.notification,
        actions: candidates,
        tenantId: 'workspace-a',
      ),
      hasLength(1),
    );
    expect(
      resolveContextualActions(
        user: user(UserRole.seller),
        entity: ContextualEntity.notification,
        actions: candidates,
        tenantId: 'workspace-a',
      ),
      isEmpty,
    );
  });

  test('resolver hides all actions for inactive or unscoped users', () {
    final candidates = [
      action(
        entity: ContextualEntity.shop,
        id: ContextualActionId.viewDetails,
        capability: AppCapability.viewShops,
      ),
    ];

    expect(
      resolveContextualActions(
        user: user(UserRole.admin, active: false),
        entity: ContextualEntity.shop,
        actions: candidates,
        tenantId: 'workspace-a',
      ),
      isEmpty,
    );
    expect(
      resolveContextualActions(
        user: user(UserRole.admin),
        entity: ContextualEntity.shop,
        actions: candidates,
        tenantId: '__global__',
      ),
      isEmpty,
    );
  });
}
