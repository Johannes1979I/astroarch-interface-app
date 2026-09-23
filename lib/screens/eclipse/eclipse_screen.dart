import 'package:flutter/material.dart';
import '../../i18n/strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../api/api_client.dart';
import '../../state/app_state.dart';
import '../../eclipse/eclipse_optimizer.dart';
import '../../eclipse/eclipse_planner.dart';
import '../../eclipse/eclipse_db.dart';
import 'eclipse_live_view.dart';

/// Sezione Eclissi — pianificazione (Fase 2, punto 1).
///
/// Pianificatore in-app autosufficiente: scegli le feature da fotografare,
/// la camera/ottica e la durata della totalità → l'app calcola i bracket
/// (Espenak, scalati sull'equipment) e la timeline, verificando che stia nel
/// tempo. Gira offline; l'esecuzione live (fire scatti) sarà la Fase 3 (bridge).
class EclipseScreen extends StatefulWidget {
  const EclipseScreen({super.key});
  @override
  State<EclipseScreen> createState() => _EclipseScreenState();
}

class _EclipseScreenState extends State<EclipseScreen> {
  // Feature selezionate (default: totalità completa senza parziale).
  final Set<EclipseFeature> _features = {
    EclipseFeature.baily,
    EclipseFeature.chromosphere,
    EclipseFeature.prominences,
    EclipseFeature.innerCorona,
    EclipseFeature.midCorona,
    EclipseFeature.outerCorona,
  };

  String _camType = 'cmos';
  String _sensor = 'IMX571';
  String _manufacturer = 'ToupTek';
  String _preset = 'ToupTek 2600';

  final _fRatio = TextEditingController(text: '5.5');
  final _focalLen = TextEditingController(text: '400');
  final _pixel = TextEditingController(text: '3.76');
  final _unityGain = TextEditingController(text: '100');
  final _gain = TextEditingController(text: '100');
  final _iso = TextEditingController(text: '400');
  final _totalitySec = TextEditingController(text: '120');
  final _shots = TextEditingController(text: '1');
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();

  EclipsePlan? _plan;
  bool _maximizeShots = false;

  // Tipo di eclissi: Sole (default) o Luna. Cambia DB, fasi, puntamento.
  EclipseKind _kind = EclipseKind.solar;
  bool get _isLunar => _kind == EclipseKind.lunar;

  // --- DB eclissi (bundlato) ---
  List<EclipseEvent> _eclipses = [];
  EclipseEvent? _selEclipse;
  EclipsePathPoint? _selPoint;
  // DB eclissi di LUNA (contatti calcolati dal bridge).
  List<LunarEclipseEvent> _lunarEclipses = [];
  LunarEclipseEvent? _selLunar;
  double? _selLat;
  double? _selLon;
  Map<String, dynamic>? _contacts; // dal bridge (astropy)
  bool _loadingContacts = false;
  bool _gpsBusy = false;
  String? _contactsError;

  @override
  void initState() {
    super.initState();
    loadEclipseDb().then((list) {
      if (mounted) setState(() => _eclipses = list);
    }).catchError((_) {});
    loadLunarEclipseDb().then((list) {
      if (mounted) setState(() => _lunarEclipses = list);
    }).catchError((_) {});
  }

  /// Cambia tipo eclissi (Sole/Luna): resetta selezione, contatti e imposta le
  /// fasi di default del nuovo tipo.
  void _setKind(EclipseKind k) => setState(() {
        _kind = k;
        _selEclipse = null;
        _selLunar = null;
        _selPoint = null;
        _contacts = null;
        _contactsError = null;
        _plan = null;
        _features
          ..clear()
          ..addAll(k == EclipseKind.lunar
              ? kLunarFeatures
              : const {
                  EclipseFeature.baily,
                  EclipseFeature.chromosphere,
                  EclipseFeature.prominences,
                  EclipseFeature.innerCorona,
                  EclipseFeature.midCorona,
                  EclipseFeature.outerCorona,
                });
      });

