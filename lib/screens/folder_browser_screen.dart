import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Navigatore di cartelle sul Pi (v0.2.48, richiesto da Tucniak).
/// Usa /api/files/browse + /api/files/roots. Confinato nella home utente
/// (lato bridge). Opzionalmente filtra per estensioni e permette di
/// "scegliere" la cartella corrente via callback [onPickFolder].
class FolderBrowserScreen extends StatefulWidget {
  /// Se fornito, mostra un pulsante "Usa questa cartella" che ritorna il path.
  final void Function(String path)? onPickFolder;
  /// Filtro estensioni file, es. 'fits,esq' (vuoto = tutti).
  final String exts;
  final String title;
  const FolderBrowserScreen({super.key, this.onPickFolder, this.exts = '', this.title = ''});

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  String _path = '';
  Map<String, dynamic>? _data;
  List<dynamic> _roots = [];
  bool _loading = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadRoots();
    _browse('');
  }

  Future<void> _loadRoots() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final r = await s.api!.filesRoots();
      if (mounted) setState(() => _roots = (r['roots'] as List?) ?? []);
    } catch (_) {}
  }

  Future<void> _browse(String path) async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    setState(() { _loading = true; _err = null; });
    try {
      final r = await s.api!.filesBrowse(path: path, exts: widget.exts);
      if (mounted) setState(() { _data = r; _path = r['path'] ?? path; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.body);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirs = (_data?['dirs'] as List?) ?? [];
    final files = (_data?['files'] as List?) ?? [];
    final parent = _data?['parent'];
    final canUp = parent != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isNotEmpty ? widget.title : 'Sfoglia cartelle'.tr(context)),
        actions: [
          if (widget.onPickFolder != null)
            TextButton.icon(
              icon: Icon(Icons.check, color: T.accent(context)),
              label: Text('USA QUESTA'.tr(context),
                  style: TextStyle(color: T.accent(context), fontWeight: FontWeight.w700)),
              onPressed: () => widget.onPickFolder!(_path),
            ),
        ],
      ),
      body: Column(children: [
        // shortcut roots
        if (_roots.isNotEmpty)
          SizedBox(height: 44, child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: [
              for (final r in _roots)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: Icon(Icons.bookmark, size: 15, color: T.accent(context)),
                    label: Text(r['label'] ?? ''),
                    onPressed: () => _browse(r['path'] ?? ''),
                  ),
                ),
            ],
          )),
        // breadcrumb / path corrente
        Container(
          width: double.infinity,
          color: T.panel(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(Icons.folder_open, size: 16, color: T.muted(context)),
            const SizedBox(width: 8),
            Expanded(child: Text('~/${_path.isEmpty ? "" : _path}',
                style: TextStyle(color: T.text(context), fontSize: 12, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis)),
          ]),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _err != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Text(_err!, textAlign: TextAlign.center,
                      style: TextStyle(color: T.muted(context)))))
              : ListView(children: [
                  if (canUp)
                    ListTile(
                      leading: Icon(Icons.arrow_upward, color: T.muted(context)),
                      title: Text('..'.tr(context)),
                      onTap: () => _browse(parent),
                      dense: true,
                    ),
                  for (final d in dirs)
                    ListTile(
                      leading: Icon(Icons.folder, color: T.accent(context)),
                      title: Text(d['name'] ?? ''),
                      trailing: Icon(Icons.chevron_right, color: T.muted(context)),
                      onTap: () => _browse(d['path'] ?? ''),
                      dense: true,
                    ),
                  for (final f in files)
                    ListTile(
                      leading: Icon(_iconFor(f['name'] ?? ''), color: T.muted(context)),
                      title: Text(f['name'] ?? ''),
                      subtitle: Text(_fmtSize((f['size'] as num?)?.toInt() ?? 0),
                          style: TextStyle(color: T.muted(context), fontSize: 11)),
                      dense: true,
                    ),
                  if (dirs.isEmpty && files.isEmpty && !_loading)
                    Padding(padding: const EdgeInsets.all(24),
                        child: Center(child: Text('Cartella vuota'.tr(context),
                            style: TextStyle(color: T.muted(context))))),
                ]),
        ),
      ]),
    );
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.fits') || n.endsWith('.fit')) return Icons.image_outlined;
    if (n.endsWith('.esq')) return Icons.queue_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _fmtSize(int b) {
    if (b > 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
    if (b > 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b > 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
    return '$b B';
  }
}
