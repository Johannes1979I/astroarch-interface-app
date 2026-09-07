import 'dart:math' as math;
import 'package:flutter/material.dart';

/// I temi dell'app:
///  - pro          : ambra/blu, default operativo, alta leggibilità
///  - night        : red-light, NON disturba l'adattamento al buio degli occhi
///  - deepSpace    : blu/viola nebulosa, con campo stellato a tema astronomia
///  - interstellar : sobrio cinematografico, blu-ghiaccio, font Exo 2, animato*
///  - starTrek     : console LCARS, pannelli arancio/viola, font Oswald, animato*
///  - osservatorioJupiter : sfondo = foto astronomica reale dell'utente
///                  (Iris NGC 7023), palette derivata dalla foto, transizione
///                  deep-sky zoom
/// (* temi "scenici": animazioni → maggior consumo batteria/CPU)
enum AppThemeMode { pro, night, deepSpace, interstellar, starTrek, osservatorioJupiter }

extension AppThemeModeX on AppThemeMode {
  String get id => switch (this) {
        AppThemeMode.pro => 'pro',
        AppThemeMode.night => 'night',
        AppThemeMode.deepSpace => 'deep_space',
        AppThemeMode.interstellar => 'interstellar',
        AppThemeMode.starTrek => 'star_trek',
        AppThemeMode.osservatorioJupiter => 'osservatorio_jupiter',
      };
  static AppThemeMode fromId(String? s) => switch (s) {
        'night' => AppThemeMode.night,
        'deep_space' => AppThemeMode.deepSpace,
        'interstellar' => AppThemeMode.interstellar,
        'star_trek' => AppThemeMode.starTrek,
        'osservatorio_jupiter' => AppThemeMode.osservatorioJupiter,
        _ => AppThemeMode.pro,
      };
  /// Temi "scenici" (sfondo a tema + transizioni).
  bool get isScenic => this == AppThemeMode.deepSpace ||
      this == AppThemeMode.interstellar || this == AppThemeMode.starTrek ||
      this == AppThemeMode.osservatorioJupiter;
  /// Animazioni di sfondo marcate (interstellar/starTrek). DeepSpace e
  /// osservatorioJupiter hanno sfondo statico (la foto non si anima).
  bool get isAnimated => this == AppThemeMode.interstellar ||
      this == AppThemeMode.starTrek;
  /// Tema con foto reale di sfondo (asset).
  bool get hasPhotoBackground => this == AppThemeMode.osservatorioJupiter;
}

/// Theme dell'app - Pro (ambra), Notte (rosso), Deep Space (nebulosa).
class AppTheme {
  // Colori Pro
  static const Color proBg = Color(0xFF0A0D12);
  static const Color proPanel = Color(0xFF121821);
  static const Color proPanel2 = Color(0xFF1A212D);
  static const Color proLine = Color(0xFF222B3A);
  static const Color proText = Color(0xFFE6EAF2);
  static const Color proMuted = Color(0xFF8A93A6);
  static const Color proAccent = Color(0xFFF5A623);
  static const Color proAccent2 = Color(0xFF5FB7FF);
  static const Color proOk = Color(0xFF3ED598);
  static const Color proWarn = Color(0xFFFFB454);
  static const Color proErr = Color(0xFFFF5B6E);

  // Colori Night (red light)
  static const Color nightBg = Color(0xFF080404);
  static const Color nightPanel = Color(0xFF160808);
  static const Color nightPanel2 = Color(0xFF1F0A0A);
  static const Color nightLine = Color(0xFF3A1414);
  static const Color nightText = Color(0xFFFFB0B0);
  static const Color nightMuted = Color(0xFFA05858);
  static const Color nightAccent = Color(0xFFFF3B3B);
  static const Color nightAccent2 = Color(0xFFFF6B6B);
  static const Color nightOk = Color(0xFFFF8A8A);
  static const Color nightErr = Color(0xFFFF5B5B);

