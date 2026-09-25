import 'dart:io';

Future<bool> probeNetworkReachabilityImpl(String host, Duration timeout) async {
  final result = await InternetAddress.lookup(host).timeout(timeout);
  return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
}
