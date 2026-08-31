/// Notification backend for platforms without a native one.
///
/// Used on the web: `flutter_local_notifications` has no web implementation
/// and imports `dart:io` internally, so the mere presence of that import
/// would break the build. The conditional import in notifications.dart
/// picks this file when `dart:io` is unavailable.
///
/// System notifications stay a convenience: their absence takes nothing
/// away operationally, because the same events remain visible in the
/// interface itself.
class NotifBackend {
  /// False here, so the UI can hide the settings toggle instead of
  /// offering a switch that would do nothing.
  static bool get available => false;

  static Future<void> init() async {}

  static Future<void> requestPermission() async {}

  static Future<void> show(int id, String title, String body,
      {bool highPriority = true}) async {}
}
