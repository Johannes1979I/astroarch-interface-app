/// QR scanning screen, selected per platform.
///
/// The `mobile_scanner` package cannot work on the web: the camera needs a
/// secure context, and its web implementation downloads ZXing from a CDN at
/// runtime — neither of which holds in the field, with no connection and no
/// certificate. The conditional export keeps that package out of the web
/// build, and the CDN reference with it.
///
/// `ScannedConfig` is pure Dart and holds on every platform, so it is
/// re-exported from here: callers keep importing this single file.
library;

export 'scanned_config.dart';
export 'qr_scan_screen_web.dart' if (dart.library.io) 'qr_scan_screen_io.dart';
