---
name: testing-strategy
description: "Use when: writing new tests, auditing test coverage gaps, adding widget tests, integration tests, provider tests, or verifying test suite completeness before release."
---

# Skill: ShoesERP Testing Strategy

## Current Coverage Status (as of April 2026)
- ✅ Unit tests: 122 passing (models + core utils)
- ❌ Widget tests: 0 (directory empty)
- ❌ Provider/Riverpod tests: 0
- ❌ Integration tests: 0
- ❌ PDF export tests: 0
- ❌ Firestore rules tests: 0

## Test Pyramid Target

```
          [Integration]  ← 5 tests minimum
        [Widget Tests]   ← 15 tests minimum
      [Provider Tests]   ← 20 tests minimum
   [Unit Tests: Models]  ← ✅ 122 passing
```

## Unit Test Gaps to Fill

### Missing Model Tests
- `inventory_transaction_model_test.dart`
- `product_variant_model_test.dart`
- `seller_inventory_model_test.dart`

### Missing Core Tests
- `app_sanitizer_test.dart` — verify `_s()` strips control chars
- `error_mapper_test.dart` — verify all FirebaseException codes map
- `formatters_test.dart` — already done ✅

## Provider Tests Pattern (with Riverpod)
```dart
// Use ProviderContainer for unit-testing providers
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  test('dashboardStatsProvider returns loading when user loading', () {
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(dashboardStatsProvider), isA<AsyncLoading>());
  });
}
```

## Widget Test Pattern
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

Widget testWidget(Widget child, {List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('LoginScreen shows email and password fields', (tester) async {
    await tester.pumpWidget(testWidget(const LoginScreen()));
    expect(find.byKey(const Key('email_field')), findsOneWidget);
    expect(find.byKey(const Key('password_field')), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
```

## Critical Widget Tests to Write
1. `login_screen_test.dart` — form validation, submit button state
2. `dashboard_screen_test.dart` — loading/error/data states, role-based content
3. `stat_card_test.dart` — renders value and label correctly
4. `status_chip_test.dart` — shows correct color per status
5. `confirm_dialog_test.dart` — cancel vs confirm callbacks
6. `app_shell_test.dart` — bottom nav items visible, role guard applied

## Firestore Rules Tests (firebase-tools / firestore-rules-unit-testing)
```javascript
// test/firestore_rules_test.js
const { initializeTestEnvironment, assertFails, assertSucceeds } 
  = require('@firebase/rules-unit-testing');

describe('Firestore Rules', () => {
  it('denies unauthenticated reads to users', async () => {
    await assertFails(unauthedDb.collection('users').get());
  });
  
  it('allows admin to read all users', async () => {
    await assertSucceeds(adminDb.collection('users').get());
  });
  
  it('denies seller to read other routes', async () => {
    await assertFails(sellerDb.collection('routes').doc('other-route').get());
  });
  
  it('prevents transaction update to change route_id', async () => {
    await assertFails(sellerDb.collection('transactions').doc('tx1')
      .update({ route_id: 'other-route' }));
  });
});
```

## PDF Export Tests
```dart
void main() {
  test('buildPdfTable generates non-empty bytes', () async {
    final bytes = await buildPdfTable(
      title: 'Test Report',
      headers: ['Name', 'Amount'],
      rows: [['Shop A', '1000']],
    );
    expect(bytes.length, greaterThan(0));
  });
  
  test('_s sanitizer strips control characters', () {
    // Access via test-only export or test the behavior via PDF generation
    final sanitized = sanitizeForPdf('\x00Hello\x01World\x7F');
    expect(sanitized, 'HelloWorld');
    expect(sanitized.contains('\x00'), isFalse);
  });
}
```

## TDD Discipline Rules (from Superpowers framework)
1. **Write the test FIRST** — then write the code to make it pass
2. Test must fail before implementation exists (red)
3. Write minimum code to pass test (green)
4. Refactor while keeping tests green
5. NEVER write code before the failing test exists

## Test Coverage Commands
```bash
# Run all tests
flutter test -r expanded

# Run with coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html

# Run specific test file
flutter test test/unit/models/user_model_test.dart

# Run widget tests
flutter test test/widget/

# Firebase rules (requires firebase-tools)
npx firebase emulators:exec --only firestore "npx jest test/firestore_rules_test.js"
```

## Pre-Release Test Checklist
- [ ] All 122+ unit tests pass
- [ ] Widget tests for all critical screens
- [ ] Provider tests for dashboardStatsProvider, invoiceNotifier
- [ ] PDF generation test with non-ASCII (Arabic/Urdu) content
- [ ] Firestore rules tests for permission-denied cases
- [ ] `flutter analyze lib --no-pub` — zero issues

## Firestore Rules Emulator Test Structure

```javascript
// test/firestore_rules_test.js
const { initializeTestEnvironment, assertFails, assertSucceeds }
  = require('@firebase/rules-unit-testing');

describe('transaction update rules', () => {
  it('seller can only update description', async () => {
    await assertSucceeds(
      sellerDb.collection('transactions').doc('tx1')
        .update({ description: 'note', updated_at: serverTimestamp() })
    );
  });

  it('seller cannot update amount', async () => {
    await assertFails(
      sellerDb.collection('transactions').doc('tx1')
        .update({ amount: 9999 })
    );
  });

  it('admin can update any field', async () => {
    await assertSucceeds(
      adminDb.collection('transactions').doc('tx1')
        .update({ amount: 100, type: 'cash_in', description: 'fix' })
    );
  });
});
```

Run with:
```bash
npx firebase emulators:exec --only firestore "npx jest test/firestore_rules_test.js"
```

## Archive / Soft-Delete 4-Test Requirement
For every model that supports soft-delete (`deleted` field), four tests are mandatory:

```dart
test('active docs returned when deleted is false', ...);
test('active docs returned when deleted field is absent', ...); // pre-DI-01 docs
test('deleted docs filtered out when deleted is true', ...);
test('batch delete sets deleted=true + deleted_at + deleted_by', ...);
```
See `inline-audit SKILL.md §6` for the correct client-side filter pattern.

## Provider Test Template

```dart
// test/unit/providers/my_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(mockAdminUser)),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('provider returns loading when auth is loading', () {
    final c = ProviderContainer(
      overrides: [authUserProvider.overrideWith((ref) => const Stream.empty())],
    );
    addTearDown(c.dispose);
    expect(c.read(myProvider), isA<AsyncLoading>());
  });
}
```

## Financial Guard Tests (Required Before Release)

```dart
// test/unit/providers/create_sale_invoice_guard_test.dart
test('createSaleInvoice rejects empty items list', () async {
  expect(
    () async => await notifier.createSaleInvoice(items: []),
    throwsA(isA<ArgumentError>()),
  );
});

test('createSaleInvoice rejects amountReceived > total', () async {
  expect(
    () async => await notifier.createSaleInvoice(
      items: [item], amountReceived: 99999),
    throwsA(isA<ArgumentError>()),
  );
});

test('voidInvoice is admin-only', () async {
  expect(
    () async => sellerNotifier.voidInvoice(invoiceId: 'inv1'),
    throwsA(isA<PermissionDeniedException>()),
  );
});
```