  // Colori Deep Space (nebulosa: blu profondo, accenti viola/ciano)
  static const Color dsBg = Color(0xFF05060F);
  static const Color dsPanel = Color(0xFF0C1024);
  static const Color dsPanel2 = Color(0xFF141A38);
  static const Color dsLine = Color(0xFF26305C);
  static const Color dsText = Color(0xFFE8ECFF);
  static const Color dsMuted = Color(0xFF8A93C0);
  static const Color dsAccent = Color(0xFF8B7CFF);   // viola nebulosa
  static const Color dsAccent2 = Color(0xFF42E8E0);  // ciano
  static const Color dsOk = Color(0xFF3EE0A0);
  static const Color dsErr = Color(0xFFFF5B7E);

  // Colori Interstellar (sobrio, cinematografico: blu-ghiaccio + ambra)
  static const Color isBg = Color(0xFF02040A);
  static const Color isPanel = Color(0xFF0A0F18);
  static const Color isPanel2 = Color(0xFF111824);
  static const Color isLine = Color(0xFF1E2A3A);
  static const Color isText = Color(0xFFDCE6F0);
  static const Color isMuted = Color(0xFF6E7E92);
  static const Color isAccent = Color(0xFF9FC3E0);   // blu ghiaccio
  static const Color isAccent2 = Color(0xFFE0A85C);  // ambra (Endurance)
  static const Color isOk = Color(0xFF7FD0C0);
  static const Color isErr = Color(0xFFE06B6B);

  // Colori Star Trek / LCARS (pannelli arancio/viola/azzurro su nero)
  static const Color stBg = Color(0xFF000000);
  static const Color stPanel = Color(0xFF1A1326);
  static const Color stPanel2 = Color(0xFF241A33);
  static const Color stLine = Color(0xFF3A2A4E);
  static const Color stText = Color(0xFFFFF0D8);
  static const Color stMuted = Color(0xFF9C88C0);
  static const Color stAccent = Color(0xFFFF9C00);   // LCARS orange
  static const Color stAccent2 = Color(0xFF9C9CFF);  // LCARS periwinkle
  static const Color stOk = Color(0xFFCC99CC);
  static const Color stErr = Color(0xFFFF5555);

  // Colori Osservatorio Jupiter (derivati dalla foto Iris NGC 7023:
  // nebulosa a riflessione → ciano/azzurro #3CAAB8 estratto dalla foto).
  static const Color ojBg = Color(0xFF04060C);
  static const Color ojPanel = Color(0xCC0A0E18);   // semi-trasparente sulla foto
  static const Color ojPanel2 = Color(0xDD121826);
  static const Color ojLine = Color(0xFF223247);
  static const Color ojText = Color(0xFFDCE8F2);
  static const Color ojMuted = Color(0xFF7286A0);
  static const Color ojAccent = Color(0xFF3CAAB8);   // ciano Iris (dalla foto)
  static const Color ojAccent2 = Color(0xFF8FC4E8);  // azzurro stellare
  static const Color ojOk = Color(0xFF5FC9B0);
  static const Color ojErr = Color(0xFFE06B6B);

  /// Path dell'asset foto di sfondo del tema Osservatorio Jupiter.
  static const String ojPhotoAsset = 'assets/themes/osservatorio_jupiter.jpg';

  /// Ritorna il ThemeData per il modo richiesto.
  static ThemeData forMode(AppThemeMode m) => switch (m) {
        AppThemeMode.night => buildNight(),
        AppThemeMode.deepSpace => buildDeepSpace(),
        AppThemeMode.interstellar => buildInterstellar(),
        AppThemeMode.starTrek => buildStarTrek(),
        AppThemeMode.osservatorioJupiter => buildOsservatorioJupiter(),
        AppThemeMode.pro => buildPro(),
      };

  static ThemeData buildOsservatorioJupiter() => _build(
        bg: ojBg, panel: ojPanel, panel2: ojPanel2, line: ojLine,
        text: ojText, muted: ojMuted, accent: ojAccent, accent2: ojAccent2,
        ok: ojOk, err: ojErr,
        // scaffold TRASPARENTE: la foto di sfondo (applicata globalmente nel
        // MaterialApp builder) traspare in OGNI schermata. Le card sono
        // semi-trasparenti (ojPanel = 0xCC…) così la foto si intravede sotto.
        scaffoldColor: const Color(0x00000000),
        fontBuilder: _osservatorioFont, // headline/display
        titleFont: 'Misa13',            // titoli AppBar di ogni schermata
      );

