import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/core/l10n/financial_document_localization.dart';
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
    String receiptPhone2 = '',
    String receiptPhone3 = '',
    int pairsPerCarton = 12,
  }) => SettingsModel(
    tenantId: admin.tenantId!,
    currency: 'SAR',
    pairsPerCarton: pairsPerCarton,
    invoiceHeader: InvoiceHeaderConfig(
      nameEn: headerName,
      receiptPhone2: receiptPhone2,
      receiptPhone3: receiptPhone3,
    ),
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

  testWidgets('receipt contacts hydrate and keep local edits while dirty', (
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
    settingsStream.add(
      settings(receiptPhone2: '+966511111111', receiptPhone3: '+966522222222'),
    );
    await tester.pumpAndSettle();

    final secondPhone = find.byKey(
      const ValueKey('invoice_header_field_receipt_phone_2'),
    );
    final thirdPhone = find.byKey(
      const ValueKey('invoice_header_field_receipt_phone_3'),
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(secondPhone, 250, scrollable: scrollable);
    expect(
      tester.widget<TextField>(secondPhone).controller!.text,
      '+966511111111',
    );
    await tester.scrollUntilVisible(thirdPhone, 250, scrollable: scrollable);
    expect(
      tester.widget<TextField>(thirdPhone).controller!.text,
      '+966522222222',
    );
    expect(
      find.textContaining('Extra numbers appear in the cash receipt footer'),
      findsOneWidget,
    );

    await tester.ensureVisible(secondPhone);
    await tester.enterText(secondPhone, '+966533333333');
    tester.testTextInput.hide();
    await tester.pump();
    settingsStream.add(
      settings(receiptPhone2: '+966544444444', receiptPhone3: '+966555555555'),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(secondPhone).controller!.text,
      '+966533333333',
    );
    await tester.ensureVisible(thirdPhone);
    expect(
      tester.widget<TextField>(thirdPhone).controller!.text,
      '+966522222222',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice header settings follow remote language pair changes', (
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

    final selector = find.byKey(
      const ValueKey('financial_document_language_pair'),
    );
    expect(selector, findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<FinancialDocumentLanguagePair>>(
            selector,
          )
          .initialValue,
      FinancialDocumentLanguagePair.englishArabic,
    );

    settingsStream.add(
      settings().copyWith(
        invoiceHeader: settings().invoiceHeader.copyWith(
          documentLanguagePair: FinancialDocumentLanguagePair.englishUrdu,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<DropdownButtonFormField<FinancialDocumentLanguagePair>>(
            selector,
          )
          .initialValue,
      FinancialDocumentLanguagePair.englishUrdu,
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
