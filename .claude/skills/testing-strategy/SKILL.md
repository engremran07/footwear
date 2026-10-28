---
name: testing-strategy
description: "Use when: writing new tests, auditing test coverage gaps, adding widget tests, integration tests, provider tests, or verifying test suite completeness before release."
---

# Skill: ShoesERP Testing Strategy

## Purpose and invocation

Choose risk-based tests for ShoesERP behavior, UI states, localization,
authorization boundaries, exports, and regressions. Use before adding tests or
when selecting validation for a code change.

## Required inputs and workflow

Inspect the current test tree, test runner, relevant implementation, and
observable contract. Select the smallest test that proves the behavior, then
expand when shared code, security, data integrity, or regressions warrant it.
Verify APIs against the pinned Flutter/Dart version.

For behavior fixes, use RED-GREEN-REFACTOR: reproduce the defect, add or
confirm a regression that fails before the fix, implement the narrow
root-cause correction, then rerun the focused test and relevant wider suites.
Cover each changed boundary with the suitable unit, provider/widget, export,
or emulator integration test; do not treat a unit test as proof of Rules or
production integration behavior.

Authorization/security changes require positive and adversarial Firestore
Rules Emulator tests of the complete client-shaped read/write batch. Any
penetration testing must have an explicit authorized scope and use local or
isolated test targets unless the owner separately authorizes a production
test window.

## Output

Report the exact command, test target, observed pass/failure output, and any
behavior or environment not covered. Do not infer broad coverage from a
focused test.

## Dependencies and boundaries

Follow `AGENTS.md` for runtime invariants and explicit release authorization.
This skill owns test strategy, not application design or production operations.

## Coverage Status

Test counts and coverage change over time. Never treat counts in this file as
current evidence. Inspect the present test tree and run the relevant commands
before reporting coverage or pass counts.

Current test locations:

- Flutter tests: `app/test/`
- Firestore Rules Emulator tests: `tests/firestore-rules/rules.test.js`

Choose coverage based on risk and observable behavior rather than a fixed
minimum per test category. Preserve existing tests and add regressions for
security, role, tenant, financial, and CRUD behavior changed by the task.

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

// tests/firestore-rules/rules.test.js
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

## Accessibility and Visual UI Tests

- Use widget tests for layout, visible state, semantics, and interactions that
  are deterministic in the test environment.
- When supported by the pinned Flutter SDK, apply the available
  `AccessibilityGuideline` checks for target sizes, labels, and contrast.
- Exercise supported locale/direction, text scaling, and narrow/expanded
  constraints for the affected screen family.
- Review golden changes rather than regenerating baselines blindly. A golden
  test verifies pixels for its fixture; it does not prove all device, locale,
  font, or assistive-technology behavior.
- Use a browser, emulator, device, or assistive technology for checks that a
  widget test cannot represent. Record checks that were unavailable instead of
  inferring visual correctness from source inspection.
- Verify test APIs against the repository's pinned Flutter SDK before use.

## TDD Discipline Rules (from Superpowers framework)

1. **Write the test FIRST** — then write the code to make it pass

2. Test must fail before implementation exists (red)

3. Write minimum code to pass test (green)

4. Refactor while keeping tests green

5. NEVER write code before the failing test exists

## Test Coverage Commands

```bash

# Run all tests

flutter test -r expanded --dart-define=use_arabic=true

# Run with coverage

flutter test --coverage --dart-define=use_arabic=true
genhtml coverage/lcov.info -o coverage/html

# Run specific Flutter test file
flutter test test/unit/models/user_model_test.dart --dart-define=use_arabic=true

# Run widget tests

flutter test test/widget/ --dart-define=use_arabic=true

# Firestore Rules Emulator suite (requires firebase-tools and npm dependencies)
Push-Location tests/firestore-rules
firebase emulators:exec --only firestore "npm test"
Pop-Location

```

## Task-Scoped Validation Checklist

- [ ] Run the smallest relevant test set first; expand to the full suite when
  shared behavior or regressions warrant it.
- [ ] Run Firestore Rules Emulator tests for Rules or authorization changes.
- [ ] Include both denied attacks and legitimate role-scoped CRUD/batch paths.
- [ ] Run `flutter analyze lib --no-pub` and `dart analyze test/` for Dart
  changes.
- [ ] For release claims, run the requested release checks and quote their
  actual output. A local test pass does not prove production deployment.

## Validation

Run the focused test command with the repository-required PDF define when
applicable. Run Dart analysis after Dart edits and Rules Emulator tests after
Rules edits. Markdown lint is required after Markdown changes. Builds,
deployments, device installs, commits, and pushes require explicit
authorization.

## Firestore Rules Emulator Test Structure

```javascript

// tests/firestore-rules/rules.test.js
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

Push-Location tests/firestore-rules
firebase emulators:exec --only firestore "npm test"
Pop-Location

```

### Same-Batch Platform Support Context

When Rules authorize a selected super-admin workspace context, test the
complete client batch, not a profile field in isolation:

- The positive case updates the profile with a concrete workspace, support
  reason, server timestamp, and exact `active_workspace_access_log_id` while
  creating the matching append-only start event in the same batch.
- Negative cases deny a profile-only selection, a log-only start, a mismatched
  event ID/actor/workspace/reason/timestamp, and an attempt to alter or delete
  an existing access event.
- Exit tests must deny profile-only context clearing, a missing or mismatched
  `last_workspace_access_end_log_id`, a forged/mismatched
  `workspace_access_ended` event, and a wrong `started_log_id`. A workspace
  switch must prove that the end event for the prior context, start event for
  the next context, and profile update all commit atomically.
- Run the complete Rules Emulator suite after changes to either side of this
  contract. Emulator success is local evidence, not proof of deployment.

### Localized Amount Input

When an amount formatter changes, test each supported digit script and its
decimal/group separators through both the actual `TextInputFormatter` and
the canonical amount parser. Retain ASCII input and reject alphabetic/currency
text at the formatter boundary; do not silently alter stored business text.

## Existing Soft-Delete Behavior

Do not introduce soft-delete behavior just to make a test or CRUD path pass.
When a requested change touches an existing soft-delete flow, first verify its
business and financial contract, then test the actual supported behavior,
including:

```dart

test('active docs returned when deleted is false', ...);
test('active docs returned when deleted field is absent', ...); // pre-DI-01 docs
test('deleted docs filtered out when deleted is true', ...);
test('authorized correction records the delete actor and timestamp atomically', ...);

```

For transaction correction, also cover the exact same-batch shop-balance
reversal and deny hard delete unless the product owner and financial contract
explicitly authorize a different design.

## Legacy Maintenance Script Tests

For repository scripts that reset, restore, export, promote roles, or migrate
tenant-owned data, test the command boundary before any Firebase-backed
execution. When policy requires a script to remain disabled, use an isolated
process test that verifies a non-zero exit and an explicit disabled message
without loading credentials or contacting Firebase:

```bash
node --test tests/maintenance_scripts.test.js
```

Do not treat a dry-run flag, project name, or client-supplied tenant ID as
proof that a bulk operation preserves record ownership. A migration that
assigns tenant IDs must use reviewed per-record ownership evidence and must
be exercised only against isolated non-production fixtures.

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
