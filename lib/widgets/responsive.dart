// Layout adattivo: un solo posto che decide come lo spazio si distribuisce,
// da un telefono in verticale a un monitor da 2560 px.
//
// Perche' esiste. Fino alla 0.10.1 la shell chiudeva OGNI schermata in un
// riquadro largo al massimo 620 px: sul Mac e sul monitor del Raspberry la
// Dashboard era una striscia da telefono in mezzo al vuoto. Togliere quel tetto
// da solo pero' peggiorava le cose: le griglie a proporzioni fisse
// (childAspectRatio) facevano card alte meta' della loro larghezza e le
// anteprime della camera diventavano alte centinaia di pixel.
//
// Regole che seguono tutti i widget qui sotto:
//  - decidono sulla larghezza REALE del riquadro (LayoutBuilder), non sullo
//    schermo (MediaQuery.size): cosi' funzionano anche con il rail laterale,
//    con i due pannelli affiancati e con le finestre ridimensionate;
//  - lo scroll resta su tutta l'area: si allarga il padding, non si stringe la
//    lista, quindi la barra di scorrimento e il pull-to-refresh restano al bordo;
//  - le griglie hanno altezza decisa dal CONTENUTO, mai da un rapporto fisso:
//    con il testo grande (textScale 1.3 e scala di sistema) non vanno in
//    overflow, e su schermo largo non producono card giganti.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Che tipo di contenuto c'e' nella pagina: decide quanto puo' allargarsi.
enum ContentKind {
  /// Pagine di controllo (Dashboard, Mount, Capture...): crescono con lo
  /// schermo a gradini, fino a 1600 px.
  page,

  /// Moduli e liste di voci (login, impostazioni, elenco bridge): righe piu'
  /// larghe di ~720 px si leggono male, qualunque sia lo schermo.
  form,

  /// Registri e tabelle: possono usare quasi tutta la larghezza.
  wide,
}

/// Soglie di larghezza, in pixel logici, del riquadro disponibile.
class Bp {
  /// Sotto: telefono in verticale. Nessun limite, tutto lo spazio.
  static const double compact = 600;

  /// Sotto: tablet in verticale, telefono in orizzontale, finestra stretta.
  static const double medium = 1024;

  /// Sotto: tablet in orizzontale, portatile. Sopra: monitor.
  static const double expanded = 1440;

  /// Sopra: monitor grande usato a scala 1 (1440p, 4K).
  static const double large = 1920;

  const Bp._();
}

/// Larghezza massima del contenuto in un riquadro largo [available].
double contentMaxWidth(double available, [ContentKind kind = ContentKind.page]) {
  if (!available.isFinite) return available;
  switch (kind) {
    case ContentKind.page:
      if (available < Bp.compact) return available;
      if (available < Bp.medium) return math.min(available, 760);
      if (available < Bp.expanded) return math.min(available, 1040);
      if (available < Bp.large) return math.min(available, 1280);
      // Monitor 1440p/4K senza ridimensionamento (il Raspberry su un monitor
      // grande): con 1280 restava meta' schermo vuoto e tutto sembrava minuscolo.
      return math.min(available, 1600);
    case ContentKind.form:
      return math.min(available, 720);
    case ContentKind.wide:
      return math.min(available, 1600);
  }
}

/// Il [base] padding della pagina, piu' i margini laterali che centrano il
/// contenuto quando il riquadro e' piu' largo di [contentMaxWidth].
EdgeInsets adaptivePadding(
  double available,
  EdgeInsets base, [
  ContentKind kind = ContentKind.page,
]) {
  if (!available.isFinite) return base;
  final inner = available - base.horizontal;
  final max = contentMaxWidth(available, kind) - base.horizontal;
  final side = math.max(0.0, (inner - max) / 2);
  return EdgeInsets.fromLTRB(
      base.left + side, base.top, base.right + side, base.bottom);
}

/// Sostituto diretto di [ListView] che centra il contenuto a una larghezza
/// leggibile. Stessi parametri principali; in piu' [kind].
///
/// Esempio: `ListView(padding: p, children: c)` diventa
/// `AdaptiveListView(padding: p, children: c)`.
class AdaptiveListView extends StatelessWidget {
  final ContentKind kind;

  /// Come in [ListView]: se null, la lista aggiunge da sola il margine di
  /// sicurezza dello schermo (barra dei gesti, notch).
  final EdgeInsets? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final bool? primary;
  final List<Widget>? children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;

  const AdaptiveListView({
    super.key,
    this.kind = ContentKind.page,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.primary,
    required List<Widget> this.children,
  })  : itemCount = null,
        itemBuilder = null,
        separatorBuilder = null;

  const AdaptiveListView.builder({
    super.key,
    this.kind = ContentKind.page,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.primary,
    required this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
  })  : children = null,
        separatorBuilder = null;

