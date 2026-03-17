// Triggers a file download. On web: browser download. On other platforms: no-op.
export 'download_helper_web.dart'
    if (dart.library.io) 'download_helper_stub.dart';
