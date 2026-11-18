import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../state/bridge_connection.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import 'qr_scan_screen.dart';

/// Lista delle bridge salvate (multi-RPi).
/// Da qui:
///   - tap su una riga → switch immediato a quella bridge
///   - "+" in alto → aggiungi nuova (scan QR o input manuale)
///   - icona ⋮ trailing → rinomina / elimina
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});
  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  bool _switching = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text('Bridge salvate'.tr(context)),
        actions: [
          IconButton(
            tooltip: 'Aggiungi bridge'.tr(context),
            icon: const Icon(Icons.add),
            onPressed: _switching ? null : _addBridge,
          ),
        ],
      ),
      body: s.bridges.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.cloud_off, size: 48, color: T.muted(context)),
                const SizedBox(height: 12),
                Text('Nessuna bridge salvata'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 14)),
                const SizedBox(height: 6),
                Text('Tap "+" per aggiungere il primo Raspberry'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 12)),
              ])))
          : AdaptiveListView.separated(
              kind: ContentKind.form,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: s.bridges.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) => _bridgeTile(s, s.bridges[i]),
            ),
    );
  }

  Widget _bridgeTile(AppState s, BridgeConnection b) {
    final isActive = s.activeBridgeId == b.id;
    final connected = isActive && s.api != null;
    final lastUsed = b.lastUsedAt != null
        ? '${'Ultimo uso: '.tr(context)}${_formatTime(b.lastUsedAt!)}'
        : 'Mai usata'.tr(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? T.accent(context).withValues(alpha: 0.10)
            : T.panel(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? T.accent(context).withValues(alpha: 0.6)
              : T.line(context),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: (isActive ? T.accent(context) : T.muted(context))
                .withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            connected ? Icons.cloud_done
                : isActive ? Icons.cloud_outlined : Icons.cloud,
            color: connected ? T.ok(context)
                : isActive ? T.accent(context) : T.muted(context),
          ),
        ),
        title: Row(children: [
          Flexible(child: Text(b.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis)),
          if (isActive) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: connected
                    ? T.ok(context).withValues(alpha: 0.18)
                    : T.accent(context).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(connected ? 'ATTIVA · CONN'.tr(context)
                  : 'ATTIVA'.tr(context),
                  style: TextStyle(
                      color: connected ? T.ok(context) : T.accent(context),
                      fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: .6)),
            ),
          ],
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('${b.host}:${b.port}',
              style: TextStyle(color: T.muted(context),
                  fontSize: 11, fontFamily: 'monospace')),
          Text(lastUsed,
              style: TextStyle(color: T.muted(context), fontSize: 10)),
        ]),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: T.muted(context)),
          onSelected: (v) => _onMenuAction(v, b),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'rename',
                child: Row(children: [
                  Icon(Icons.edit, size: 16, color: T.text(context)),
                  const SizedBox(width: 8),
                  Text('Rinomina'.tr(context)),
                ])),
            PopupMenuItem(value: 'token',
                child: Row(children: [
                  Icon(Icons.key, size: 16, color: T.text(context)),
                  const SizedBox(width: 8),
                  Text('Mostra token'.tr(context)),
                ])),
            PopupMenuItem(value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 16, color: T.err(context)),
                  const SizedBox(width: 8),
                  Text('Elimina'.tr(context),
                      style: TextStyle(color: T.err(context))),
                ])),
          ],
        ),
        // v0.2.43: il tap funziona ANCHE sul profilo attivo — connette
        // direttamente senza fare switch (evita reset inutile dello stato).
        // Quando connect ha successo, MaterialApp passa automaticamente a
        // ShellScreen (la "schermata operativa" del bridge).
        onTap: _switching ? null : () =>
            isActive ? _connectActive(b) : _switchTo(b),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'adesso'.tr(context);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    if (diff.inDays < 7) return '${diff.inDays} g fa';
    return '${t.day.toString().padLeft(2,'0')}/${t.month.toString().padLeft(2,'0')}/${t.year}';
  }

  Future<void> _switchTo(BridgeConnection b) async {
    final s = context.read<AppState>();
    setState(() => _switching = true);
    showSnack(context, '${'Switch a '.tr(context)}${b.name}…');
    final ok = await s.switchTo(b.id);
    if (!mounted) return;
    setState(() => _switching = false);
    if (ok) {
      showSnack(context, '${'Connesso a '.tr(context)}${b.name}');
    } else {
      showSnack(context,
          '${'Switch fallito: '.tr(context)}${s.lastConnectError ?? "—"}',
          error: true);
    }
  }

  /// v0.2.43: tap sul bridge GIA' ATTIVO → connette direttamente
  /// (niente switchTo per non resettare lo stato locale). Al successo
  /// MaterialApp passa automaticamente a ShellScreen.
  Future<void> _connectActive(BridgeConnection b) async {
    final s = context.read<AppState>();
    setState(() => _switching = true);
    showSnack(context, '${'Connessione a '.tr(context)}${b.name}…');
    final ok = await s.connect();
    if (!mounted) return;
    setState(() => _switching = false);
    if (ok) {
      showSnack(context, '${'Connesso a '.tr(context)}${b.name}');
    } else {
      showSnack(context,
          '${'Errore: '.tr(context)}${s.lastConnectError ?? "—"}',
          error: true);
    }
  }

  Future<void> _onMenuAction(String action, BridgeConnection b) async {
    final s = context.read<AppState>();
    switch (action) {
      case 'rename':
        final newName = await _promptText(
          title: 'Rinomina bridge'.tr(context),
          initial: b.name,
        );
        if (newName != null && newName.trim().isNotEmpty) {
          await s.renameBridge(b.id, newName.trim());
        }
        break;
      case 'token':
        await _showTokenDialog(b);
        break;
      case 'delete':
        final confirm = await showDialog<bool>(context: context,
            builder: (c) => AlertDialog(
              title: Text('Eliminare la bridge?'.tr(context)),
              content: Text(
                '${'Eliminerai '.tr(context)}"${b.name}" '
                '(${b.host}:${b.port}). '
                '${'L\'azione non si può annullare.'.tr(context)}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text('Annulla'.tr(context))),
                TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: T.err(context)),
                    onPressed: () => Navigator.pop(c, true),
                    child: Text('Elimina'.tr(context))),
              ],
            ));
        if (confirm == true) {
          await s.removeBridge(b.id);
        }
        break;
    }
  }

  Future<String?> _promptText({required String title, String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text('Annulla'.tr(context))),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text),
                child: Text('OK'.tr(context))),
          ],
        ));
  }

  Future<void> _showTokenDialog(BridgeConnection b) async {
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(b.name),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Host: ${b.host}:${b.port}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        const SizedBox(height: 10),
        Text('Token:'.tr(context),
            style: TextStyle(color: T.muted(context), fontSize: 11)),
        const SizedBox(height: 4),
        SelectableText(b.token,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ]),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text('Copia token'.tr(context)),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: b.token));
            if (mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('Token copiato'.tr(context)),
                  duration: const Duration(seconds: 2)));
            }
          },
        ),
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('Chiudi'.tr(context))),
      ],
    ));
  }

  Future<void> _addBridge() async {
    // Dialog di scelta: QR scan o manuale
    final choice = await showDialog<String>(context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Aggiungi bridge'.tr(context)),
          content: Text(
              'Come vuoi aggiungere il Raspberry?'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text('Annulla'.tr(context))),
            TextButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 16),
              label: Text('Scansiona QR'.tr(context)),
              onPressed: () => Navigator.pop(ctx, 'qr'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.keyboard, size: 16),
              label: Text('Manuale'.tr(context)),
              onPressed: () => Navigator.pop(ctx, 'manual'),
            ),
          ],
        ));
    if (choice == null || !mounted) return;
    if (choice == 'qr') {
      final r = await Navigator.push<ScannedConfig>(context,
          MaterialPageRoute(builder: (_) => const QrScanScreen()));
      if (r == null || !mounted) return;
      await _saveNewBridge(r.host, r.port, r.token);
    } else {
      await _manualAddDialog();
    }
  }

  Future<void> _manualAddDialog() async {
    final nameCtl = TextEditingController();
    final hostCtl = TextEditingController();
    final portCtl = TextEditingController(text: '8765');
    final tokCtl = TextEditingController();
    final saved = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Aggiungi bridge'.tr(context)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
              children: [
            TextField(controller: nameCtl,
                decoration: InputDecoration(
                    labelText: 'Nome'.tr(context), hintText: 'EQ8 / Askar')),
            const SizedBox(height: 10),
            TextField(controller: hostCtl, keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: 'Host (Tailscale IP)'.tr(context),
                    hintText: 'es. 100.x.y.z')),
            const SizedBox(height: 10),
            TextField(controller: portCtl, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Porta'.tr(context))),
            const SizedBox(height: 10),
            TextField(controller: tokCtl, obscureText: true,
                decoration: InputDecoration(labelText: 'Token'.tr(context))),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text('Annulla'.tr(context))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text('Salva'.tr(context))),
          ],
        ));
    if (saved != true || !mounted) return;
    final host = hostCtl.text.trim();
    final port = int.tryParse(portCtl.text.trim()) ?? 8765;
    final tok = tokCtl.text.trim();
    final name = nameCtl.text.trim();
    if (host.isEmpty || tok.isEmpty) {
      showSnack(context, 'Host e token sono obbligatori'.tr(context),
          error: true);
      return;
    }
    await _saveNewBridge(host, port, tok, suggestedName: name);
  }

  Future<void> _saveNewBridge(String host, int port, String token,
      {String? suggestedName}) async {
    // Chiede un nome se non fornito
    String name = (suggestedName ?? '').trim();
    if (name.isEmpty) {
      final entered = await _promptText(
        title: 'Nome della bridge'.tr(context),
        initial: host,
      );
      if (entered == null || entered.trim().isEmpty) return;
      name = entered.trim();
    }
    if (!mounted) return;
    final s = context.read<AppState>();
    await s.addBridge(name: name, host: host, port: port, token: token);
    if (mounted) {
      showSnack(context, '${'Bridge aggiunta: '.tr(context)}$name');
    }
  }
}