  static ThemeData buildPro() => _build(
        bg: proBg, panel: proPanel, panel2: proPanel2, line: proLine,
        text: proText, muted: proMuted, accent: proAccent, accent2: proAccent2,
        ok: proOk, err: proErr,
      );

  static ThemeData buildNight() => _build(
        bg: nightBg, panel: nightPanel, panel2: nightPanel2, line: nightLine,
        text: nightText, muted: nightMuted, accent: nightAccent, accent2: nightAccent2,
        ok: nightOk, err: nightErr,
      );

  static ThemeData buildDeepSpace() => _build(
        bg: dsBg, panel: dsPanel, panel2: dsPanel2, line: dsLine,
        text: dsText, muted: dsMuted, accent: dsAccent, accent2: dsAccent2,
        ok: dsOk, err: dsErr,
      );

  // Theme fonts, Open Font Licence, BUNDLED as assets.
  // Interstellar → Exo 2 (sans tech, estetica cinematografica minimalista).
  // Star Trek → Antonio (condensato, look LCARS — alternativa libera al
  //   font ufficiale, che è protetto da copyright).
  //
  // They used to come from the google_fonts package, which downloads them
  // from fonts.gstatic.com on first use and caches them afterwards. In the
  // field, under a dark sky with no connection, that download cannot
  // succeed, and both themes lost their typeface, falling back to the
  // system one.
  // These are variable fonts: Flutter uses the default instance and
  // synthesises the weights. For finer control over weights, pass
  // `fontVariations` on the theme's TextStyles.
  static TextTheme _interstellarFont(TextTheme base) =>
      base.apply(fontFamily: 'Exo2');
  static TextTheme _starTrekFont(TextTheme base) =>
      base.apply(fontFamily: 'Antonio');

  /// Font "13 Misa" (Zane Townsend / Unrender) per il tema Osservatorio Jupiter.
  /// v0.2.53: applicato SOLO ai TITOLI (richiesto dall'utente). È un font
  /// display decorativo con orbite → sui numeri/testo sarebbe illeggibile.
  /// I titoli delle schermate (AppBar) usano il font via `titleFont` in
  /// _build; qui copriamo anche gli headline/display semantici. Body e numeri
  /// restano col font di sistema (leggibile).
  static TextTheme _osservatorioFont(TextTheme base) {
    const fam = 'Misa13';
    TextStyle? m(TextStyle? s) => s?.copyWith(fontFamily: fam, letterSpacing: 1.2);
    return base.copyWith(
      displayLarge: m(base.displayLarge),
      displayMedium: m(base.displayMedium),
      displaySmall: m(base.displaySmall),
      headlineLarge: m(base.headlineLarge),
      headlineMedium: m(base.headlineMedium),
      headlineSmall: m(base.headlineSmall),
    );
  }

  static ThemeData buildInterstellar() => _build(
        bg: isBg, panel: isPanel, panel2: isPanel2, line: isLine,
        text: isText, muted: isMuted, accent: isAccent, accent2: isAccent2,
        ok: isOk, err: isErr, fontBuilder: _interstellarFont,
      );

  static ThemeData buildStarTrek() => _build(
        bg: stBg, panel: stPanel, panel2: stPanel2, line: stLine,
        text: stText, muted: stMuted, accent: stAccent, accent2: stAccent2,
        ok: stOk, err: stErr, fontBuilder: _starTrekFont,
        cardRadius: 18, // pannelli LCARS più arrotondati
      );

