import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bidirectional online/offline detection with hysteresis.
///
/// Why this shape:
/// - Single DNS probes can flap on mobile networks and falsely report offline.
/// - We keep the app optimistic (`true`) until repeated probe failures occur.
/// - We only switch to offline after consecutive failures to reduce jitter.
final networkStatusProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();
  const probeHosts = <String>[
    'firestore.googleapis.com',
    'google.com',
    'one.one.one.one',
  ];
  const probeTimeout = Duration(seconds: 4);
  const pollInterval = Duration(seconds: 12);
  const offlineFailureThreshold = 3;

  var failureCount = 0;
  var lastStatus = true;

  Future<bool> probeHost(String host) async {
    final result = await InternetAddress.lookup(host).timeout(probeTimeout);
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  }

  Future<void> check() async {
    var reachable = false;
    for (final host in probeHosts) {
      try {
        if (await probeHost(host)) {
          reachable = true;
          break;
        }
      } catch (_) {
        // Continue to next fallback host.
      }
    }

    if (reachable) {
      failureCount = 0;
      if (!lastStatus && !controller.isClosed) {
        controller.add(true);
      }
      lastStatus = true;
      return;
    }

    failureCount += 1;
    if (failureCount >= offlineFailureThreshold && lastStatus) {
      if (!controller.isClosed) {
        controller.add(false);
      }
      lastStatus = false;
    }
  }

  // Optimistic initial state: avoids false offline badge during startup warm-up.
  controller.add(true);
  check();
  final timer = Timer.periodic(pollInterval, (_) => check());

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Alias kept for backward compatibility — prefer [networkStatusProvider].
final isOnlineProvider = networkStatusProvider;
