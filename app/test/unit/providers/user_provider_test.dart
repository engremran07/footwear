import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/providers/user_provider.dart';

void main() {
  test(
    'own display-name writes reject invalid names before Auth access',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(userManagementNotifierProvider.notifier);

      await expectLater(
        notifier.updateOwnDisplayName('  '),
        throwsArgumentError,
      );
      await expectLater(
        notifier.updateOwnDisplayName('x' * 101),
        throwsArgumentError,
      );
    },
  );
}
