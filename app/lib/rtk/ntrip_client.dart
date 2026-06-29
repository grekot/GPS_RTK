import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Konfiguracja połączenia z casterem NTRIP (np. ASG-EUPOS).
class NtripConfig {
  const NtripConfig({
    required this.host,
    this.port = 2101,
    required this.mountpoint,
    this.username = '',
    this.password = '',
  });

  final String host;
  final int port;
  final String mountpoint;
  final String username;
  final String password;

  bool get isComplete => host.isNotEmpty && mountpoint.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'mountpoint': mountpoint,
        'username': username,
        'password': password,
      };

  factory NtripConfig.fromJson(Map<String, dynamic> j) => NtripConfig(
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 2101,
        mountpoint: j['mountpoint'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
      );
}

/// Żądanie NTRIP v1 (GET mountpointu z autoryzacją Basic).
String buildNtripRequest(NtripConfig c,
    {String userAgent = 'NTRIP gps_rtk/1.0'}) {
  final auth = base64Encode(utf8.encode('${c.username}:${c.password}'));
  return 'GET /${c.mountpoint} HTTP/1.0\r\n'
      'User-Agent: $userAgent\r\n'
      'Authorization: Basic $auth\r\n'
      'Accept: */*\r\n'
      '\r\n';
}

/// Czy nagłówek odpowiedzi castera oznacza sukces (ICY 200 / HTTP 200).
bool ntripResponseOk(String header) {
  final h = header.toUpperCase();
  return h.contains('ICY 200') || h.contains(' 200 OK') || h.contains('200 OK');
}

/// Koniec nagłówka odpowiedzi: dla „ICY …\r\n" jednolinijkowy, dla HTTP do
/// pustej linii (\r\n\r\n). Zwraca indeks pierwszego bajtu RTCM lub -1.
int ntripHeaderEnd(List<int> buf) {
  final head = String.fromCharCodes(buf.take(min(buf.length, 16))).toUpperCase();
  if (head.startsWith('ICY')) {
    for (var i = 0; i + 1 < buf.length; i++) {
      if (buf[i] == 13 && buf[i + 1] == 10) return i + 2;
    }
    return -1;
  }
  for (var i = 0; i + 3 < buf.length; i++) {
    if (buf[i] == 13 && buf[i + 1] == 10 && buf[i + 2] == 13 && buf[i + 3] == 10) {
      return i + 4;
    }
  }
  return -1;
}

/// Klient strumienia poprawek NTRIP. Łączy się z casterem, po nagłówku przekazuje
/// surowe RTCM przez [onRtcm], a [sendGga] wysyła pozycję (VRS). Auto-reconnect.
class NtripClient {
  NtripClient(
    this.config, {
    this.onRtcm,
    this.onStatus,
    this.onReady,
    this.staleTimeout = const Duration(seconds: 12),
  });

  final NtripConfig config;
  final void Function(List<int> rtcm)? onRtcm;
  final void Function(String status)? onStatus;

  /// Wywoływane, gdy strumień jest gotowy (po nagłówku) — źródło wysyła wtedy
  /// od razu GGA, żeby VRS ustawiła się szybko, bez czekania na timer.
  final void Function()? onReady;

  /// Gdy przez ten czas nie przyjdą żadne poprawki mimo „połączono", łącze jest
  /// martwe (VRS przestała nadawać / half-open TCP) → wymuszamy reconnect.
  /// Automatyzuje to, co użytkownik robił ręcznie przez STOP→START.
  final Duration staleTimeout;

  Socket? _socket;
  bool _running = false;
  bool _headerDone = false;
  int _rtcmBytes = 0; // ile bajtów poprawek przyszło w bieżącym połączeniu
  Timer? _staleTimer;
  final List<int> _buf = [];

  Future<void> start() async {
    _running = true;
    await _connect();
  }

  Future<void> stop() async {
    _running = false;
    _staleTimer?.cancel();
    _staleTimer = null;
    _socket?.destroy();
    _socket = null;
  }

