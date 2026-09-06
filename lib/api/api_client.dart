import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Entry del log di una chiamata API (visibile in Activity log).
class ApiLogEntry {
  final DateTime ts;
  final String method;
  final String path;
  final int? status;
  final String? body;
  final String? error;
  final Duration duration;
  ApiLogEntry({
    required this.ts, required this.method, required this.path,
    this.status, this.body, this.error, required this.duration,
  });
  bool get ok => error == null && status != null && status! >= 200 && status! < 300;
}

/// Buffer circolare globale degli ultimi N call. Visibile dalla schermata Logs.
class ApiLog {
  static const int maxEntries = 100;
  static final List<ApiLogEntry> _entries = [];
  static final List<void Function()> _listeners = [];

  static void add(ApiLogEntry e) {
    _entries.insert(0, e);
    if (_entries.length > maxEntries) _entries.removeRange(maxEntries, _entries.length);
    for (final l in List.of(_listeners)) {
      try { l(); } catch (_) {}
    }
  }

  static List<ApiLogEntry> get entries => List.unmodifiable(_entries);
  static void clear() {
    _entries.clear();
    for (final l in List.of(_listeners)) { try { l(); } catch (_) {} }
  }

  static void addListener(void Function() l) => _listeners.add(l);
  static void removeListener(void Function() l) => _listeners.remove(l);
}

/// Client HTTP REST per il bridge.
class ApiClient {
  final String baseUrl; // es: http://100.74.22.40:8765
  final String token;
  final http.Client _http = http.Client();

