import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// Stand-in for the QR scanning screen on the web.
///
/// Two reasons the scanner cannot work here. The camera needs a secure
/// context: on a page served over plain HTTP — the normal case in the
/// field, where there is no way to obtain a certificate — the browser does
/// not grant it at all. And on the web the mobile_scanner package loads the
/// ZXing library from a CDN at runtime, which is unreachable with no
/// connection.
///
/// No great loss: when the interface is served by the bridge itself, host
/// and port are already known, because they are the page's own, and only
/// the token is left to type.
class QrScanScreen extends StatelessWidget {
  const QrScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Scansiona QR'.tr(context))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.no_photography_outlined,
                    size: 48, color: T.muted(context)),
                const SizedBox(height: 16),
                Text(
                  'La scansione QR non è disponibile nel browser.'.tr(context),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Inserisci i dati manualmente: li trovi nella dashboard sul desktop di AstroArch.'
                      .tr(context),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: T.muted(context), fontSize: 13),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Indietro'.tr(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