  static ThemeData _build({
    required Color bg, required Color panel, required Color panel2,
    required Color line, required Color text, required Color muted,
    required Color accent, required Color accent2,
    required Color ok, required Color err,
    TextTheme Function(TextTheme)? fontBuilder,
    double cardRadius = 14,
    Color? scaffoldColor,
    String? titleFont,
  }) {
    final base = ThemeData.dark(useMaterial3: true);
    // Font tematico (se fornito) applicato al textTheme, con fallback sicuro.
    TextTheme themedText = base.textTheme;
    if (fontBuilder != null) {
      try { themedText = fontBuilder(base.textTheme); } catch (_) {}
    }
    return base.copyWith(
      scaffoldBackgroundColor: scaffoldColor ?? bg,
      colorScheme: ColorScheme.dark(
        surface: bg,
        primary: accent,
        secondary: accent2,
        error: err,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
      ).copyWith(
        surfaceContainerHighest: panel,
        surfaceContainer: panel,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        // v0.2.53: titleFont applica il font tematico al TITOLO della schermata
        // (AppBar). Se null, lo style di default. Per Osservatorio Jupiter è
        // '13 Misa' → il font si vede sui titoli (prima era hardcoded senza
        // fontFamily, quindi il font non appariva).
        titleTextStyle: TextStyle(
          color: text, fontWeight: FontWeight.w600,
          fontSize: titleFont != null ? 20 : 17,
          fontFamily: titleFont,
          letterSpacing: titleFont != null ? 1.5 : null,
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: line),
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerColor: line,
      textTheme: themedText.apply(bodyColor: text, displayColor: text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent),
        ),
        labelStyle: TextStyle(color: muted, fontSize: 12, letterSpacing: 1),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: .4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: line),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        indicatorColor: accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w500),
        ),
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: muted, size: 22)),
        height: 64,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: panel),
      listTileTheme: ListTileThemeData(textColor: text, iconColor: muted),
      iconTheme: IconThemeData(color: muted),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: panel2,
        contentTextStyle: TextStyle(color: text),
        actionTextColor: accent,
      ),
    );
  }
}

/// Sfondo a tema dietro al contenuto. Stile e animazione dipendono dal
/// tema attivo:
///  - deepSpace    : campo stellato + nebulosa, STATICO (no batteria extra)
///  - interstellar : stelle in drift lento + aloni che pulsano (animato)
///  - starTrek     : scan-line LCARS che scorre + stelle (animato)
///  - altri temi   : trasparente (no-op)
/// Deterministico (seed fisso) → niente sfarfallio. Animazione solo per i
/// temi scenici animati.
class StarfieldBackground extends StatefulWidget {
  final Widget child;
  final AppThemeMode mode;
  const StarfieldBackground({super.key, required this.child, required this.mode});

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    _setupAnim();
  }

  void _setupAnim() {
    _ctrl?.dispose();
    _ctrl = null;
    if (widget.mode.isAnimated) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 18), // lento → poco consumo
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(StarfieldBackground old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _setupAnim();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.mode.isScenic) return widget.child;
    // v0.2.50: il tema foto (osservatorioJupiter) ha lo sfondo applicato
    // GLOBALMENTE nel MaterialApp builder (tutte le schermate). Qui niente
    // da fare → evita doppio rendering.
    if (widget.mode.hasPhotoBackground) return widget.child;
    if (_ctrl == null) {
      // statico (deepSpace)
      return Stack(children: [
        Positioned.fill(child: IgnorePointer(
            child: CustomPaint(painter: _StarfieldPainter(widget.mode, 0)))),
        widget.child,
      ]);
    }
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(
        animation: _ctrl!,
        builder: (_, __) => CustomPaint(
            painter: _StarfieldPainter(widget.mode, _ctrl!.value)),
      ))),
      widget.child,
    ]);
  }
}

class _StarfieldPainter extends CustomPainter {
  final AppThemeMode mode;
  final double t; // 0..1 fase animazione
  _StarfieldPainter(this.mode, this.t);