  @override
  void dispose() {
    for (final c in [_fRatio, _focalLen, _pixel, _unityGain, _gain, _iso, _totalitySec, _shots, _latCtrl, _lonCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c, double fb) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fb;
  int _i(TextEditingController c, int fb) => int.tryParse(c.text.trim()) ?? fb;

  void _applyPreset(String p) {
    setState(() {
      _preset = p;
      switch (p) {
        case 'ToupTek 2600':
          _camType = 'cmos';
          _sensor = 'IMX571';
          _manufacturer = 'ToupTek';
          _unityGain.text = '100';
          _pixel.text = '3.76';
        case 'CMOS generica':
          _camType = 'cmos';
          _sensor = '';
          _manufacturer = '';
          _unityGain.text = '120';
          _pixel.text = '3.76';
        case 'Reflex (DSLR)':
          _camType = 'dslr';
          _sensor = '';
          _manufacturer = '';
          _pixel.text = '4.3';
          _iso.text = '400';
      }
    });
  }

  void _setFeatures(Set<EclipseFeature> f) => setState(() {
        _features
          ..clear()
          ..addAll(f);
        _plan = null;
      });

  void _generate() {
    final cam = CameraSpec(
      type: _camType,
      unityGain: _d(_unityGain, 100),
      sensor: _sensor,
      manufacturer: _manufacturer,
      pixelSize: _d(_pixel, 3.76),
    );
    final scope = TelescopeSpec(fRatio: _d(_fRatio, 5.5), focalLength: _d(_focalLen, 400));
    final gain = _camType == 'cmos' ? _d(_gain, 100) : null;
    final iso = _camType == 'dslr' ? _d(_iso, 400) : null;
    final EclipsePlan plan;
    if (_isLunar) {
      // Eclissi di Luna: fasi lunghe, niente budget di totalità.
      plan = EclipsePlanner().buildLunar(
        features: _features,
        scope: scope,
        cam: cam,
        gain: gain,
        iso: iso,
        shotsPerExposure: _i(_shots, 1),
        maximizeShots: _maximizeShots,
      );
    } else {
      final totSec = _i(_totalitySec, 120);
      final c2 = DateTime(2027, 8, 2, 11, 0, 0);
      final contacts = EclipseContacts(c2: c2, c3: c2.add(Duration(seconds: totSec)));
      plan = EclipsePlanner().build(
        features: _features,
        contacts: contacts,
        scope: scope,
        cam: cam,
        gain: gain,
        iso: iso,
        shotsPerExposure: _i(_shots, 1),
        maximizeShots: _maximizeShots,
      );
    }
    setState(() => _plan = plan);
    showSnack(context, 'Piano generato'.tr(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Eclissi'.tr(context))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: [
          _kindSelector(context),
          const SizedBox(height: 8),
          _intro(context),
          _eclipseDbSection(context),
          SectionLabel(
              (_isLunar ? 'Fasi da fotografare' : 'Feature da fotografare').tr(context)),
          _featurePresets(context),
          const SizedBox(height: 8),
          _featureChips(context),
          SectionLabel('Camera e ottica'.tr(context)),
          _cameraSection(context),
          SectionLabel('Totalità'.tr(context)),
          _totalitySection(context),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Genera piano'.tr(context),
            icon: Icons.auto_awesome,
            onPressed: _features.isEmpty ? null : _generate,
          ),
          if (_plan != null) _resultSection(context, _plan!),
        ],
      ),
    );
  }

  Widget _kindSelector(BuildContext c) => Row(children: [
        Expanded(child: _kindBtn(c, EclipseKind.solar, '☀️ ${'Sole'.tr(c)}')),
        const SizedBox(width: 8),
        Expanded(child: _kindBtn(c, EclipseKind.lunar, '🌙 ${'Luna'.tr(c)}')),
      ]);

