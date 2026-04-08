---
applyTo: "app/test/**/*.dart"
---

# Testing Requirements

## Coverage Minimums

| Domain | Required Coverage |
|--------|-------------------|
| Models (fromJson/toJson) | 100% round-trip |
| Provider happy path | ≥1 test per public method |
| Provider error path | ≥1 permission-denied path test |
| Financial guards | All input validation branches |
| Widget screens | Auth guard + 2 user-visible states |

## Rules

1. **Never delete tests.** If a test fails after a code change, fix the root cause. A green test suite is non-negotiable.
2. **All new model fields** require: default-value test + round-trip test (toJson → fromJson → equality).
3. **All new provider write methods** require: happy path + ArgumentError boundary test.
4. **Admin-only methods** require: test with admin succeeds + test with seller throws.
5. **Financial guards** require: each `throw ArgumentError(...)` branch has a dedicated test case.

## Provider Test Template

```dart
// happy path
test('createFoo succeeds with valid data', () async {
  final container = ProviderContainer(overrides: [...]);
  addTearDown(container.dispose);
  // arrange...
  await container.read(fooNotifierProvider.notifier).createFoo(...);
  // assert...
});

// permission denied path
test('createFoo throws for seller when admin-only', () async {
  final container = ProviderContainer(overrides: [mockSeller]);
  addTearDown(container.dispose);
  expect(
    () => container.read(fooNotifierProvider.notifier).createFoo(...),
    throwsA(isA<ArgumentError>()),
  );
});
```

## Model Round-Trip Template

```dart
test('FooModel fromJson/toJson round-trip', () {
  final original = FooModel(id: 'test', field: 'value', ...);
  final json = original.toJson();
  final restored = FooModel.fromJson(json, 'test');
  expect(restored, equals(original));
});

test('FooModel fromJson uses default for missing field', () {
  final json = <String, dynamic>{'id': 'x'}; // missing optional fields
  final model = FooModel.fromJson(json, 'x');
  expect(model.optionalField, isNull); // or expected default
});
```

## Financial Guard Test Requirements

Every `ArgumentError` guard in `createSaleInvoice` / `updateTransaction` / `deleteTransaction` MUST have a test:
- `amountReceived > total` → throws
- `total != subtotal - discount` → throws
- `items.isEmpty` → throws (for sale invoices)
- `createdBy.isEmpty` → throws
- `discount < 0 || discount > subtotal` → throws

## Naming Convention

- Unit tests: `test/unit/{domain}_test.dart`
- Widget tests: `test/widget/{screen}_test.dart`
- Integration tests: `test/integration/{flow}_test.dart`
- All tests importable from: `test/all_tests.dart`

## What Tests Should NOT Do

- ❌ Make real Firestore calls (mock with Mockito or FakeFirebaseFirestore)
- ❌ Depend on specific Firestore document IDs existing
- ❌ Use `sleep()` or `delay()` — use `pump()` in widget tests
- ❌ Test implementation details — test behavior
