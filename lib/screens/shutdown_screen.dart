import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Spegnimento ordinato del Raspberry che ospita l'osservatorio.
///
/// Perché una schermata dedicata e non una voce con finestrella: il
/// messaggio che conta ("ora puoi togliere corrente") arriva DOPO che la
/// connessione è caduta, e a quel punto uno snack da due secondi o un
/// riquadro dentro Impostazioni sarebbero già stati smontati. Qui invece
/// resta finché l'utente non lo chiude lui.
class ShutdownScreen extends StatefulWidget {
  const ShutdownScreen({super.key});

  @override
  State<ShutdownScreen> createState() => _ShutdownScreenState();
}

enum _Phase { checking, ready, working, done, failed }

class _ShutdownScreenState extends State<ShutdownScreen> {
  _Phase _phase = _Phase.checking;
  List<Map<String, dynamic>> _blockers = const [];
  String _error = '';
  String _progress = '';
  bool _rebootMode = false;

  /// Quanto aspettiamo che il Pi smetta di rispondere prima di dire
  /// all'utente che non ne siamo sicuri. Il bridge dichiara un'attesa
  /// intorno ai 9 secondi; teniamo margine largo per l'arresto di systemd.
  static const _maxWait = Duration(seconds: 75);
  static const _pollEvery = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    setState(() { _phase = _Phase.checking; _error = ''; });
    try {
      final r = await s.api!.shutdownCheck();
      if (!mounted) return;
      setState(() {
        _blockers = _asBlockers(r['blockers']);
        _phase = _Phase.ready;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 = bridge più vecchio di 0.5.0: la funzione non c'è.
      setState(() {
        _phase = _Phase.failed;
        _error = e.status == 404
            ? 'Questo bridge non supporta lo spegnimento: aggiornalo alla 0.5.0.'
                .tr(context)
            : e.body;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _phase = _Phase.failed; _error = '$e'; });
    }
  }

  List<Map<String, dynamic>> _asBlockers(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<void> _confirmAndRun() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    final name = s.activeBridge?.name ?? '${s.host}:${s.port}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: T.panel(c),
        title: Text(_rebootMode
            ? 'Riavviare {0}?'.trFmt(c, [name])
            : 'Spegnere {0}?'.trFmt(c, [name])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_rebootMode
                ? 'KStars, Ekos e PHD2 verranno chiusi e il computer dell\'osservatorio si riavvierà.'
                    .tr(c)
                : 'KStars, Ekos e PHD2 verranno chiusi e il computer dell\'osservatorio si spegnerà.'
                    .tr(c)),
            const SizedBox(height: 10),
            if (!_rebootMode)
              Text(
                  'Per rimetterlo in funzione dovrai riaccenderlo di persona in cupola.'
                      .tr(c),
                  style: TextStyle(color: T.warn(c), fontSize: 12)),
            if (kIsWeb) ...[
              const SizedBox(height: 10),
              Text(
                  'Stai usando l\'interfaccia servita dal Raspberry: anche questa pagina smetterà di funzionare.'
                      .tr(c),
                  style: TextStyle(color: T.warn(c), fontSize: 12)),
            ],
            if (_blockers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Stai forzando nonostante:'.tr(c),
                  style: TextStyle(
                      color: T.err(c), fontSize: 12, fontWeight: FontWeight.w700)),
              for (final b in _blockers)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• ${_blockerText(c, b)}',
                      style: TextStyle(color: T.err(c), fontSize: 12)),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('ANNULLA'.tr(c))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: T.err(c)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(
                _rebootMode ? 'RIAVVIA'.tr(c) : 'SPEGNI'.tr(c),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(force: _blockers.isNotEmpty);
  }

  Future<void> _run({required bool force}) async {
    final s = context.read<AppState>();
    if (s.api == null) return;

    setState(() {
      _phase = _Phase.working;
      _error = '';
      _progress = 'Chiusura di KStars, Ekos e PHD2…'.tr(context);
    });
    // Da qui in poi la caduta della connessione è voluta: la bandiera
    // spegne il banner rosso e blocca la riconnessione automatica.
    s.markShuttingDown(true);

    try {
      if (_rebootMode) {
        await s.api!.systemReboot(force: force);
      } else {
        await s.api!.systemShutdown(force: force);
      }
    } on ApiException catch (e) {
      // Il bridge ha risposto e ha rifiutato: è un no vero, non una rete
      // che cade. Rimettiamo tutto com'era e mostriamo i motivi.
      s.markShuttingDown(false);
      if (!mounted) return;
      if (e.status == 409) {
        setState(() {
          _blockers = _blockersFromRefusal(e.body);
          _phase = _Phase.ready;
        });
      } else {
        setState(() { _phase = _Phase.failed; _error = e.body; });
      }
      return;
    } catch (_) {
      // Rete caduta prima della risposta: il comando è comunque partito.
      // Non è un errore, si prosegue ad attendere che il Pi taccia.
    }

    if (!mounted) return;
    setState(() => _progress = _rebootMode
        ? 'Riavvio in corso…'.tr(context)
        : 'Spegnimento in corso…'.tr(context));

    final silent = await _waitUntilSilent(s);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.done;
      _progress = silent
          ? ''
          : 'Il Raspberry risponde ancora: attendi qualche secondo prima di togliere corrente.'
              .tr(context);
    });
  }

  /// Aspetta che il bridge smetta di rispondere: è l'unico segnale
  /// affidabile che la macchina si è davvero fermata. `ping()` non lancia
  /// mai, restituisce false anche su errore di rete.
  Future<bool> _waitUntilSilent(AppState s) async {
    final deadline = DateTime.now().add(_maxWait);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollEvery);
      if (!mounted) return false;
      final api = s.api;
      if (api == null) return true;
      if (!await api.ping()) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _blockersFromRefusal(String body) {
    // Il 409 porta il proprio elenco dentro `detail`. Se non riusciamo a
    // rileggerlo, meglio una lista vuota che un errore: i motivi restano
    // comunque visibili nel testo dell'eccezione.
    try {
      final m = jsonDecodeSafe(body);
      final detail = m?['detail'];
      if (detail is Map) return _asBlockers(detail['blockers']);
    } catch (_) {}
    return const [];
  }

  String _blockerText(BuildContext c, Map<String, dynamic> b) {
    switch (b['code']) {
      case 'mount_unparked':
        return 'La montatura non è in park.'.tr(c);
      case 'capture_running':
        return 'C\'è una sequenza di ripresa in corso.'.tr(c);
      case 'guiding':
        return 'La guida è attiva.'.tr(c);
      default:
        return (b['message'] ?? b['code'] ?? '').toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final name = s.activeBridge?.name ?? '${s.host}:${s.port}';
    return Scaffold(
      appBar: AppBar(
          title: Text('Spegni l\'osservatorio'.tr(context)),
          automaticallyImplyLeading: _phase != _Phase.working),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(context, child: _body(context, s, name)),
        ],
      ),
    );
  }

  Widget _card(BuildContext c, {required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: T.panel(c),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.line(c)),
        ),
        child: child,
      );

  Widget _body(BuildContext c, AppState s, String name) {
    switch (_phase) {
      case _Phase.checking:
        return Row(children: [
          const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text('Controllo lo stato dell\'osservatorio…'.tr(c))),
        ]);

      case _Phase.working:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(_progress,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 12),
          Text('Non togliere corrente finché non te lo dico.'.tr(c),
              style: TextStyle(color: T.warn(c), fontSize: 12)),
        ]);

      case _Phase.done:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_rebootMode ? Icons.restart_alt : Icons.power_off,
                color: T.ok(c), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  _rebootMode
                      ? '{0} si sta riavviando.'.trFmt(c, [name])
                      : 'Ora puoi togliere corrente a {0}.'.trFmt(c, [name]),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ]),
          if (_progress.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_progress, style: TextStyle(color: T.warn(c), fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Text(
              _rebootMode
                  ? 'Tra un minuto circa potrai ricollegarti.'.tr(c)
                  : 'Il sistema si è chiuso in modo ordinato: nessun file resta a metà.'
                      .tr(c),
              style: TextStyle(color: T.muted(c), fontSize: 12)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final nav = Navigator.of(c);
                await s.disconnect();
                if (nav.canPop()) nav.pop();
              },
              child: Text('Chiudi'.tr(c)),
            ),
          ),
        ]);

      case _Phase.failed:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.error_outline, color: T.err(c), size: 26),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Non è riuscito.'.tr(c),
                    style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          Text(_error, style: TextStyle(color: T.muted(c), fontSize: 12)),
          const SizedBox(height: 16),
          OutlinedButton(
              onPressed: _check, child: Text('Riprova'.tr(c))),
        ]);

      case _Phase.ready:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('${s.host}:${s.port}',
              style: TextStyle(
                  color: T.muted(c), fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 14),
          Text(
              'Chiude KStars, Ekos e PHD2, poi spegne il computer dell\'osservatorio. È il modo giusto: togliere corrente a sistema acceso può corrompere la scheda.'
                  .tr(c),
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          if (_blockers.isEmpty)
            Row(children: [
              Icon(Icons.check_circle_outline, color: T.ok(c), size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Nessuna attività in corso: si può spegnere.'.tr(c),
                      style: TextStyle(color: T.ok(c), fontSize: 12))),
            ])
          else ...[
            Text('Attenzione:'.tr(c),
                style: TextStyle(
                    color: T.err(c), fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 6),
            for (final b in _blockers)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, color: T.err(c), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_blockerText(c, b),
                          style: TextStyle(color: T.err(c), fontSize: 12))),
                ]),
              ),
          ],
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _rebootMode,
            onChanged: (v) => setState(() => _rebootMode = v),
            title: Text('Riavvia invece di spegnere'.tr(c),
                style: const TextStyle(fontSize: 13)),
            subtitle: Text('Il computer si riavvia da solo.'.tr(c),
                style: TextStyle(color: T.muted(c), fontSize: 11)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blockers.isEmpty ? T.err(c) : T.warn(c),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: s.api == null ? null : _confirmAndRun,
              icon: Icon(_rebootMode ? Icons.restart_alt : Icons.power_off,
                  color: Colors.white),
              label: Text(
                  _blockers.isEmpty
                      ? (_rebootMode
                          ? 'Riavvia l\'osservatorio'.tr(c)
                          : 'Spegni l\'osservatorio'.tr(c))
                      : 'Forza comunque'.tr(c),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
                onPressed: _check, child: Text('Ricontrolla'.tr(c))),
          ),
        ]);
    }
  }
}

/// jsonDecode che non lancia: il corpo di un 409 è JSON, ma non vale la
/// pena far fallire una schermata se un giorno non lo fosse.
Map<String, dynamic>? jsonDecodeSafe(String s) {
  try {
    final v = jsonDecode(s);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