  Widget _kindBtn(BuildContext c, EclipseKind k, String label) {
    final sel = _kind == k;
    return InkWell(
      onTap: sel ? null : () => _setKind(k),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? T.accent(c).withValues(alpha: 0.18) : T.panel(c),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? T.accent(c) : T.line(c), width: sel ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, color: T.text(c), fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _intro(BuildContext c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: T.accent(c).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.accent(c).withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(Icons.brightness_3, color: T.accent(c), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pianifica i bracket per ogni dettaglio della totalità. I tempi sono calcolati con la guida Espenak e scalati sulla tua ottica/camera.'
                  .tr(c),
              style: TextStyle(fontSize: 12, color: T.text(c)),
            ),
          ),
        ]),
      );

  // ============ DB eclissi: dropdown + contatti ============
  Widget _eclipseDbSection(BuildContext c) {
    if (_isLunar) return _lunarDbSection(c);
    return Column(children: [
      SectionLabel('Carica eclissi'.tr(c)),
      _dropBox(c, DropdownButton<EclipseEvent>(
        value: _selEclipse,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: T.panel(c),
        hint: Text(_eclipses.isEmpty ? 'Caricamento…'.tr(c) : 'Scegli un\'eclissi'.tr(c),
            style: TextStyle(color: T.muted(c), fontSize: 13)),
        items: [
          for (final e in _eclipses)
            DropdownMenuItem(
              value: e,
              child: Text('${e.isTotal ? '🌑' : '🌓'} ${e.date} · ${e.name}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: T.text(c), fontSize: 13)),
            ),
        ],
        onChanged: (e) => e == null ? null : _selectEclipse(e),
      )),
      if (_selEclipse != null) ...[
        const SizedBox(height: 8),
        _dropBox(c, DropdownButton<EclipsePathPoint>(
          value: _selPoint,
          isExpanded: true,
          underline: const SizedBox(),
          dropdownColor: T.panel(c),
          hint: Text('Scegli la località (durata)'.tr(c),
              style: TextStyle(color: T.muted(c), fontSize: 13)),
          items: [
            for (final p in _selEclipse!.path)
              DropdownMenuItem(
                value: p,
                child: Text('${p.location} — ${p.duration}s',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: T.text(c), fontSize: 13)),
              ),
          ],
          onChanged: (p) => p == null ? null : _selectPoint(p),
        )),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _numField(c, 'Lat', _latCtrl)),
          const SizedBox(width: 10),
          Expanded(child: _numField(c, 'Lon', _lonCtrl)),
        ]),
        const SizedBox(height: 8),
        GhostButton(
          label: _gpsBusy ? 'GPS…'.tr(c) : 'Usa il mio GPS'.tr(c),
          icon: Icons.my_location,
          small: true,
          onPressed: _gpsBusy ? null : _useGps,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Scegli una località dal percorso, inserisci il TUO GPS, o usa la posizione del telefono. Malaga città non è tra i punti: al bordo nord la totalità è breve (~115s) — spostati a sud per più minuti.'
                .tr(c),
            style: TextStyle(fontSize: 10.5, color: T.muted(c)),
          ),
        ),
        const SizedBox(height: 8),
        _eclipseInfo(c),
      ],
    ]);
  }

  String _lunarEmoji(String type) =>
      type == 'total' ? '🔴' : (type == 'partial' ? '🌗' : '🌘');

  // ============ DB eclissi di LUNA (contatti universali + visibilità) ============
  Widget _lunarDbSection(BuildContext c) {
    return Column(children: [
      SectionLabel('Carica eclissi di Luna'.tr(c)),
      _dropBox(c, DropdownButton<LunarEclipseEvent>(
        value: _selLunar,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: T.panel(c),
        hint: Text(
            _lunarEclipses.isEmpty
                ? 'Caricamento…'.tr(c)
                : 'Scegli un\'eclissi di Luna'.tr(c),
            style: TextStyle(color: T.muted(c), fontSize: 13)),
        items: [
          for (final e in _lunarEclipses)
            DropdownMenuItem(
              value: e,
              child: Text('${_lunarEmoji(e.type)} ${e.date} · ${e.name}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: T.text(c), fontSize: 13)),
            ),
        ],
        onChanged: (e) => e == null ? null : _selectLunar(e),
      )),
      if (_selLunar != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _numField(c, 'Lat', _latCtrl)),
          const SizedBox(width: 10),
          Expanded(child: _numField(c, 'Lon', _lonCtrl)),
        ]),
        const SizedBox(height: 8),
        GhostButton(
          label: _gpsBusy ? 'GPS…'.tr(c) : 'Usa il mio GPS'.tr(c),
          icon: Icons.my_location,
          small: true,
          onPressed: _gpsBusy ? null : _useGps,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Le eclissi di Luna si vedono da tutto l\'emisfero notturno: gli orari sono universali, conta solo se la Luna è sopra il tuo orizzonte.'
                .tr(c),
            style: TextStyle(fontSize: 10.5, color: T.muted(c)),
          ),
        ),
        const SizedBox(height: 8),
        _lunarInfo(c),
      ],
    ]);
  }

  void _selectLunar(LunarEclipseEvent e) => setState(() {
        _selLunar = e;
        _selLat = null;
        _selLon = null;
        _contacts = null;
        _contactsError = null;
        _plan = null;
      });

  Widget _lunarInfo(BuildContext c) {
    final e = _selLunar!;
    final typeIt = e.isTotal
        ? 'Totale'
        : (e.isPartial ? 'Parziale' : 'Penombrale');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.accent(c).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.accent(c).withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📅 ${e.date} · ${typeIt.tr(c)} · mag ${e.magnitude}',
            style: TextStyle(
                fontSize: 12.5, color: T.text(c), fontWeight: FontWeight.w600)),
        if (e.geTime != null)
          Text('🕑 ${'Ora max (generale)'.tr(c)}: ${e.geTime}',
              style: TextStyle(fontSize: 10.5, color: T.muted(c))),
        const SizedBox(height: 10),
        GhostButton(
          label: 'Calcola contatti + visibilità (P1–P4)'.tr(c),
          icon: Icons.schedule,
          small: true,
          onPressed: _loadingContacts ? null : _calcContacts,
        ),
        if (_loadingContacts)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: T.accent(c))),
              const SizedBox(width: 8),
              Text('Calcolo con astropy…'.tr(c),
                  style: TextStyle(fontSize: 11, color: T.muted(c))),
            ]),
          ),
        if (_contactsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${'Errore: '.tr(c)}$_contactsError',
                style: TextStyle(fontSize: 11, color: T.err(c))),
          ),
        if (_contacts != null) _contactsView(c, _contacts!),
      ]),
    );
  }

  /// Legge la posizione dal GPS del telefono e (se un'eclissi è selezionata)
  /// calcola in automatico contatti e durata per quel punto.
  Future<void> _useGps() async {
    setState(() {
      _gpsBusy = true;
      _contactsError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _contactsError = 'GPS spento sul telefono'.tr(context));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _contactsError = 'Permesso posizione negato'.tr(context));
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      _latCtrl.text = pos.latitude.toStringAsFixed(4);
      _lonCtrl.text = pos.longitude.toStringAsFixed(4);
      // Il GPS ha priorità: ignora la città scelta dal dropdown.
      setState(() => _selPoint = null);
      if (_selEclipse != null || _selLunar != null) await _calcContacts();
    } catch (e) {
      if (mounted) setState(() => _contactsError = 'GPS: $e');
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  Widget _dropBox(BuildContext c, Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: T.panel(c),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(c)),
        ),
        child: child,
      );

  Widget _eclipseInfo(BuildContext c) {
    final e = _selEclipse!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.accent(c).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.accent(c).withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📅 ${e.date} · ${e.isTotal ? 'Totale' : 'Anulare'} · mag ${e.magnitude}',
            style: TextStyle(fontSize: 12.5, color: T.text(c), fontWeight: FontWeight.w600)),
        if (e.geTime != null)
          Text('🕑 ${'Ora max (generale)'.tr(c)}: ${e.geTime}  ·  ${'ora locale dai contatti'.tr(c)}',
              style: TextStyle(fontSize: 10.5, color: T.muted(c))),
        if (_selPoint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
                '${_selPoint!.location} — ${_selPoint!.duration}s  (${_selLat!.toStringAsFixed(2)}, ${_selLon!.toStringAsFixed(2)})',
                style: TextStyle(fontSize: 11, color: T.muted(c))),
          ),
        const SizedBox(height: 10),
        GhostButton(
          label: 'Calcola contatti dal bridge (C1–C4 + Sole)'.tr(c),
          icon: Icons.schedule,
          small: true,
          onPressed: _loadingContacts ? null : _calcContacts,
        ),
        if (_loadingContacts)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: T.accent(c))),
              const SizedBox(width: 8),
              Text('Calcolo con astropy…'.tr(c), style: TextStyle(fontSize: 11, color: T.muted(c))),
            ]),
          ),
        if (_contactsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${'Errore: '.tr(c)}$_contactsError',
                style: TextStyle(fontSize: 11, color: T.err(c))),
          ),
        if (_contacts != null) _contactsView(c, _contacts!),
      ]),
    );
  }

  Widget _contactsView(BuildContext c, Map<String, dynamic> j) {
    if (_isLunar) return _lunarContactsView(c, j);
    if (j['visible'] == false) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Eclissi non visibile da questa posizione.'.tr(c),
            style: TextStyle(fontSize: 12, color: T.err(c), fontWeight: FontWeight.w600)),
      );
    }
    String t(String k) => (j[k] as String?) ?? '—';
    final sun = (j['sun'] as Map?)?.cast<String, dynamic>();
    final isTotal = (j['type'] as String?) == 'total';
    final cov = (j['coverage_pct'] as num?)?.toDouble();
    final mono = TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: T.text(c));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!isTotal)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: T.warn(c).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: T.warn(c).withValues(alpha: 0.5)),
            ),
            child: Text(
              '⚠️ ${'Qui NON sei in totalità'.tr(c)}${cov != null ? ' — ${'copertura max'.tr(c)} ${cov.toStringAsFixed(1)}%' : ''}. ${'Piano impostato per la fase parziale (filtro).'.tr(c)}',
              style: TextStyle(fontSize: 11.5, color: T.text(c), fontWeight: FontWeight.w600),
            ),
          ),
        Text('C1: ${t('c1')}', style: mono),
        if (isTotal) Text('C2: ${t('c2')}', style: mono),
        Text('${'Max'.tr(c)}: ${t('max')}', style: mono),
        if (isTotal) Text('C3: ${t('c3')}', style: mono),
        Text('C4: ${t('c4')}', style: mono),
        if (isTotal && j['totality_sec'] != null)
          Text('${'Totalità'.tr(c)}: ${j['totality_sec']}s',
              style: TextStyle(fontSize: 11.5, color: T.text(c), fontWeight: FontWeight.w600)),
        if (!isTotal && cov != null)
          Text('${'Copertura massima'.tr(c)}: ${cov.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 11.5, color: T.text(c), fontWeight: FontWeight.w600)),
        if (sun != null)
          Text('Sole @ max: alt ${(sun['alt'] as num?)?.toStringAsFixed(1) ?? '—'}° · az ${(sun['az'] as num?)?.toStringAsFixed(1) ?? '—'}°',
              style: TextStyle(fontSize: 11, color: T.muted(c))),
      ]),
    );
  }

  Widget _lunarContactsView(BuildContext c, Map<String, dynamic> j) {
    String t(String k) => (j[k] as String?) ?? '—';
    final moon = (j['moon'] as Map?)?.cast<String, dynamic>();
    final type = (j['type'] as String?) ?? 'penumbral';
    final visible = j['visible'] == true;
    final isTotal = type == 'total';
    final isPartial = type == 'partial' || isTotal;
    final mono = TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: T.text(c));
    final totSec = (j['totality_sec'] as num?)?.toInt();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!visible)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: T.warn(c).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: T.warn(c).withValues(alpha: 0.5)),
            ),
            child: Text(
              '⚠️ ${'Al massimo la Luna è sotto l\'orizzonte da qui'.tr(c)} (${'orari universali UT'.tr(c)}).',
              style: TextStyle(
                  fontSize: 11.5, color: T.text(c), fontWeight: FontWeight.w600),
            ),
          ),
        Text('P1 penombra:  ${t('p1')}', style: mono),
        if (isPartial) Text('U1 parziale:  ${t('u1')}', style: mono),
        if (isTotal) Text('U2 totale:    ${t('u2')}', style: mono),
        Text('${'Max'.tr(c)}:          ${t('max')}', style: mono),
        if (isTotal) Text('U3 fine tot.: ${t('u3')}', style: mono),
        if (isPartial) Text('U4 fine parz.:${t('u4')}', style: mono),
        Text('P4 fine pen.: ${t('p4')}', style: mono),
        if (isTotal && totSec != null)
          Text('${'Totalità'.tr(c)}: ${(totSec / 60).round()} min',
              style: TextStyle(
                  fontSize: 11.5, color: T.text(c), fontWeight: FontWeight.w600)),
        Text('${'Magnitudine umbrale'.tr(c)}: ${j['umbral_magnitude'] ?? '—'}',
            style: TextStyle(fontSize: 11, color: T.muted(c))),
        if (moon != null)
          Text(
              'Luna @ max: alt ${(moon['alt'] as num?)?.toStringAsFixed(1) ?? '—'}° · az ${(moon['az'] as num?)?.toStringAsFixed(1) ?? '—'}°',
              style: TextStyle(fontSize: 11, color: T.muted(c))),
      ]),
    );
  }

  void _selectEclipse(EclipseEvent e) => setState(() {
        _selEclipse = e;
        _selPoint = null;
        _selLat = null;
        _selLon = null;
        _contacts = null;
        _contactsError = null;
        _plan = null;
      });

  void _selectPoint(EclipsePathPoint p) => setState(() {
        _selPoint = p;
        _selLat = p.lat;
        _selLon = p.lon;
        _latCtrl.text = p.lat.toStringAsFixed(4);
        _lonCtrl.text = p.lon.toStringAsFixed(4);
        if (p.duration > 0) _totalitySec.text = '${p.duration}';
        _contacts = null;
        _contactsError = null;
        _plan = null;
      });

  Future<void> _calcContacts() async {
    final s = context.read<AppState>();
    if (s.api == null) {
      setState(() => _contactsError = 'Bridge non connesso'.tr(context));
      return;
    }
    final lat = double.tryParse(_latCtrl.text.trim().replaceAll(',', '.'));
    final lon = double.tryParse(_lonCtrl.text.trim().replaceAll(',', '.'));
    final date = _isLunar ? _selLunar?.date : _selEclipse?.date;
    if (date == null || lat == null || lon == null) {
      setState(() => _contactsError = 'Seleziona eclissi e inserisci lat/lon'.tr(context));
      return;
    }
    _selLat = lat;
    _selLon = lon;
    setState(() {
      _loadingContacts = true;
      _contactsError = null;
    });
    try {
      final r = await s.api!.eclipseContacts(
          date: date, lat: lat, lon: lon, kind: _isLunar ? 'lunar' : 'solar');
      if (mounted) {
        setState(() {
          _contacts = r;
          final ts = r['totality_sec'];
          if (ts is num && ts > 0) _totalitySec.text = '${ts.round()}';
          // Solo Sole: se il punto NON è in totalità → piano per la fase parziale.
          if (!_isLunar && (r['type'] as String?) != 'total') {
            _features
              ..clear()
              ..add(EclipseFeature.partial);
          }
          _plan = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _contactsError = e.body);
    } catch (e) {
      if (mounted) setState(() => _contactsError = '$e');
    } finally {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  Widget _featurePresets(BuildContext c) {
    if (_isLunar) {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        _presetChip(c, 'Tutte le fasi'.tr(c),
            () => _setFeatures(kLunarFeatures.toSet())),
        _presetChip(c, 'Solo totale (Luna rossa)'.tr(c),
            () => _setFeatures({EclipseFeature.lunarTotal})),
      ]);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
        _presetChip(c, 'Totalità completa'.tr(c), () => _setFeatures({
              EclipseFeature.baily,
              EclipseFeature.chromosphere,
              EclipseFeature.prominences,
              EclipseFeature.innerCorona,
              EclipseFeature.midCorona,
              EclipseFeature.outerCorona,
            })),
        _presetChip(c, 'Solo corona'.tr(c), () => _setFeatures({
              EclipseFeature.innerCorona,
              EclipseFeature.midCorona,
              EclipseFeature.outerCorona,
            })),
        _presetChip(c, 'Momenti chiave'.tr(c), () => _setFeatures({
              EclipseFeature.baily,
              EclipseFeature.chromosphere,
              EclipseFeature.innerCorona,
              EclipseFeature.midCorona,
              EclipseFeature.outerCorona,
            })),
      ]);
  }

  Widget _presetChip(BuildContext c, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: T.panel(c),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: T.line(c)),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, color: T.text(c), fontWeight: FontWeight.w600)),
        ),
      );

  Widget _featureChips(BuildContext c) {
    // Ordine cronologico. Luna: penombra/parziale/totale. Sole: parziale + totalità.
    final order = _isLunar
        ? kLunarFeatures
        : const [
            EclipseFeature.partial,
            EclipseFeature.baily,
            EclipseFeature.chromosphere,
            EclipseFeature.prominences,
            EclipseFeature.innerCorona,
            EclipseFeature.midCorona,
            EclipseFeature.outerCorona,
          ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in order)
          ChipToggle(
            label: f.labelIt,
            selected: _features.contains(f),
            onTap: () => setState(() {
              _features.contains(f) ? _features.remove(f) : _features.add(f);
              _plan = null;
            }),
          ),
      ],
    );
  }

  Widget _cameraSection(BuildContext c) => Column(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in ['ToupTek 2600', 'CMOS generica', 'Reflex (DSLR)'])
            ChipToggle(label: p, selected: _preset == p, onTap: () => _applyPreset(p)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _numField(c, 'Rapporto f/'.tr(c), _fRatio)),
          const SizedBox(width: 10),
          Expanded(child: _numField(c, 'Focale (mm)'.tr(c), _focalLen)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _numField(c, 'Pixel (µm)'.tr(c), _pixel)),
          const SizedBox(width: 10),
          Expanded(
            child: _camType == 'cmos'
                ? _numField(c, 'Gain', _gain)
                : _numField(c, 'ISO', _iso),
          ),
        ]),
        if (_camType == 'cmos') ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField(c, 'Unity gain'.tr(c), _unityGain)),
            const SizedBox(width: 10),
            const Expanded(child: SizedBox()),
          ]),
        ],
      ]);

  Widget _totalitySection(BuildContext c) => Column(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in [60, 120, 180, 240])
            _presetChip(c, '${s}s', () => setState(() {
                  _totalitySec.text = '$s';
                  _plan = null;
                })),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _numField(c, 'Durata totalità (s)'.tr(c), _totalitySec)),
          const SizedBox(width: 10),
          Expanded(
            child: _maximizeShots
                ? const SizedBox()
                : _numField(c, 'Scatti per posa'.tr(c), _shots),
          ),
        ]),
        const SizedBox(height: 10),
        ChipToggle(
          label: 'Massimizza scatti (riempi il tempo)'.tr(c),
          selected: _maximizeShots,
          onTap: () => setState(() {
            _maximizeShots = !_maximizeShots;
            _plan = null;
          }),
        ),
        const SizedBox(height: 6),
        Text(
          _maximizeShots
              ? 'Ogni fase riceve il massimo numero di scatti che entra nel tempo (più frame = più segnale da impilare). Baily/cromosfera restano limitate perché durano pochi secondi.'
                  .tr(c)
              : 'Suggerimento: prendi la durata esatta della totalità dal tuo GPS in Eclipse Commander.'
                  .tr(c),
          style: TextStyle(fontSize: 10.5, color: T.muted(c)),
        ),
      ]);

  Widget _numField(BuildContext c, String label, TextEditingController ctrl) => TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(color: T.text(c), fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: T.muted(c), fontSize: 12),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: T.line(c)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: T.accent(c)),
          ),
        ),
      );

  Widget _resultSection(BuildContext c, EclipsePlan plan) {
    final fits = plan.fits;
    final banner = Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (fits ? T.ok(c) : T.err(c)).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (fits ? T.ok(c) : T.err(c)).withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(fits ? Icons.check_circle : Icons.error, color: fits ? T.ok(c) : T.err(c), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            fits
                ? '${'Sta nella totalità.'.tr(c)} ${'Margine'.tr(c)} ${plan.marginSeconds}s'
                : '${'Sfora di'.tr(c)} ${plan.overrunSeconds}s',
            style: TextStyle(fontSize: 13, color: T.text(c), fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      banner,
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: StatusCard(
          header: 'Frame totalità'.tr(c),
          value: '${plan.totalityFrames}',
          subtitle: '${plan.totalityBlocks.length} ${'blocchi'.tr(c)}',
          leading: Icons.burst_mode,
        )),
        const SizedBox(width: 8),
        Expanded(child: StatusCard(
          header: 'Tempo stimato'.tr(c),
          value: _fmtDur(plan.totalityUsed),
          subtitle: plan.totalityBudget == null
              ? '—'
              : '${'su'.tr(c)} ${_fmtDur(plan.totalityBudget!)}',
          leading: Icons.timer_outlined,
        )),
      ]),
      if (plan.adjustments.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: T.warn(c).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: T.warn(c).withValues(alpha: 0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.tune, size: 14, color: T.warn(c)),
              const SizedBox(width: 6),
              Text('Regolazioni per rientrare nel tempo'.tr(c),
                  style: TextStyle(fontSize: 11.5, color: T.warn(c), fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            for (final a in plan.adjustments)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $a', style: TextStyle(fontSize: 11, color: T.text(c))),
              ),
          ]),
        ),
      ],
      SectionLabel('Timeline totalità'.tr(c)),
      for (final b in plan.totalityBlocks) _blockCard(c, b),
      if (plan.partialBlocks.isNotEmpty) ...[
        SectionLabel('Fase parziale (filtro)'.tr(c)),
        for (final b in plan.partialBlocks) _blockCard(c, b),
      ],
      const SizedBox(height: 18),
      PrimaryButton(
        label: 'Vai al direttore live →'.tr(c),
        icon: Icons.play_circle_outline,
        onPressed: plan.totalityBlocks.isEmpty
            ? null
            : () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => EclipseLiveView(
                      plan: plan,
                      gain: _camType == 'cmos' ? _d(_gain, 100) : null,
                      isLunar: _isLunar,
                    ),
                  ),
                ),
      ),
      const SizedBox(height: 6),
      Text(
        'Il direttore live pilota la camera reale e richiede il bridge connesso. Collauda a secco (Luna / Sole filtrato) prima.'
            .tr(c),
        style: TextStyle(fontSize: 10.5, color: T.muted(c)),
      ),
    ]);
  }

  Widget _blockCard(BuildContext c, CaptureBlock b) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: T.panel(c),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.line(c)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(b.label,
                  style: TextStyle(fontSize: 13.5, color: T.text(c), fontWeight: FontWeight.w600)),
            ),
            if (b.withFilter)
              Icon(Icons.filter_alt, size: 15, color: T.warn(c)),
            Text('${b.frames} ${'frame'.tr(c)}',
                style: TextStyle(fontSize: 11, color: T.muted(c))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in b.exposures)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: T.accent(c).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(formatExposure(e),
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: T.accent(c))),
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${b.shots}× ${'per posa'.tr(c)} · ~${_fmtDur(b.estimate(1.5))}',
            style: TextStyle(fontSize: 10.5, color: T.muted(c)),
          ),
        ]),
      );

  String _fmtDur(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
  }
}
