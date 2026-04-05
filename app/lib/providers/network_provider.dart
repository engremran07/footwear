import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bidirectional online/offline detection via DNS probe.
/// Emits [true] when reachable, [false] when not.
/// Probes every 10 seconds; first result within ~100 ms.
final networkStatusProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();

  Future<void> check() async {
    try {
      final result = await InternetAddress.lookup('8.8.8.8')
          .timeout(const Duration(seconds: 5));
      if (!controller.isClosed) {
        controller.add(result.isNotEmpty && result[0].rawAddress.isNotEmpty);
      }
    } catch (_) {
      if (!controller.isClosed) controller.add(false);
    }
  }

  check();
  final timer = Timer.periodic(const Duration(seconds: 10), (_) => check());

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Alias kept for backward compatibility — prefer [networkStatusProvider].
final isOnlineProvider = networkStatusProvider;