  void sendGga(String gga) {
    try {
      _socket?.add(utf8.encode('$gga\r\n'));
    } catch (_) {/* zerwane łącze — reconnect zajmie się resztą */}
  }

  Future<void> _connect() async {
    if (!_running) return;
    _headerDone = false;
    _rtcmBytes = 0;
    _staleTimer?.cancel();
    _buf.clear();
    try {
      onStatus?.call('NTRIP: łączenie…');
      final s = await Socket.connect(config.host, config.port,
          timeout: const Duration(seconds: 15));
      _socket = s;
      s.add(utf8.encode(buildNtripRequest(config)));
      await s.flush();
      s.listen(_onData,
          onError: (_) => _reconnect(), onDone: _reconnect, cancelOnError: true);
    } catch (e) {
      onStatus?.call('NTRIP nieosiągalny: $e');
      _reconnect();
    }
  }

  void _onData(List<int> data) {
    if (_headerDone) {
      if (_rtcmBytes == 0) onStatus?.call('NTRIP: odbieram poprawki');
      _rtcmBytes += data.length;
      _armStale(); // świeże poprawki — resetuj watchdog
      onRtcm?.call(data);
      return;
    }
    _buf.addAll(data);
    final end = ntripHeaderEnd(_buf);
    if (end == -1) return;
    final header = String.fromCharCodes(_buf.sublist(0, end));
    // Zła/nieistniejąca nazwa mountpointu → caster odsyła sourcetable
    // („SOURCETABLE 200 OK"), co zawiera „200 OK" i mylnie wygląda na sukces.
    if (header.toUpperCase().contains('SOURCETABLE')) {
      onStatus?.call('NTRIP: mountpoint nieznany — caster zwrócił listę stacji. '
          'Sprawdź nazwę mountpointu.');
      _socket?.destroy();
      return;
    }
    if (!ntripResponseOk(header)) {
      onStatus?.call('Caster odrzucił: ${header.split('\r\n').first}');
      _socket?.destroy();
      return;
    }
    _headerDone = true;
    onStatus?.call('NTRIP: połączono');
    onReady?.call(); // wyślij GGA od razu → szybkie ustawienie VRS
    _armStale();
    final rest = _buf.sublist(end);
    if (rest.isNotEmpty) {
      onStatus?.call('NTRIP: odbieram poprawki');
      _rtcmBytes += rest.length;
      onRtcm?.call(rest);
    }
    _buf.clear();
  }

  /// Uzbraja watchdog braku poprawek: po [staleTimeout] bez RTCM wymusza
  /// reconnect (świeży strumień + GGA), bez czekania na ręczny STOP→START.
  void _armStale() {
    _staleTimer?.cancel();
    _staleTimer = Timer(staleTimeout, () {
      if (!_running) return;
      onStatus?.call('NTRIP: brak poprawek ${staleTimeout.inSeconds} s — '
          'wznawiam połączenie…');
      _socket?.destroy(); // → onDone → _reconnect
    });
  }

  void _reconnect() {
    _staleTimer?.cancel();
    _socket = null;
    // Połączono, ale zero poprawek przed zerwaniem = baza nie nadaje.
    if (_headerDone && _rtcmBytes == 0) {
      onStatus?.call('NTRIP: połączono, ale baza nie wysłała poprawek '
          '(offline lub zła nazwa mountpointu).');
    }
    if (_running) {
      onStatus?.call('NTRIP: ponawiam za 5 s…');
      Future.delayed(const Duration(seconds: 5), _connect);
    }
  }
}

/// Żądanie sourcetable (lista mountpointów castera — `GET /`). Autoryzację
/// Basic dokłada tylko, gdy podano login (sourcetable zwykle jest publiczna).
String buildSourcetableRequest(
  String username,
  String password, {
  String userAgent = 'NTRIP gps_rtk/1.0',
}) {
  final b = StringBuffer()
    ..write('GET / HTTP/1.0\r\n')
    ..write('User-Agent: $userAgent\r\n');
  if (username.isNotEmpty) {
    final auth = base64Encode(utf8.encode('$username:$password'));
    b.write('Authorization: Basic $auth\r\n');
  }
  b.write('Accept: */*\r\n\r\n');
  return b.toString();
}

