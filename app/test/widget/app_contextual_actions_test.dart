import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/role_names.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/widgets/app_contextual_actions.dart';

void main() {
  final timestamp = Timestamp.fromDate(DateTime.utc(2026, 10, 28));

  UserModel user(UserRole role) => UserModel(
    id: 'user-1',
    email: 'user@example.test',
    displayName: 'Test User',
    role: role,
    tenantId: 'workspace-a',
    active: true,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  AppContextualAction action({
    required AppCapability capability,
    required VoidCallback onSelected,
  }) => AppContextualAction(
    entity: ContextualEntity.shop,
    id: ContextualActionId.viewDetails,
    label: 'View details',
    icon: Icons.open_in_new,
    requiredCapability: capability,
    onSelected: onSelected,
  );

  testWidgets('long press opens an action and preserves ordinary tap', (
    tester,
  ) async {
    var taps = 0;
    var nestedTaps = 0;
    var selected = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.value(user(UserRole.admin)),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AppContextualActions(
              entity: ContextualEntity.shop,
              tenantId: 'workspace-a',
              actions: [
                action(
                  capability: AppCapability.viewShops,
                  onSelected: () => selected++,
                ),
              ],
              child: InkWell(
                onTap: () => taps++,
                child: SizedBox(
                  width: 160,
                  height: 96,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Shop row'),
                      TextButton(
                        onPressed: () => nestedTaps++,
                        child: const Text('Nested action'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shop row'));
    expect(taps, 1);
    await tester.tap(find.text('Nested action'));
    expect(nestedTaps, 1);
    await tester.longPress(find.text('Shop row'));
    await tester.pumpAndSettle();
    expect(find.text('View details'), findsOneWidget);

    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('actions unavailable to role are not presented', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.value(user(UserRole.seller)),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AppContextualActions(
              entity: ContextualEntity.shop,
              tenantId: 'workspace-a',
              actions: [
                action(
                  capability: AppCapability.manageUsers,
                  onSelected: () {},
                ),
              ],
              child: const SizedBox(
                width: 120,
                height: 64,
                child: Center(child: Text('Shop row')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Shop row'));
    await tester.pumpAndSettle();
    expect(find.text('View details'), findsNothing);
  });

  testWidgets('context menu key opens actions with large RTL text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.value(user(UserRole.admin)),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: AppContextualActions(
                  entity: ContextualEntity.shop,
                  tenantId: 'workspace-a',
                  actions: [
                    action(
                      capability: AppCapability.viewShops,
                      onSelected: () {},
                    ),
                  ],
                  child: const Focus(
                    autofocus: true,
                    child: SizedBox(
                      width: 240,
                      height: 64,
                      child: Center(child: Text('Shop row')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    expect(find.text('View details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
