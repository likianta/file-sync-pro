/// Wire protocol shared by the desktop client and the file server.
library;

const String appName = 'file-sync-pro';

const int protocolVersion = 1;

const int defaultFileServerPort = 2160;

const String tokenHeader = 'x-file-sync-token';

/// Server routes (relative to `<base>/<mount>/`).
abstract final class ServerRoute {
  static const manifest = 'manifest';
  static const file = 'file';
  static const directory = 'dir';
  static const stat = 'stat';
  static const health = 'health';
}
