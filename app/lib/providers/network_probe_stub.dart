Future<bool> probeNetworkReachabilityImpl(String host, Duration timeout) async {
  // Firebase SDK connectivity is authoritative on web; dart:io DNS probes
  // are unavailable there and can incorrectly force the app offline.
  return true;
}
