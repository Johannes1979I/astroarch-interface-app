import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import 'folder_browser_screen.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _diskUsage;
  bool _loading = false;
  final Set<String> _selected = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    setState(() => _loading = true);
    try {
      _data = await s.api!.filesRecent(limit: 100);
      _diskUsage = await s.api!.filesDiskUsage();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
      _selectionMode = _selected.isNotEmpty;
    });
  }

  void _selectAll() {
    final items = (_data?['items'] as List? ?? []);
    setState(() {
      _selected.clear();
      for (final i in items) {
        _selected.add((i as Map)['path']);
      }
      _selectionMode = _selected.isNotEmpty;
    });
  }

  void _exitSelection() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    final s = context.read<AppState>();
    if (s.api == null || _selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      backgroundColor: T.panel(context),
      title: Text('${'Cancella '.tr(context)}$n ${'file?'.tr(context)}'),
      content: Text(n == 1
          ? 'Il file FITS verrà cancellato definitivamente dal Raspberry Pi.\n\nQuesta azione non è reversibile.'.tr(context)
          : '${'I '.tr(context)}$n ${'file FITS verranno cancellati definitivamente dal Raspberry Pi.\n\nQuesta azione non è reversibile.'.tr(context)}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false),
            child: Text('ANNULLA'.tr(context))),
        ElevatedButton(
          onPressed: () => Navigator.pop(c, true),
          style: ElevatedButton.styleFrom(backgroundColor: T.err(context)),
          child: Text('CANCELLA'.tr(context), style: const TextStyle(color: Colors.white)),
        ),
      ],
    ));
    if (ok != true) return;
    try {
      final r = await s.api!.filesDeleteMany(_selected.toList());
      final freed = ((r['freed_bytes'] as num?)?.toDouble() ?? 0) / 1024 / 1024;
      if (mounted) {
        showSnack(context, '${'Cancellati '.tr(context)}${r['deleted_count']} ${'file (liberati '.tr(context)}${freed.toStringAsFixed(1)} MB)');
      }
      _exitSelection();
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  Future<void> _deleteSingle(String path, String name) async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      backgroundColor: T.panel(context),
      title: Text('Cancella file?'.tr(context)),
      content: Text('$name ${'sarà cancellato definitivamente.'.tr(context)}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false),
            child: Text('ANNULLA'.tr(context))),
        ElevatedButton(
          onPressed: () => Navigator.pop(c, true),
          style: ElevatedButton.styleFrom(backgroundColor: T.err(context)),
          child: Text('CANCELLA'.tr(context), style: const TextStyle(color: Colors.white)),
        ),
      ],
    ));
    if (ok != true) return;
    try {
      await s.api!.fileDelete(path);
      if (mounted) showSnack(context, '${'Cancellato '.tr(context)}$name');
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (_data?['items'] as List? ?? []).cast<Map>();
    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelection)
            : Builder(builder: (c) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(c).openDrawer())),
        title: _selectionMode
            ? Text('${_selected.length} ${'selezionati'.tr(context)}')
            : Text('Files'.tr(context)),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Seleziona tutti'.tr(context),
                  onPressed: _selectAll,
                ),
                IconButton(
                  icon: Icon(Icons.delete_forever, color: T.err(context)),
                  tooltip: 'Cancella selezionati'.tr(context),
                  onPressed: _deleteSelected,
                ),
              ]
            : [
                // v0.2.48 (P5): naviga le cartelle sul Pi (richiesto da Tucniak)
                IconButton(
                  tooltip: 'Sfoglia cartelle'.tr(context),
                  icon: const Icon(Icons.folder_open),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const FolderBrowserScreen(exts: 'fits,fit,esq'))),
                ),
                IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
              ],
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: items.isEmpty
                  ? AdaptiveListView(kind: ContentKind.form, children: [
                      _diskInfoCard(),
                      Padding(padding: const EdgeInsets.all(40),
                          child: Text('${'Nessun FITS in '.tr(context)}${_data?['base'] ?? 'dir'}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: T.muted(context)))),
                    ])
                  : AdaptiveListView.separated(
                      kind: ContentKind.form,
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
                      itemCount: items.length + 1,
                      separatorBuilder: (_, __) => Divider(height: 1, color: T.line(context)),
                      itemBuilder: (c, i) {
                        if (i == 0) return _diskInfoCard();
                        return _FileRow(
                          item: items[i - 1],
                          selected: _selected.contains(items[i - 1]['path']),
                          selectionMode: _selectionMode,
                          onTap: () {
                            if (_selectionMode) {
                              _toggleSelection(items[i - 1]['path']);
                            } else {
                              Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => _PreviewScreen(
                                      path: items[i - 1]['path'],
                                      name: items[i - 1]['name'])));
                            }
                          },
                          onLongPress: () =>
                              _toggleSelection(items[i - 1]['path']),
                          onDelete: () => _deleteSingle(
                              items[i - 1]['path'], items[i - 1]['name']),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _diskInfoCard() {
    final d = _diskUsage;
    if (d == null || d['error'] != null) return const SizedBox(height: 4);
    final total = (d['total_bytes'] as num).toDouble();
    final free = (d['free_bytes'] as num).toDouble();
    final used = total - free;
    final imagesUsed = ((d['images_dir_bytes'] as num?) ?? 0).toDouble();
    final filesCount = (d['images_files_count'] as num?) ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.sd_card, size: 14, color: T.muted(context)),
          const SizedBox(width: 6),
          Text('STORAGE RPi'.tr(context),
              style: TextStyle(color: T.muted(context),
                  fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('$filesCount FITS · ${(imagesUsed / 1024 / 1024 / 1024).toStringAsFixed(2)} GB',
              style: TextStyle(color: T.muted(context),
                  fontFamily: 'monospace', fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : used / total,
            minHeight: 5,
            backgroundColor: T.line(context),
            color: used / total > 0.85 ? T.err(context)
                : used / total > 0.7 ? T.warn(context) : T.accent(context),
          ),
        ),
        const SizedBox(height: 4),
        Text('${(used / 1024 / 1024 / 1024).toStringAsFixed(1)} / '
             '${(total / 1024 / 1024 / 1024).toStringAsFixed(1)} GB · '
             '${'libero '.tr(context)}${(free / 1024 / 1024 / 1024).toStringAsFixed(1)} GB',
            style: TextStyle(color: T.muted(context),
                fontFamily: 'monospace', fontSize: 10)),
      ]),
    );
  }
}

