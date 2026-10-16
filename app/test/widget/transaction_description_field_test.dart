import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/transaction_description_field.dart';

void main() {
  testWidgets('transaction description accepts and preserves new lines', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionDescriptionField(
            controller: controller,
            label: 'Description',
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.multiline);
    expect(field.textInputAction, TextInputAction.newline);
    expect(field.minLines, 2);
    expect(field.maxLines, 4);

    await tester.enterText(find.byType(TextField), 'First line\nSecond line');
    expect(controller.text, 'First line\nSecond line');
  });
}
