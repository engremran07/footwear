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
    bool allowNonStockInvoices = false,
  }) => SettingsModel(
    tenantId: admin.tenantId!,
    currency: 'SAR',
    pairsPerCarton: pairsPerCarton,
    allowNonStockInvoices: allowNonStockInvoices,
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

  testWidgets(
    'non-stock toggle persists independently of unsaved header edits',
    (tester) async {
      final settingsStream = StreamController<SettingsModel>.broadcast();
      addTearDown(settingsStream.close);
      var currentSettings = settings();
      final savedPayloads = <Map<String, dynamic>>[];
      final settingsNotifier = _SavingSettingsNotifier((data) async {
        savedPayloads.add(Map<String, dynamic>.from(data));
        currentSettings = currentSettings.copyWith(
          allowNonStockInvoices: data['allow_non_stock_invoices'] as bool,
        );
        settingsStream.add(currentSettings);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(admin)),
            settingsProvider.overrideWith((ref) => settingsStream.stream),
            settingsNotifierProvider.overrideWith(() => settingsNotifier),
          ],
          child: const MaterialApp(home: _InvoiceHeaderEntry()),
        ),
      );

      await tester.tap(find.text('Open invoice header'));
      await tester.pump();
      settingsStream.add(currentSettings);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('invoice_header_field_name_en')),
        'Unsaved draft',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(savedPayloads, [
        {'allow_non_stock_invoices': true},
      ]);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('invoice_header_field_name_en')),
            )
            .controller!
            .text,
        'Unsaved draft',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open invoice header'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('invoice_header_field_name_en')),
            )
            .controller!
            .text,
        'Workspace Header',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('non-stock toggle restores its previous value when save fails', (
    tester,
  ) async {
    final settingsStream = StreamController<SettingsModel>.broadcast();
    addTearDown(settingsStream.close);
    final settingsNotifier = _SavingSettingsNotifier((_) async {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          settingsProvider.overrideWith((ref) => settingsStream.stream),
          settingsNotifierProvider.overrideWith(() => settingsNotifier),
        ],
        child: const MaterialApp(home: _InvoiceHeaderEntry()),
      ),
    );

    await tester.tap(find.text('Open invoice header'));
    await tester.pump();
    settingsStream.add(settings());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.byType(SnackBar), findsOneWidget);
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

class _SavingSettingsNotifier extends SettingsNotifier {
  _SavingSettingsNotifier(this.onSave);

  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  Future<void> save(Map<String, dynamic> data) => onSave(data);
}

class _InvoiceHeaderEntry extends StatelessWidget {
  const _InvoiceHeaderEntry();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const InvoiceHeaderSettingsScreen(),
          ),
        ),
        child: const Text('Open invoice header'),
      ),
    ),
  );
}
