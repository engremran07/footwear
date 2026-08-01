import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/action_guard.dart';

void main() {
  group('ActionGuard', () {
    test('allows the first execution and blocks a duplicate start', () {
      final guard = ActionGuard();

      expect(guard.tryStart(), isTrue);
      expect(guard.tryStart(), isFalse);
      expect(guard.isLocked, isTrue);

      guard.finish();

      expect(guard.tryStart(), isTrue);
      expect(guard.isLocked, isTrue);
    });

    test('reports the busy state correctly', () {
      final guard = ActionGuard();

      expect(guard.isLocked, isFalse);

      expect(guard.tryStart(), isTrue);
      expect(guard.isLocked, isTrue);

      guard.finish();

      expect(guard.isLocked, isFalse);
    });
  });
}