  static final List<_Star> _stars = _gen();
  static List<_Star> _gen() {
    final r = math.Random(20260527);
    return List.generate(140, (_) => _Star(
      r.nextDouble(), r.nextDouble(),
      r.nextDouble() * 1.3 + 0.3,
      r.nextDouble() * 0.6 + 0.2,
    ));
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (mode) {
      case AppThemeMode.deepSpace:
        _paintNebula(canvas, size, const Color(0x228B7CFF), const Color(0x1842E8E0));
        _paintStars(canvas, size, 0);
        break;
      case AppThemeMode.interstellar:
        // drift orizzontale lento + aloni pulsanti + disco di Gargantua
        final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
        _paintNebula(canvas, size,
            Color.fromRGBO(159, 195, 224, 0.10 + 0.05 * pulse),
            Color.fromRGBO(224, 168, 92, 0.06 + 0.04 * (1 - pulse)));
        _paintStars(canvas, size, t * 0.04); // drift molto lento
        _paintGargantua(canvas, size, t);    // buco nero iconico
        break;
      case AppThemeMode.starTrek:
        // sfondo nero + stelle + scan-line LCARS + starship che scorre
        _paintStars(canvas, size, 0);
        final y = (t * size.height) % size.height;
        final scan = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: const [Color(0x00FF9C00), Color(0x33FF9C00), Color(0x00FF9C00)],
          ).createShader(Rect.fromLTWH(0, y - 40, size.width, 80));
        canvas.drawRect(Rect.fromLTWH(0, y - 40, size.width, 80), scan);
        _paintStarship(canvas, size, t);     // silhouette nave (originale)
        break;
      default:
        break;
    }
  }

  void _paintNebula(Canvas canvas, Size size, Color c1, Color c2) {
    final p1 = Paint()..shader = RadialGradient(colors: [c1, const Color(0x00000000)])
        .createShader(Rect.fromCircle(
            center: Offset(size.width * 0.25, size.height * 0.28),
            radius: size.width * 0.5));
    canvas.drawRect(Offset.zero & size, p1);
    final p2 = Paint()..shader = RadialGradient(colors: [c2, const Color(0x00000000)])
        .createShader(Rect.fromCircle(
            center: Offset(size.width * 0.8, size.height * 0.7),
            radius: size.width * 0.45));
    canvas.drawRect(Offset.zero & size, p2);
  }

  /// Starfield con PARALLAX: le stelle più grandi (vicine) driftano più
  /// veloci di quelle piccole (lontane) → profondità. Le grandi hanno anche
  /// un leggero glow.
  void _paintStars(Canvas canvas, Size size, double driftX) {
    for (final s in _stars) {
      // parallax: drift proporzionale alla dimensione (profondità)
      final depth = (s.r - 0.3) / 1.3; // 0..1
      final x = ((s.x + driftX * (0.3 + depth)) % 1.0) * size.width;
      final y = s.y * size.height;
      if (s.r > 1.0) {
        // glow per le stelle vicine
        canvas.drawCircle(Offset(x, y), s.r * 2.2, Paint()
          ..color = Colors.white.withValues(alpha: s.alpha * 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      }
      canvas.drawCircle(Offset(x, y), s.r,
          Paint()..color = Colors.white.withValues(alpha: s.alpha));
    }
  }

  /// Disco di accrescimento "Gargantua" foto-realistico (originale, ispirato
  /// a Interstellar): orizzonte degli eventi nero + photon ring, disco con
  /// DOPPLER BEAMING (un lato molto più luminoso), LENSING gravitazionale
  /// (anello verticale che passa sopra e sotto), glow esterno. Rotazione lenta.
  void _paintGargantua(Canvas canvas, Size size, double t) {
    final c = Offset(size.width * 0.80, size.height * 0.17);
    final r = size.width * 0.14;
    canvas.save();
    canvas.translate(c.dx, c.dy);

    // glow esterno morbido
    canvas.drawCircle(Offset.zero, r * 2.6, Paint()
      ..shader = RadialGradient(colors: const [
        Color(0x33FFD89A), Color(0x00000000),
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 2.6)));

    // LENSING: anello verticale (l'immagine del disco "dietro" curvata sopra
    // e sotto la sfera) — la firma visiva di Gargantua.
    final lensRect = Rect.fromCenter(center: Offset.zero, width: r * 2.5, height: r * 3.6);
    canvas.drawOval(lensRect, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = r * 0.16
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..shader = SweepGradient(transform: GradientRotation(t * 2 * math.pi),
        colors: const [Color(0x00FFE6B0), Color(0x66FFE6B0), Color(0x00FFE6B0),
                       Color(0x66FFE6B0), Color(0x00FFE6B0)],
      ).createShader(lensRect));

    // DISCO DI ACCRESCIMENTO (ellisse schiacciata) con doppler beaming:
    // lato sinistro (in avvicinamento) molto più luminoso del destro.
    final diskRect = Rect.fromCenter(center: Offset.zero, width: r * 3.6, height: r * 1.0);
    canvas.drawOval(diskRect, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = r * 0.34
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
      ..shader = LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: const [
          Color(0xFFFFF4D0), Color(0xFFFFD080), Color(0xFFC87830),
          Color(0xFF7A4818), Color(0xFF3A2410),
        ],
        stops: const [0.0, 0.28, 0.55, 0.8, 1.0],
      ).createShader(diskRect));

    // sfera nera (orizzonte degli eventi)
    canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0xFF000000));
    // photon ring sottile e luminoso attorno all'orizzonte
    canvas.drawCircle(Offset.zero, r * 1.02, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = r * 0.05
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
      ..color = const Color(0xCCFFE6B0));
    canvas.restore();
  }

  /// Starship (forma ORIGINALE: scafo a disco + collo + due gondole con
  /// bussard glow rosso e scia warp azzurra) che scorre. Non riproduce navi
  /// protette da copyright — è una nave generica stilizzata.
  void _paintStarship(Canvas canvas, Size size, double t) {
    final x = (t * 1.4 - 0.2) * size.width;
    final y = size.height * 0.22;
    final s = size.width * 0.055;
    canvas.save();
    canvas.translate(x, y);
    // scia warp (azzurra) dietro
    canvas.drawRect(
      Rect.fromCenter(center: Offset(-s * 2.5, s * 1.0), width: s * 4, height: s * 0.5),
      Paint()..shader = LinearGradient(colors: const [
        Color(0x000088FF), Color(0x553399FF),
      ]).createShader(Rect.fromCenter(center: Offset(-s * 2.5, s * 1.0), width: s * 4, height: s * 0.5)));
    final hull = Paint()..color = const Color(0x66B0C4DE);
    // scafo a disco
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 2.4, height: s * 0.7), hull);
    // collo + corpo
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, s * 0.6), width: s * 0.6, height: s * 1.0),
        Radius.circular(s * 0.2)), hull);
    // due gondole con punta rossa (bussard)
    for (final dx in [-s * 0.85, s * 0.85]) {
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(dx, s * 1.05), width: s * 0.32, height: s * 1.2),
          Radius.circular(s * 0.16)), hull);
      canvas.drawCircle(Offset(dx, s * 0.5), s * 0.16,
          Paint()..color = const Color(0x99FF5533));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.t != t || old.mode != mode;
}

class _Star {
  final double x, y, r, alpha;
  const _Star(this.x, this.y, this.r, this.alpha);
}

/// Token semantici accessibili in tutta l'app.
class T {
  static Color text(BuildContext c) => Theme.of(c).colorScheme.onSurface;
  static Color muted(BuildContext c) =>
      Theme.of(c).inputDecorationTheme.labelStyle?.color ?? Colors.grey;
  static Color panel(BuildContext c) => Theme.of(c).colorScheme.surfaceContainer;
  static Color line(BuildContext c) => Theme.of(c).dividerColor;
  static Color accent(BuildContext c) => Theme.of(c).colorScheme.primary;
  static Color accent2(BuildContext c) => Theme.of(c).colorScheme.secondary;
  static Color ok(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? const Color(0xFF3ED598) : const Color(0xFF1F8B62);
  static Color err(BuildContext c) => Theme.of(c).colorScheme.error;
  static Color warn(BuildContext c) => const Color(0xFFFFB454);
}