class _FileRow extends StatefulWidget {
  final Map item;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  const _FileRow({
    required this.item, required this.selected, required this.selectionMode,
    required this.onTap, required this.onLongPress, required this.onDelete,
  });
  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  Uint8List? _thumb;

  @override
  void initState() { super.initState(); _loadThumb(); }

  Future<void> _loadThumb() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      _thumb = await s.api!.filePreview(widget.item['path'], thumbnail: true);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = ((widget.item['size'] as num?)?.toDouble() ?? 0) / 1024 / 1024;
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        color: widget.selected
            ? T.accent(context).withValues(alpha: 0.18)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(children: [
            if (widget.selectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  widget.selected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: widget.selected ? T.accent(context) : T.muted(context),
                  size: 22,
                ),
              ),
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: T.line(context)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _thumb == null
                  ? Icon(Icons.image, color: T.muted(context), size: 18)
                  : Image.memory(_thumb!, fit: BoxFit.cover, gaplessPlayback: true),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.item['name'],
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${widget.item['path']}',
                  style: TextStyle(color: T.muted(context), fontSize: 10),
                  overflow: TextOverflow.ellipsis),
            ])),
            Text('${size.toStringAsFixed(1)} MB',
                style: TextStyle(color: T.muted(context),
                    fontFamily: 'monospace', fontSize: 11)),
            if (!widget.selectionMode)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.delete_outline,
                    color: T.err(context).withValues(alpha: 0.7), size: 18),
                onPressed: widget.onDelete,
              ),
          ]),
        ),
      ),
    );
  }
}

class _PreviewScreen extends StatefulWidget {
  final String path; final String name;
  const _PreviewScreen({required this.path, required this.name});
  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  Uint8List? _img;
  String? _err;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      _img = await s.api!.filePreview(widget.path);
    } catch (e) { _err = '$e'; }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _delete() async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      backgroundColor: T.panel(context),
      title: Text('Cancella file?'.tr(context)),
      content: Text('${widget.name} ${'sarà cancellato definitivamente dal RPi.'.tr(context)}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('ANNULLA'.tr(context))),
        ElevatedButton(
          onPressed: () => Navigator.pop(c, true),
          style: ElevatedButton.styleFrom(backgroundColor: T.err(context)),
          child: Text('CANCELLA'.tr(context), style: const TextStyle(color: Colors.white)),
        ),
      ],
    ));
    if (ok != true) return;
    try {
      await s.api!.fileDelete(widget.path);
      if (mounted) {
        showSnack(context, 'Cancellato'.tr(context));
        Navigator.pop(context, true); // ritorna true per refresh
      }
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: T.err(context)),
            onPressed: _delete,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!, style: TextStyle(color: T.err(context))))
              : InteractiveViewer(
                  minScale: 1, maxScale: 5,
                  child: Container(color: Colors.black,
                      child: Center(child: Image.memory(_img!, fit: BoxFit.contain))),
                ),
    );
  }
}
