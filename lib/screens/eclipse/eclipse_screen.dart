import 'package:flutter/material.dart';
import '../../i18n/strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../eclipse/eclipse_optimizer.dart';
import '../../eclipse/eclipse_planner.dart';
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

  EclipsePlan? _plan;
  bool _maximizeShots = false;

  @override
  void dispose() {
    for (final c in [_fRatio, _focalLen, _pixel, _unityGain, _gain, _iso, _totalitySec, _shots]) {
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
    final totSec = _i(_totalitySec, 120);
    final c2 = DateTime(2027, 8, 2, 11, 0, 0);
    final contacts = EclipseContacts(c2: c2, c3: c2.add(Duration(seconds: totSec)));
    final plan = EclipsePlanner().build(
      features: _features,
      contacts: contacts,
      scope: scope,
      cam: cam,
      gain: _camType == 'cmos' ? _d(_gain, 100) : null,
      iso: _camType == 'dslr' ? _d(_iso, 400) : null,
      shotsPerExposure: _i(_shots, 1),
      maximizeShots: _maximizeShots,
    );
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
          _intro(context),
          SectionLabel('Feature da fotografare'.tr(context)),
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

  Widget _featurePresets(BuildContext c) => Wrap(spacing: 8, runSpacing: 8, children: [
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
    // Ordine cronologico: parziale + feature di totalità.
    const order = [
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