/// Pojedyncza pozycja sourcetable (linia `STR`) — jeden mountpoint castera.
class SourcetableEntry {
  const SourcetableEntry({
    required this.mountpoint,
    this.identifier = '',
    this.format = '',
    this.navSystem = '',
    this.country = '',
    this.lat,
    this.lon,
  });

  final String mountpoint; // pole 1 — nazwa używana w GET /<mountpoint>
  final String identifier; // pole 2 — opis/lokalizacja stacji
  final String format; // pole 3 — np. „RTCM 3.2"
  final String navSystem; // pole 6 — np. „GPS+GLO+GAL"
  final String country; // pole 8 — np. „POL"
  final double? lat; // pole 9 — szerokość stacji [°]
  final double? lon; // pole 10 — długość stacji [°]

  /// Parsuje linię `STR;mount;ident;format;…`. Zwraca null, gdy to nie STR
  /// albo brak nazwy mountpointu.
  static SourcetableEntry? parse(String line) {
    if (!line.startsWith('STR;')) return null;
    final f = line.split(';');
    if (f.length < 2 || f[1].trim().isEmpty) return null;
    String at(int i) => i < f.length ? f[i].trim() : '';
    return SourcetableEntry(
      mountpoint: f[1].trim(),
      identifier: at(2),
      format: at(3),
      navSystem: at(6),
      country: at(8),
      lat: double.tryParse(at(9)),
      lon: double.tryParse(at(10)),
    );
  }
}

/// Wyłuskuje mountpointy (linie `STR`) z treści odpowiedzi SOURCETABLE.
List<SourcetableEntry> parseSourcetable(String body) {
  final out = <SourcetableEntry>[];
  for (final line in const LineSplitter().convert(body)) {
    if (line == 'ENDSOURCETABLE') break;
    final e = SourcetableEntry.parse(line);
    if (e != null) out.add(e);
  }
  return out;
}

/// Pobiera sourcetable z castera (`GET /`) i zwraca listę mountpointów.
/// Rzuca [SocketException]/[TimeoutException] przy problemach z siecią oraz
/// [FormatException], gdy odpowiedź nie jest sourcetable (zła ścieżka/host).
Future<List<SourcetableEntry>> fetchSourcetable(
  String host,
  int port, {
  String username = '',
  String password = '',
  Duration timeout = const Duration(seconds: 15),
}) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  final buf = <int>[];
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  final sub = socket.listen(
    (data) {
      buf.addAll(data);
      // Caster zwykle zamyka łącze po sourcetable, ale ENDSOURCETABLE pozwala
      // zakończyć od razu, gdyby trzymał połączenie otwarte (NTRIP v2/HTTP).
      if (_endsSourcetable(buf)) finish();
    },
    onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    },
    onDone: finish,
    cancelOnError: true,
  );
  try {
    socket.add(utf8.encode(buildSourcetableRequest(username, password)));
    await socket.flush();
    await done.future.timeout(timeout, onTimeout: () {});
  } finally {
    await sub.cancel();
    socket.destroy();
  }

  final text = utf8.decode(buf, allowMalformed: true);
  if (!text.toUpperCase().contains('SOURCETABLE 200')) {
    final firstLine = const LineSplitter().convert(text).take(1).join();
    throw FormatException(
      firstLine.isEmpty ? 'Caster nie zwrócił sourcetable.' : firstLine,
    );
  }
  return parseSourcetable(text);
}

/// Szuka „ENDSOURCETABLE" w ogonie bufora (znacznik końca listy).
bool _endsSourcetable(List<int> buf) {
  final start = buf.length > 64 ? buf.length - 64 : 0;
  return String.fromCharCodes(buf.sublist(start)).contains('ENDSOURCETABLE');
}