  const AdaptiveListView.separated({
    super.key,
    this.kind = ContentKind.page,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.primary,
    required this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
    required IndexedWidgetBuilder this.separatorBuilder,
  }) : children = null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final EdgeInsets? p;
      final base = padding;
      if (base != null) {
        p = adaptivePadding(c.maxWidth, base, kind);
      } else {
        // Nessun padding indicato: finche' il contenuto non va centrato,
        // null come prima, cosi' ListView aggiunge il margine di sicurezza da
        // sola (segnalato in revisione: senza, su Android l'ultima voce finiva
        // sotto la barra dei gesti). Su schermo largo i margini laterali, piu'
        // lo stesso margine di sicurezza in alto e in basso.
        final side = adaptivePadding(c.maxWidth, EdgeInsets.zero, kind).left;
        if (side == 0) {
          p = null;
        } else {
          final mq = MediaQuery.paddingOf(context);
          p = EdgeInsets.fromLTRB(side, mq.top, side, mq.bottom);
        }
      }
      if (children != null) {
        return ListView(
          controller: controller,
          physics: physics,
          shrinkWrap: shrinkWrap,
          primary: primary,
          padding: p,
          children: children!,
        );
      }
      if (separatorBuilder != null) {
        return ListView.separated(
          controller: controller,
          physics: physics,
          shrinkWrap: shrinkWrap,
          primary: primary,
          padding: p,
          itemCount: itemCount!,
          itemBuilder: itemBuilder!,
          separatorBuilder: separatorBuilder!,
        );
      }
      return ListView.builder(
        controller: controller,
        physics: physics,
        shrinkWrap: shrinkWrap,
        primary: primary,
        padding: p,
        itemCount: itemCount,
        itemBuilder: itemBuilder!,
      );
    });
  }
}

/// Centra e limita in larghezza un contenuto che NON e' una lista (per
/// esempio il figlio di un SingleChildScrollView o una Column).
class AdaptiveWidth extends StatelessWidget {
  final ContentKind kind;
  final Widget child;
  const AdaptiveWidth(
      {super.key, this.kind = ContentKind.page, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: contentMaxWidth(c.maxWidth, kind)),
          child: child,
        ),
      );
    });
  }
}

/// Griglia di card: il numero di colonne dipende dalla larghezza disponibile
/// ([minTileWidth] per card, da 1 a [maxColumns]); l'altezza la decide il
/// contenuto. Sostituisce `GridView.count(shrinkWrap: true, ...)` dentro le
/// liste.
///
/// Con [equalHeight] (predefinito) le card di una riga hanno la stessa altezza,
/// misurata con IntrinsicHeight. Se una card contiene un LayoutBuilder, che non
/// sa rispondere a quella misura, usare `equalHeight: false`.
class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;
  final bool equalHeight;

  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minTileWidth = 160,
    this.maxColumns = 4,
    this.spacing = 8,
    this.equalHeight = true,
  });

  /// Colonne per una larghezza [w] e [count] card. Esposta per i test.
  ///
  /// Evita le card orfane: se togliendo una colonna il numero di righe non
  /// cresce, la toglie. Quattro card in uno spazio da tre colonne diventano
  /// 2+2 invece di 3+1, sei card in uno da quattro diventano 3+3.
  static int columnsFor(double w,
      {int count = 1 << 20,
      double minTileWidth = 160,
      int maxColumns = 4,
      double spacing = 8}) {
    var cols = w.isFinite
        ? ((w + spacing) / (minTileWidth + spacing)).floor().clamp(1, maxColumns)
        : maxColumns;
    cols = math.min(cols, math.max(1, count));
    int rows(int c) => (count + c - 1) ~/ c;
    while (cols > 1 && count % cols != 0 && rows(cols - 1) == rows(cols)) {
      cols--;
    }
    return cols;
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final cols = columnsFor(c.maxWidth,
          count: children.length,
          minTileWidth: minTileWidth,
          maxColumns: maxColumns,
          spacing: spacing);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final cells = <Widget>[];
        for (var j = 0; j < cols; j++) {
          if (j > 0) cells.add(SizedBox(width: spacing));
          final k = i + j;
          cells.add(Expanded(
              child: k < children.length ? children[k] : const SizedBox()));
        }
        final row = Row(
          crossAxisAlignment: equalHeight
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.start,
          children: cells,
        );
        if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
        rows.add(equalHeight ? IntrinsicHeight(child: row) : row);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    });
  }
}

/// Anteprima a proporzioni fisse (camera, stella guida, plate solve) che non
/// supera [maxHeightFraction] dell'altezza dello schermo: su un monitor largo
/// non spinge piu' i comandi fuori dalla vista, su un telefono in orizzontale
/// non riempie tutto. Il figlio riceve comunque il riquadro reale, quindi un
/// LayoutBuilder al suo interno (il mirino della guida) resta corretto.
class AdaptivePreview extends StatelessWidget {
  final double aspectRatio;
  final double maxHeightFraction;
  final Widget child;

  const AdaptivePreview({
    super.key,
    required this.aspectRatio,
    this.maxHeightFraction = 0.55,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * maxHeightFraction;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.max(120.0, maxH)),
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: AspectRatio(aspectRatio: aspectRatio, child: child),
      ),
    );
  }
}

/// Due colonne affiancate sopra [breakpoint], una sola sotto (prima [left],
/// poi [right], nello stesso ordine di oggi). Da usare come figlio di una
/// lista per sfruttare la larghezza di un monitor.
class AdaptiveColumns extends StatelessWidget {
  final List<Widget> left;
  final List<Widget> right;
  final double breakpoint;
  final int leftFlex;
  final int rightFlex;
  final double gap;

  const AdaptiveColumns({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = 980,
    this.leftFlex = 1,
    this.rightFlex = 1,
    this.gap = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [...left, ...right],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: leftFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: left,
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            flex: rightFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: right,
            ),
          ),
        ],
      );
    });
  }
}
