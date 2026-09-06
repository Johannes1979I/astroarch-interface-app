import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import 'scanned_config.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _ctl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _err;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final cfg = ScannedConfig.tryParse(raw);
      if (cfg != null) {
        _handled = true;
        Navigator.pop(context, cfg);
        return;
      }
      setState(() => _err = '${'QR non valido: '.tr(context)}${raw.length > 80 ? "${raw.substring(0, 80)}…" : raw}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Scansiona QR'.tr(context)),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _ctl.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _ctl.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctl, onDetect: _onDetect),
          // Overlay con cornice
          IgnorePointer(
            child: CustomPaint(painter: _ScannerOverlay(color: T.accent(context))),
          ),
          Positioned(
            left: 24, right: 24, bottom: 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_err != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: T.err(context).withValues(alpha: 0.6)),
                    ),
                    child: Text(_err!, style: TextStyle(color: T.err(context), fontSize: 12)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Inquadra il QR mostrato dalla dashboard sul desktop di AstroArch.'.tr(context),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends CustomPainter {
  final Color color;
  _ScannerOverlay({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final boxSize = size.shortestSide * 0.7;
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2;
    final rect = Rect.fromLTWH(left, top, boxSize, boxSize);

    // sfondo semi-trasparente con buco
    final bg = Paint()..color = const Color(0x99000000);
    canvas.drawDRRect(
      RRect.fromLTRBR(0, 0, size.width, size.height, Radius.zero),
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      bg,
    );

    // angoli colorati
    final corner = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    const cornerLen = 28.0;
    // top-left
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(cornerLen, 0), corner);
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(0, cornerLen), corner);
    // top-right
    canvas.drawLine(rect.topRight, rect.topRight.translate(-cornerLen, 0), corner);
    canvas.drawLine(rect.topRight, rect.topRight.translate(0, cornerLen), corner);
    // bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(cornerLen, 0), corner);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(0, -cornerLen), corner);
    // bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(-cornerLen, 0), corner);
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(0, -cornerLen), corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
