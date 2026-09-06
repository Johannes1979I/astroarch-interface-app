import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Card "Avvia KStars / PHD2" nella Dashboard.
/// Due pulsanti che spawnano i binari sul DISPLAY del RPi (la finestra
/// appare sul monitor del RPi, non sul telefono). Mostra indicatore live
/// dello stato (in esecuzione / da avviare) via polling ogni 3s.
class LaunchAppsCard extends StatefulWidget {
  const LaunchAppsCard({super.key});
  @override
  State<LaunchAppsCard> createState() => _LaunchAppsCardState();
}

class _LaunchAppsCardState extends State<LaunchAppsCard> {
  Timer? _poll;
  bool _kstarsRunning = false;
  bool _phd2Running = false;
  bool _kstarsBusy = false;
  bool _phd2Busy = false;
  // Stato del sistema master (active / inactive / pending / error / unknown).
  // Quando 'inactive' i pulsanti running diventano "tap per chiudere".
  String _ekosActive = 'unknown';
  // Guider usato da Ekos ('internal' | 'phd2' | ...): se e' quello interno
  // PHD2 non va lanciato, quindi il pulsante diventa informativo e inattivo.
  String? _guideBackend;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool get _systemActive => _ekosActive == 'active';

  Future<void> _refresh() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      // In parallelo: stato GUI processi + stato master Ekos. La seconda
      // condizione decide se i pulsanti "in esecuzione" sono cliccabili
      // (per killare) o no (sistema attivo = sessione viva, non chiudere).
      final results = await Future.wait([
        s.api!.guiAppsState(),
        s.api!.ekosState().catchError((_) => <String, dynamic>{}),
        s.api!.guideBackend().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final apps = results[0];
      final ekos = results[1];
      final guide = results[2];
      setState(() {
        _kstarsRunning = apps['kstars_running'] == true;
        _phd2Running = apps['phd2_running'] == true;
        _ekosActive = (ekos['active'] as String?) ?? 'unknown';
        _guideBackend = guide['backend'] as String?;
      });
    } catch (_) {}
  }

  /// Logica unificata: tap su un pulsante può LANCIARE (se app off) o
  /// CHIUDERE (se app running E sistema disattivato). Se app running e
  /// sistema attivo, mostra warning e non fa nulla (non vogliamo
  /// chiudere KStars mentre Ekos sta usando i driver).
  Future<void> _onTap({
    required bool running,
    required Future<Map<String, dynamic>> Function() launchFn,
    required Future<Map<String, dynamic>> Function() killFn,
    required String appName,
    required void Function(bool busy) setBusy,
  }) async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    if (running && _systemActive) {
      showSnack(context,
          '${'Disattiva prima il sistema (pulsante rosso) per chiudere '.tr(context)}$appName',
          error: true);
      return;
    }
    setBusy(true);
    try {
      if (running) {
        await killFn();
        if (!mounted) return;
        showSnack(context, '${appName} ${'chiuso sul desktop del RPi'.tr(context)}');
      } else {
        final r = await launchFn();
        if (!mounted) return;
        if (r['already_running'] == true) {
          showSnack(context, '${appName} ${'già in esecuzione'.tr(context)}');
        } else {
          showSnack(context, '${appName} ${'avviato sul desktop del RPi'.tr(context)}');
        }
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context,
          '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context,
          '${'Errore: '.tr(context)}$e', error: true);
    } finally {
      if (mounted) setBusy(false);
    }
  }

  Future<void> _onTapKStars() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    await _onTap(
      running: _kstarsRunning,
      launchFn: () => s.api!.launchKStars(),
      killFn: () => s.api!.killKStars(),
      appName: 'KStars',
      setBusy: (v) => setState(() => _kstarsBusy = v),
    );
  }

  Future<void> _onTapPhd2() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    await _onTap(
      running: _phd2Running,
      launchFn: () => s.api!.launchPhd2(),
      killFn: () => s.api!.killPhd2(),
      appName: 'PHD2',
      setBusy: (v) => setState(() => _phd2Busy = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: T.panel(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.rocket_launch, size: 14, color: T.muted(context)),
          const SizedBox(width: 6),
          Text('AVVIO PROGRAMMI'.tr(context),
              style: TextStyle(color: T.muted(context),
                  fontSize: 10, letterSpacing: 1.4,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('sul desktop del RPi'.tr(context),
              style: TextStyle(color: T.muted(context),
                  fontSize: 10, fontStyle: FontStyle.italic)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _appButton(
            label: 'KSTARS / EKOS',
            icon: Icons.public,
            running: _kstarsRunning,
            busy: _kstarsBusy,
            onTap: _onTapKStars,
          )),
          const SizedBox(width: 8),
          Expanded(child: (_guideBackend == 'internal')
              // Ekos guida col guider interno: PHD2 non serve. Mostriamo lo
              // stato invece di un pulsante che confonderebbe.
              ? _appButton(
                  label: 'GUIDA INTERNA',
                  icon: Icons.auto_graph,
                  running: false,
                  busy: false,
                  onTap: null,
                  disabledSubtitle: 'PHD2 non serve'.tr(context),
                )
              : _appButton(
                  label: 'PHD2',
                  icon: Icons.gps_fixed,
                  running: _phd2Running,
                  busy: _phd2Busy,
                  onTap: _onTapPhd2,
                )),
        ]),
      ]),
    );
  }

  Widget _appButton({
    required String label, required IconData icon,
    required bool running, required bool busy,
    required VoidCallback? onTap,
    String? disabledSubtitle,
  }) {
    // onTap == null → pulsante informativo, non cliccabile (es. "GUIDA
    // INTERNA" quando Ekos non usa PHD2): stile spento, niente feedback tap.
    final bool disabled = onTap == null;
    // 3 stati visivi:
    //  - running + sistema attivo  → VERDE bloccato (tap mostra warning)
    //  - running + sistema giù     → VERDE chiudibile (subtitle "tap per chiudere")
    //  - off                        → ARANCIONE (tap per avviare)
    final canKill = running && !_systemActive;
    final Color bgColor = disabled
        ? T.line(context).withValues(alpha: 0.12)
        : running
            ? T.ok(context).withValues(alpha: 0.15)
            : T.accent(context).withValues(alpha: 0.10);
    final Color borderColor = disabled
        ? T.line(context)
        : running
            ? T.ok(context).withValues(alpha: 0.5)
            : T.accent(context).withValues(alpha: 0.4);
    final Color fgColor = disabled
        ? T.muted(context)
        : running ? T.ok(context) : T.accent(context);
    final String subtitle = disabled
        ? (disabledSubtitle ?? '')
        : running
            ? (canKill
                ? 'tap per chiudere'.tr(context)
                : 'in esecuzione'.tr(context))
            : 'avvia'.tr(context);
    final IconData buttonIcon = disabled
        ? icon
        : running
            ? (canKill ? Icons.power_settings_new : Icons.check_circle)
            : icon;

    return InkWell(
      onTap: (busy || disabled) ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(children: [
          if (busy)
            SizedBox(width: 16, height: 16, child:
                CircularProgressIndicator(strokeWidth: 2, color: fgColor))
          else
            Icon(buttonIcon, color: fgColor, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            Text(label,
                style: TextStyle(color: fgColor, fontSize: 12,
                    fontWeight: FontWeight.w700, letterSpacing: .3),
                overflow: TextOverflow.ellipsis),
            Text(subtitle,
                style: TextStyle(color: fgColor.withValues(alpha: 0.8),
                    fontSize: 10)),
          ])),
        ]),
      ),
    );
  }
}
