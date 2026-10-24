import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/dashboard_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/providers/shop_provider.dart';
import 'package:footwear_erp/providers/user_provider.dart';
import 'package:footwear_erp/screens/reports_screen.dart';

void main() {
  testWidgets('report export shows progress and maps provider failures', (
    tester,
  ) async {
    var exportCalls = 0;
    final shopsExportCompleter = Completer<List<ShopModel>>();
    final now = Timestamp.now();
    final admin = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.tenantAdmin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          dashboardStatsProvider.overrideWithValue(
            const AsyncData(DashboardStats()),
          ),
          settingsProvider.overrideWith((ref) => const Stream.empty()),
          shopsProvider.overrideWith((ref) => Stream.value(<ShopModel>[])),
          allUsersProvider.overrideWith((ref) => Stream.value(<UserModel>[])),
          shopsExportProvider.overrideWith((ref) async {
            exportCalls += 1;
            return shopsExportCompleter.future;
          }),
        ],
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Shops Report'));
    await tester.tap(find.text('Shops Report'));
    await tester.pump();
    await tester.pump();

    expect(exportCalls, 1);
    final exportTile = find.ancestor(
      of: find.text('Shops Report'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
        of: exportTile,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(tester.widget<ListTile>(exportTile).onTap, isNull);

    shopsExportCompleter.completeError(StateError('provider failed'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