  ApiClient({required this.baseUrl, required this.token});

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Uri _u(String path, [Map<String, String>? q]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: path,
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? q]) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _http.get(_u(path, q), headers: _authHeaders).timeout(const Duration(seconds: 10));
      sw.stop();
      ApiLog.add(ApiLogEntry(
        ts: DateTime.now(), method: 'GET', path: _logPath(path, q),
        status: r.statusCode, body: _shortBody(r.body), duration: sw.elapsed,
      ));
      return _decode(r);
    } catch (e) {
      sw.stop();
      ApiLog.add(ApiLogEntry(
        ts: DateTime.now(), method: 'GET', path: _logPath(path, q),
        error: e.toString(), duration: sw.elapsed,
      ));
      rethrow;
    }
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body, Duration? timeout]) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _http
          .post(_u(path), headers: _authHeaders, body: jsonEncode(body ?? {}))
          .timeout(timeout ?? const Duration(seconds: 15));
      sw.stop();
      ApiLog.add(ApiLogEntry(
        ts: DateTime.now(), method: 'POST', path: _logPath(path, null),
        status: r.statusCode, body: _shortBody(r.body), duration: sw.elapsed,
      ));
      return _decode(r);
    } catch (e) {
      sw.stop();
      ApiLog.add(ApiLogEntry(
        ts: DateTime.now(), method: 'POST', path: _logPath(path, null),
        error: e.toString(), duration: sw.elapsed,
      ));
      rethrow;
    }
  }

  String _logPath(String path, Map<String, String>? q) {
    if (q == null || q.isEmpty) return path;
    return '$path?${q.entries.map((e) => "${e.key}=${e.value}").join("&")}';
  }
  String _shortBody(String b) => b.length > 200 ? '${b.substring(0, 200)}…' : b;

  Future<Uint8List> getBytes(String path, [Map<String, String>? q]) async {
    final r = await _http.get(_u(path, q), headers: _authHeaders).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, r.body);
    }
    return r.bodyBytes;
  }

  Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return {};
      final j = jsonDecode(r.body);
      if (j is Map<String, dynamic>) return j;
      return {'data': j};
    }
    throw ApiException(r.statusCode, r.body);
  }

  // --- Health (no auth) ---
  Future<bool> ping() async {
    try {
      final r = await _http.get(_u('/healthz')).timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- High-level helpers ---
  Future<Map<String, dynamic>> snapshot() => get('/api/system/snapshot');
  /// v0.2.55: ultimo frame JPEG su richiesta (per ricaricarlo dopo il rientro
  /// da background, quando la WS non lo ri-invia). Lancia ApiException(404)
  /// se non c'è ancora nessun frame.
  Future<Uint8List> lastFrame() => getBytes('/api/system/last_frame');
  Future<Map<String, dynamic>> info() => get('/api/system/info');
  Future<Map<String, dynamic>> connections() => get('/api/system/connections');
  Future<Map<String, dynamic>> cameraRoles() => get('/api/system/camera_roles');
  Future<Map<String, dynamic>> simbadSearch(String name) => get('/api/system/simbad', {'name': name});

  // Ekos master control (clone del quadratino Start/Stop in Setup di Ekos)
  Future<Map<String, dynamic>> ekosState() => get('/api/system/ekos_state');
  Future<Map<String, dynamic>> ekosStart() => post('/api/system/ekos_start');
  Future<Map<String, dynamic>> ekosStop() => post('/api/system/ekos_stop');
  Future<Map<String, dynamic>> ekosConnectDevices() => post('/api/system/ekos_connect_devices');
  Future<Map<String, dynamic>> ekosDisconnectDevices() => post('/api/system/ekos_disconnect_devices');
  Future<Map<String, dynamic>> ekosToggle() => post('/api/system/ekos_toggle');

  // === Launch GUI apps on the RPi (KStars + PHD2 windows on the Pi's monitor) ===
  Future<Map<String, dynamic>> guiAppsState() => get('/api/system/gui_apps_state');
  Future<Map<String, dynamic>> launchKStars() => post('/api/system/launch_kstars');
  Future<Map<String, dynamic>> launchPhd2() => post('/api/system/launch_phd2');
  Future<Map<String, dynamic>> killKStars() => post('/api/system/kill_kstars');
  Future<Map<String, dynamic>> killPhd2() => post('/api/system/kill_phd2');

  /// QR di accoppiamento: ritorna {host, port, token, payload, png_base64}
  /// generato dal bridge con l'IP Tailscale (NON l'IP LAN).
  Future<Map<String, dynamic>> pairingQr() => get('/api/system/qr');

  // Align
  Future<Map<String, dynamic>> alignStatus() => get('/api/align/status');
  Future<void> alignSolveLastFrame() => post('/api/align/solve_last_frame');
  Future<Map<String, dynamic>> alignSolve({String? path, double? hintRa, double? hintDec, double? hintRadius}) =>
      post('/api/align/solve', {
        if (path != null) 'path': path,
        if (hintRa != null) 'hint_ra': hintRa,
        if (hintDec != null) 'hint_dec': hintDec,
        if (hintRadius != null) 'hint_radius': hintRadius,
      });
  Future<Map<String, dynamic>> alignSolveStatus(String runId) => get('/api/align/solve/$runId');
  Future<Map<String, dynamic>> alignSolveSyncMount(String runId) =>
      post('/api/align/solve/$runId/sync_mount');
  Future<Map<String, dynamic>> alignCaptureAndSolve({
    double exposureSec = 5.0,
    String? cameraDevice,
    int binX = 2, int binY = 2,
    double? gain,
  }) => post('/api/align/capture_and_solve', {
        'exposure_sec': exposureSec,
        'bin_x': binX, 'bin_y': binY,
        if (gain != null) 'gain': gain,
        if (cameraDevice != null) 'camera_device': cameraDevice,
      });

  /// Trigger Ekos Align captureAndSolve via DBus.
  /// L'utente vede tutto in Ekos sul desktop (FITS Viewer, log, sequenza solve).
  Future<Map<String, dynamic>> alignEkosCaptureAndSolve({
    int? binIndex, double? targetRaHours, double? targetDecDeg,
    int? solverAction, // Ekos enum: 0=Sync, 1=Slew, 2=Nothing
    double? exposureSec, double? gain,
  }) => post('/api/align/ekos_capture_and_solve', {
        if (binIndex != null) 'bin_index': binIndex,
        if (targetRaHours != null) 'target_ra_hours': targetRaHours,
        if (targetDecDeg != null) 'target_dec_deg': targetDecDeg,
        if (solverAction != null) 'solver_action': solverAction,
        if (exposureSec != null) 'exposure_sec': exposureSec,
        if (gain != null) 'gain': gain,
      });
  Future<Map<String, dynamic>> alignEkosStatus() => get('/api/align/ekos_align_status');
  Future<void> alignEkosAbort() => post('/api/align/ekos_align_abort');
  Future<Map<String, dynamic>> alignEkosFullStatus() => get('/api/align/ekos_full_status');
  Future<Map<String, dynamic>> alignEkosSet({
    int? binIndex, int? solverAction, int? solverMode,
    double? targetRaHours, double? targetDecDeg, double? targetPositionAngle,
    String? solverArguments,
  }) => post('/api/align/ekos_align_set', {
        if (binIndex != null) 'bin_index': binIndex,
        if (solverAction != null) 'solver_action': solverAction,
        if (solverMode != null) 'solver_mode': solverMode,
        if (targetRaHours != null) 'target_ra_hours': targetRaHours,
        if (targetDecDeg != null) 'target_dec_deg': targetDecDeg,
        if (targetPositionAngle != null) 'target_position_angle': targetPositionAngle,
        if (solverArguments != null) 'solver_arguments': solverArguments,
      });
  Future<Map<String, dynamic>> polarAlignStart({double raOffsetMin = 30, double exposureSec = 5}) =>
      post('/api/align/polar_align/run', {
        'ra_offset_min': raOffsetMin, 'exposure_sec': exposureSec,
      });
  Future<Map<String, dynamic>> polarAlignStatus(String runId) =>
      get('/api/align/polar_align/$runId');
  Future<void> polarAlignAbort(String runId) =>
      post('/api/align/polar_align/$runId/abort');

  // Setup
  Future<Map<String, dynamic>> setupProfiles() => get('/api/setup/profiles');
  Future<Map<String, dynamic>> setupActiveDrivers() => get('/api/setup/active_drivers');

  // Scheduler
  Future<Map<String, dynamic>> schedulerWeatherSafe() => get('/api/scheduler/weather_safe');
  Future<Map<String, dynamic>> schedulerSkyState() => get('/api/scheduler/sky_state');
  Future<Map<String, dynamic>> schedulerJobs() => get('/api/scheduler/jobs');
  Future<Map<String, dynamic>> schedulerAddJob(Map<String, dynamic> job) =>
      post('/api/scheduler/jobs', job);
  Future<Map<String, dynamic>> schedulerCheckConditions(String jobId) =>
      post('/api/scheduler/jobs/$jobId/check_conditions');
  Future<void> schedulerDeleteJob(String jobId) async {
    final uri = _u('/api/scheduler/jobs/$jobId');
    final r = await _http.delete(uri, headers: _authHeaders).timeout(const Duration(seconds: 10));
    if (r.statusCode >= 300) throw ApiException(r.statusCode, r.body);
  }
  Future<List<String>> devices() async {
    final r = await get('/api/system/devices');
    return ((r['devices'] as List?) ?? []).cast<String>();
  }

  // INDI panel
  Future<List<dynamic>> indiDeviceProperties(String dev) async {
    final r = await get('/api/indi/devices/$dev/properties');
    return (r['properties'] as List?) ?? [];
  }

  Future<void> indiSet(String dev, String name, Map<String, dynamic> values) async {
    await post('/api/indi/devices/$dev/properties/$name', {'values': values});
  }

  Future<void> indiRefresh({String device = '', String name = ''}) =>
      post('/api/indi/refresh${_qs({'device': device, 'name': name})}');

  Future<void> indiConnect(String device) =>
      post('/api/indi/devices/$device/connect');
  Future<void> indiDisconnect(String device) =>
      post('/api/indi/devices/$device/disconnect');

  // Mount
  Future<Map<String, dynamic>> mountStatus({String? device}) =>
      get('/api/mount/status', _maybe(device));
  Future<void> mountGoto(double ra, double dec, {String action = 'track', String? device}) =>
      post('/api/mount/goto', {'ra': ra, 'dec': dec, 'action': action, if (device != null) 'device': device});
  Future<void> mountPark({String? device}) => post('/api/mount/park', _maybeBody(device));
  Future<void> mountUnpark({String? device}) => post('/api/mount/unpark', _maybeBody(device));
  Future<void> mountAbort({String? device}) => post('/api/mount/abort', _maybeBody(device));
  Future<void> mountTrack({required bool on, String? mode, String? device}) =>
      post('/api/mount/track', {'on': on, if (mode != null) 'mode': mode, if (device != null) 'device': device});
  Future<void> mountSlew({required String dir, required bool active, String? device}) =>
      post('/api/mount/slew', {'direction': dir, 'active': active, if (device != null) 'device': device});
  Future<void> mountSlewRate(String rate, {String? device}) =>
      post('/api/mount/slew_rate', {'rate': rate, if (device != null) 'device': device});

  // Camera
  Future<Map<String, dynamic>> cameraStatus({String? device}) =>
      get('/api/camera/status', _maybe(device));
  Future<void> cameraExpose(double seconds, {String? device}) =>
      post('/api/camera/expose', {'seconds': seconds, if (device != null) 'device': device});
  Future<void> cameraAbort({String? device}) => post('/api/camera/abort', _maybeBody(device));
  Future<void> cameraCooler(bool on, {double? target, String? device}) =>
      post('/api/camera/cooler', {'on': on, if (target != null) 'target': target, if (device != null) 'device': device});
  Future<void> cameraGain(double v, {String? device}) =>
      post('/api/camera/gain', {'value': v, if (device != null) 'device': device});
  Future<void> cameraOffset(double v, {String? device}) =>
      post('/api/camera/offset', {'value': v, if (device != null) 'device': device});
  Future<void> cameraBinning(int x, int y, {String? device}) =>
      post('/api/camera/binning', {'x': x, 'y': y, if (device != null) 'device': device});
  Future<void> cameraFrameType(String t, {String? device}) =>
      post('/api/camera/frame_type', {'type': t, if (device != null) 'device': device});
  Future<void> cameraTransferFormat(String fmt, {String? device}) =>
      post('/api/camera/transfer_format', {'format': fmt, if (device != null) 'device': device});
  Future<void> cameraCaptureFormat(String fmt, {String? device}) =>
      post('/api/camera/capture_format', {'format': fmt, if (device != null) 'device': device});
  Future<void> cameraUploadSetup({String? device, String mode = 'BOTH', String? dir, String? prefix}) =>
      post('/api/camera/upload_setup', {
        'mode': mode,
        if (device != null) 'device': device,
        if (dir != null) 'dir': dir,
        if (prefix != null) 'prefix': prefix,
      });

  // Capture via Ekos (DBus)
  Future<Map<String, dynamic>> captureEkosAlive() => get('/api/capture/ekos_alive');
  Future<Map<String, dynamic>> captureEkosRun({
    required List<Map<String, dynamic>> jobs,
    String? target,
    String train = '',
    bool master = true,
    bool autoStart = true,
    // v0.2.36: override dither lato app (pannello Guide → Dither config)
    double? ditherAmount,           // px
    double? ditherSettleTime,       // sec
    double? ditherSettlePixels,     // max RMS px durante settling
    int? ditherFrequency,           // dither ogni N frame (>=1)
    bool? ditherRaOnly,             // dither solo RA
  }) => post('/api/capture/ekos_run', {
    'jobs': jobs,
    if (target != null) 'target': target,
    'train': train,
    'master': master,
    'auto_start': autoStart,
    if (ditherAmount != null) 'ditherAmount': ditherAmount,
    if (ditherSettleTime != null) 'ditherSettleTime': ditherSettleTime,
    if (ditherSettlePixels != null) 'ditherSettlePixels': ditherSettlePixels,
    if (ditherFrequency != null) 'ditherFrequency': ditherFrequency,
    if (ditherRaOnly != null) 'ditherRaOnly': ditherRaOnly,
  });
  /// v0.2.56: avvia la sequenza GIÀ pianificata nella Capture queue di Ekos,
  /// senza clear/load dei job dell'app. Rispetta esattamente quello che
  /// l'utente ha configurato a mano nella UI di Ekos sul desktop.
  /// Se [autoDither] è null, il bridge legge DitherEnabled da Ekos [Guide].
  Future<Map<String, dynamic>> captureEkosStartExisting({
    String train = '',
    bool? autoDither,
  }) => post('/api/capture/ekos_start_existing', {
    'train': train,
    if (autoDither != null) 'auto_dither': autoDither,
  });
  /// v0.2.36: legge i parametri dither correntemente configurati in Ekos
  /// (kstarsrc [Guide]). Usato dal pannello "Dither config" per il
  /// pulsante "Sincronizza da Ekos".
  Future<Map<String, dynamic>> ekosDitherSettings() =>
      get('/api/capture/ekos_dither_settings');
  /// v0.3.6: stato live del watcher auto-dither (bridge-native).
  Future<Map<String, dynamic>> autoDitherStatus() =>
      get('/api/capture/auto_dither_status');
  Future<Map<String, dynamic>> captureEkosStatus() => get('/api/capture/ekos_status');
  Future<void> captureEkosAbort() => post('/api/capture/ekos_abort');
  Future<void> captureEkosClear() => post('/api/capture/ekos_clear');

  // Observation orchestrator (slew + plate solve + guide + capture)
  Future<Map<String, dynamic>> observationRun({
    String? targetName,
    double? raHours,
    double? decDeg,
    required List<Map<String, dynamic>> jobs,
    bool doPlateSolve = true,
    bool doAutofocus = false,
    bool doGuideCalibrate = false,
    bool doGuideStart = true,
    bool useEkosCapture = true,
  }) => post('/api/observation/run', {
    if (targetName != null) 'target_name': targetName,
    if (raHours != null) 'ra_hours': raHours,
    if (decDeg != null) 'dec_deg': decDeg,
    'jobs': jobs,
    'do_plate_solve': doPlateSolve,
    'do_autofocus': doAutofocus,
    'do_guide_calibrate': doGuideCalibrate,
    'do_guide_start': doGuideStart,
    'use_ekos_capture': useEkosCapture,
  });
  Future<Map<String, dynamic>> observationStatus(String runId) =>
      get('/api/observation/$runId');
  Future<void> observationAbort(String runId) =>
      post('/api/observation/$runId/abort');

  // Focuser
  Future<Map<String, dynamic>> focuserStatus({String? device}) =>
      get('/api/focuser/status', _maybe(device));
  Future<void> focuserAbs(int pos, {String? device}) =>
      post('/api/focuser/abs', {'position': pos, if (device != null) 'device': device});
  Future<void> focuserRel(int steps, String direction, {String? device}) =>
      post('/api/focuser/rel', {'steps': steps, 'direction': direction, if (device != null) 'device': device});
  Future<void> focuserAbort({String? device}) => post('/api/focuser/abort', _maybeBody(device));
  Future<Map<String, dynamic>> focuserAutofocusStart({
    String? device, String? camera, int stepSize = 50, int nSteps = 9, double exposureSec = 2.0,
  }) => post('/api/focuser/autofocus', {
    if (device != null) 'device': device,
    if (camera != null) 'camera': camera,
    'step_size': stepSize, 'n_steps': nSteps, 'exposure_sec': exposureSec,
  });
  Future<Map<String, dynamic>> focuserAutofocusStatus(String runId) =>
      get('/api/focuser/autofocus/$runId');
  Future<void> focuserAutofocusAbort(String runId) =>
      post('/api/focuser/autofocus/$runId/abort');

  // === EKOS AUTOFOCUS ===
  Future<Map<String, dynamic>> focuserEkosState({String train = ''}) =>
      get('/api/focuser/ekos_state', {'train': train});
  Future<Map<String, dynamic>> focuserEkosStart({
    String train = '', int? boxSize, int? stepSize, int? maxTravel,
    double? tolerance, List<int>? binning, String? filter,
  }) => post('/api/focuser/ekos_start', {
        'train': train,
        if (boxSize != null) 'box_size': boxSize,
        if (stepSize != null) 'step_size': stepSize,
        if (maxTravel != null) 'max_travel': maxTravel,
        if (tolerance != null) 'tolerance': tolerance,
        if (binning != null) 'binning': binning,
        if (filter != null) 'filter': filter,
      });
  Future<Map<String, dynamic>> focuserEkosAbort({String train = ''}) =>
      post('/api/focuser/ekos_abort', {'train': train});
  Future<Map<String, dynamic>> focuserEkosCurve() =>
      get('/api/focuser/ekos_curve');
  Future<Map<String, dynamic>> focuserEkosCurveReset() =>
      post('/api/focuser/ekos_curve_reset');

  // Filter wheel
  Future<Map<String, dynamic>> filterStatus({String? device}) =>
      get('/api/filter_wheel/status', _maybe(device));
  Future<void> filterSelect(int slot, {String? device}) =>
      post('/api/filter_wheel/select', {'slot': slot, if (device != null) 'device': device});

  // Guide
  Future<Map<String, dynamic>> guideStatus() => get('/api/guide/status');
  // v0.2.57: guider INTERNO di Ekos (via DBus lato bridge). Alternativo a PHD2.
  Future<Map<String, dynamic>> guideBackend() => get('/api/guide/backend');
  Future<Map<String, dynamic>> guideEkosStatus() => get('/api/guide/ekos_status');
  /// v0.2.59: frame LIVE della camera di guida col guider INTERNO.
  /// Il bridge apre un client INDI dedicato (:7624) e legge lo stream BLOB.
  /// `timeout` e' quello lato server: teniamolo basso cosi' risponde 409
  /// prima che scada il timeout HTTP quando la camera non sta esponendo.
  Future<Map<String, dynamic>> guideEkosFullFrame({int maxDim = 1024, int timeout = 12}) =>
      get('/api/guide/ekos_full_frame', {'max_dim': '$maxDim', 'timeout': '$timeout'});
  Future<void> guideEkosStart() => post('/api/guide/ekos_start');
  Future<void> guideEkosStop() => post('/api/guide/ekos_stop');
  Future<void> guideEkosCalibrate() => post('/api/guide/ekos_calibrate');
  Future<void> guideEkosDither() => post('/api/guide/ekos_dither');
  Future<void> guideEkosLoop() => post('/api/guide/ekos_loop');
  Future<void> guideStart({Map<String, dynamic>? p}) => post('/api/guide/start', p);
  Future<void> guideStop() => post('/api/guide/stop');
  Future<Map<String, dynamic>> guideDither({
    double amount = 3.0,
    bool raOnly = false,
    double? settleTime,
    double? settlePixels,
    double? settleTimeout,
    bool wait = true,
  }) {
    final body = <String, dynamic>{
      'amount': amount,
      'ra_only': raOnly,
      'wait': wait,
    };
    if (settleTime != null) body['settle_time'] = settleTime;
    if (settlePixels != null) body['settle_pixels'] = settlePixels;
    if (settleTimeout != null) body['settle_timeout'] = settleTimeout;
    // Con wait=true il bridge blocca fino al SettleDone (puo' durare quanto
    // settle_timeout): allunghiamo il timeout HTTP di conseguenza.
    final to = wait
        ? Duration(seconds: ((settleTimeout ?? 60.0) + 25).toInt())
        : const Duration(seconds: 15);
    return post('/api/guide/dither', body, to);
  }

  /// Connette TUTTE le periferiche del profilo PHD2 attivo (RPC set_connected).
  Future<Map<String, dynamic>> guideConnectEquipment({
    bool connected = true,
    int? profileId,
  }) {
    final body = <String, dynamic>{'connected': connected};
    if (profileId != null) body['profile_id'] = profileId;
    return post('/api/guide/connect_equipment', body);
  }

  Future<void> guideLoop() => post('/api/guide/loop');
  Future<void> guideClearCalibration() => post('/api/guide/clear_calibration');
  Future<void> guidePause(bool paused) => post('/api/guide/pause', {'paused': paused});
  Future<void> guideCalibrate() => post('/api/guide/calibrate');
  Future<void> guideFindStar() => post('/api/guide/find_star');
  Future<Map<String, dynamic>> guideProfile() => get('/api/guide/profile');

  /// Riquadro intorno alla stella di guida via PHD2 (get_star_image).
  /// Ritorna {frame, width, height, star_x, star_y, png_base64}.
  /// Lancia ApiException(409) se PHD2 non ha una stella selezionata.
  Future<Map<String, dynamic>> guideStarImage() => get('/api/guide/star_image');

  /// v0.3.3: frame INTERO della camera di guida via PHD2 save_image.
  /// È quello che vedi nella finestra principale di PHD2 sul desktop.
  /// Ritorna {width, height, png_base64}. Internamente PHD2 salva un FITS,
  /// il bridge lo legge, applica auto-stretch e ritorna PNG.
  /// [maxDim] = downscale lato max (px). 0 = nessun resize.
  ///
  /// v0.2.35 fix: prima il query string era embedded nel path (`'/api/guide/full_frame?max_dim=$maxDim'`).
  /// Uri.replace(path:) URL-encodava il `?` come `%3F` → bridge restituiva 404 Not Found
  /// perché cercava un path literal con `%3F`. Adesso usiamo il secondo arg `q`
  /// come tutti gli altri endpoint del file.
  Future<Map<String, dynamic>> guideFullFrame({int maxDim = 1024}) =>
      get('/api/guide/full_frame', {'max_dim': '$maxDim'});

  // === Planetario KStars (v0.2.40) ========================================
  /// Esporta il SkyMap di KStars come PNG + info di focus (centro RA/Dec, FOV).
  /// Ritorna {width, height, png_base64, focus:{ra_deg,dec_deg,fov_deg,object,...}}.
  Future<Map<String, dynamic>> skymapView({int width = 900, int height = 600, double? fovDeg}) =>
      get('/api/skymap/view', {
        'width': '$width', 'height': '$height',
        if (fovDeg != null) 'fov': '$fovDeg',
      });
  /// Centro/FOV/oggetto correnti del planetario.
  Future<Map<String, dynamic>> skymapFocus() => get('/api/skymap/focus');
  /// Centra il planetario su un oggetto per nome (es. "M 51").
  Future<Map<String, dynamic>> skymapCenterObject(String object) =>
      post('/api/skymap/center', {'object': object});
  /// Centra il planetario su coordinate (gradi).
  Future<Map<String, dynamic>> skymapCenterCoords(double raDeg, double decDeg) =>
      post('/api/skymap/center', {'ra_deg': raDeg, 'dec_deg': decDeg});
  /// Centra sulla posizione corrente del telescopio.
  Future<Map<String, dynamic>> skymapCenterTelescope() =>
      post('/api/skymap/center_telescope', {});
  /// Zoom: fovDeg target oppure dir "in"/"out".
  Future<Map<String, dynamic>> skymapZoom({double? fovDeg, String? dir}) =>
      post('/api/skymap/zoom', {
        if (fovDeg != null) 'fov_deg': fovDeg,
        if (dir != null) 'dir': dir,
      });
  /// FASE 2: tap-to-goto. Manda il pixel toccato; il bridge ricentra lì e
  /// ritorna le coordinate precise + oggetto candidato per la conferma goto.
  Future<Map<String, dynamic>> skymapTap(int x, int y, int width, int height) =>
      post('/api/skymap/tap', {'x': x, 'y': y, 'width': width, 'height': height});
  /// Scorri la mappa trascinando: dx/dy = spostamento del dito in px immagine.
  Future<Map<String, dynamic>> skymapPan(double dx, double dy, int width, int height) =>
      post('/api/skymap/pan', {'dx': dx, 'dy': dy, 'width': width, 'height': height});

  // Observatory
  Future<Map<String, dynamic>> observatoryStatus() => get('/api/observatory/status');
  Future<void> domeShutter(String device, bool open) =>
      post('/api/observatory/dome/shutter', {'device': device, 'open': open});
  Future<void> dustCap(String device, bool park) =>
      post('/api/observatory/dust_cap', {'device': device, 'park': park});
  Future<void> flatPanel(String device, {required bool on, double? intensity}) =>
      post('/api/observatory/flat_panel', {'device': device, 'on': on, if (intensity != null) 'intensity': intensity});

  // Files
  Future<Map<String, dynamic>> filesRecent({int limit = 50}) =>
      get('/api/files/recent', {'limit': '$limit'});
  // v0.2.48 (P5): navigazione cartelle dentro la home del Pi.
  Future<Map<String, dynamic>> filesBrowse({String path = '', bool onlyDirs = false, String exts = ''}) =>
      get('/api/files/browse', {
        'path': path, 'only_dirs': '$onlyDirs', if (exts.isNotEmpty) 'exts': exts,
      });
  Future<Map<String, dynamic>> filesRoots() => get('/api/files/roots');
  // v0.2.48 (P6): sequenze .esq sul Pi.
  Future<Map<String, dynamic>> listSequences() => get('/api/capture/list_sequences');
  Future<Map<String, dynamic>> loadSequenceFile(String path, {bool autoStart = false}) =>
      post('/api/capture/load_sequence_file', {'path': path, 'auto_start': autoStart});
  Future<Uint8List> filePreview(String path, {bool thumbnail = false}) =>
      getBytes('/api/files/preview', {'path': path, 'thumbnail': '$thumbnail'});
  Future<Map<String, dynamic>> fileDelete(String path) async {
    final uri = _u('/api/files/file', {'path': path});
    final r = await _http.delete(uri, headers: _authHeaders).timeout(const Duration(seconds: 10));
    if (r.statusCode >= 300) throw ApiException(r.statusCode, r.body);
    return jsonDecode(r.body);
  }
  Future<Map<String, dynamic>> filesDeleteMany(List<String> paths) =>
      post('/api/files/delete_many', {'paths': paths});
  Future<Map<String, dynamic>> filesDiskUsage() => get('/api/files/disk_usage');

  Map<String, String>? _maybe(String? device) =>
      device == null ? null : {'device': device};
  Map<String, dynamic>? _maybeBody(String? device) =>
      device == null ? null : {'device': device};
  String _qs(Map<String, String> m) {
    final entries = m.entries.where((e) => e.value.isNotEmpty);
    if (entries.isEmpty) return '';
    return '?' + entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
  }

  void close() => _http.close();
}

class ApiException implements Exception {
  final int status;
  final String body;
  ApiException(this.status, this.body);
  @override
  String toString() => 'ApiException($status): $body';
}
