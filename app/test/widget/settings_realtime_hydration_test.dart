import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/screens/invoice_header_settings_screen.dart';
import 'package:footwear_erp/screens/settings_screen.dart';

void main() {
  final now = Timestamp.now();
  final admin = UserModel(
    id: 'admin-1',
    email: 'admin@example.com',
    displayName: 'Admin',
    role: UserRole.admin,
    tenantId: 'tenant-1',
    active: true,
    createdAt: now,
    updatedAt: now,
  );

  SettingsModel settings({
    String headerName = 'Workspace Header',
    int pairsPerCarton = 12,
  }) => SettingsModel(
    tenantId: admin.tenantId!,
    currency: 'SAR',
    pairsPerCarton: pairsPerCarton,
    invoiceHeader: InvoiceHeaderConfig(nameEn: headerName),
    updatedAt: now,
  );

  testWidgets('clean invoice header follows remote changes, dirty form wins', (
    tester,
  ) async {
    final settingsStream = StreamController<SettingsModel>();
    addTearDown(settingsStream.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          settingsProvider.overrideWith((ref) => settingsStream.stream),
        ],
        child: const MaterialApp(home: InvoiceHeaderSettingsScreen()),
      ),
    );
    settingsStream.add(settings());
    await tester.pumpAndSettle();

    final headerNameField = find.byType(TextField).first;
    expect(
      tester.widget<TextField>(headerNameField).controller!.text,
      'Workspace Header',
    );

    settingsStream.add(settings(headerName: 'Updated from Web'));
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(headerNameField).controller!.text,
      'Updated from Web',
    );

    await tester.enterText(headerNameField, 'Unsaved phone edit');
    settingsStream.add(settings(headerName: 'Another remote update'));
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(headerNameField).controller!.text,
      'Unsaved phone edit',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clean workspace settings follow remote changes', (tester) async {
    final settingsStream = StreamController<SettingsModel>();
    addTearDown(settingsStream.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          settingsProvider.overrideWith((ref) => settingsStream.stream),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    settingsStream.add(settings());
    await tester.pumpAndSettle();

    final cartonField = find.byType(TextField).first;
    expect(tester.widget<TextField>(cartonField).controller!.text, '12');

    settingsStream.add(settings(pairsPerCarton: 24));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(cartonField).controller!.text, '24');
    expect(tester.takeException(), isNull);
  });
}
