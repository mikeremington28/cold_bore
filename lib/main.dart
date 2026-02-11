import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:io';

const String kBackupSchemaVersion = '2026-02-05';




// --- Web-only: download a text file (no-op on mobile/desktop) ---
void _downloadTextFileWeb(String filename, String content, {String mimeType = 'text/plain'}) {
  if (!kIsWeb) return;
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.children.add(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
}


Future<String?> _pickWebJsonFile() async {
  if (!kIsWeb) return null;
  final input = html.FileUploadInputElement()
    ..accept = '.json,application/json'
    ..multiple = false;
  input.click();
  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;

  final file = files.first;
  final reader = html.FileReader();
  reader.readAsText(file);
  await reader.onLoadEnd.first;
  final result = reader.result;
  return result is String ? result : null;
}

String _cleanText(String s) {
  // Fix common mojibake / smart punctuation that can show up from copy/paste.
  return s
      .replaceAll('â€¢', '•')
      .replaceAll('â€™', "'")
      .replaceAll('â€˜', "'")
      .replaceAll('â€œ', '"')
      .replaceAll('â€�', '"')
      .replaceAll('â€”', '-')
      .replaceAll('â†’', '->')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('’', "'")
      .replaceAll('—', '-')
      .replaceAll('→', '->');
}


// --- Export helpers (no extra packages required) -----------------------------

int _crc32(Uint8List bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xEDB88320 & mask);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

String _csvEscape(String v) {
  final needs = v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
  if (!needs) return v;
  return '"${v.replaceAll('"', '""')}"';
}

String _fmtDateIso(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _fmtDateTimeIso(DateTime d) {
  final ymd = _fmtDateIso(d);
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  final ss = d.second.toString().padLeft(2, '0');
  return '$ymd $hh:$mm:$ss';
}


const String kExportSchemaVersion = '2026-01-22';

String _sessionEvidenceId(TrainingSession s) {
  // Canonical JSON-like structure to generate a stable integrity identifier
  // for a session record. This is NOT cryptographic; it is intended as a
  // lightweight tamper-evident checksum for review workflows.
  final map = <String, Object?>{
    'id': s.id,
    'userId': s.userId,
    'dateTime': _fmtDateTimeIso(s.dateTime),
    'locationName': s.locationName,
    'latitude': s.latitude,
    'longitude': s.longitude,
    'temperatureF': s.temperatureF,
    'windSpeedMph': s.windSpeedMph,
    'windDirectionDeg': s.windDirectionDeg,
    'rifleId': s.rifleId,
    'ammoLotId': s.ammoLotId,
    'notes': s.notes,
    'shots': s.shots
        .map((x) => {
              'id': x.id,
              'time': _fmtDateTimeIso(x.time),
              'isColdBore': x.isColdBore,
              'isBaseline': x.isBaseline,
              'distance': x.distance,
              'result': x.result,
              'notes': x.notes,
              'photos': x.photos
                  .map((p) => {
                        'id': p.id,
                        'time': _fmtDateTimeIso(p.time),
                        'caption': p.caption,
                      })
                  .toList(),
            })
        .toList(),
    'trainingDope': s.trainingDope
        .map((d) => {
              'id': d.id,
              'time': _fmtDateTimeIso(d.time),
              'rifleId': d.rifleId,
              'ammoLotId': d.ammoLotId,
              'distance': d.distance,
              'distanceUnit': d.distanceUnit.name,
              'elevation': d.elevation,
              'elevationUnit': d.elevationUnit.name,
              'elevationNotes': d.elevationNotes,
              'windType': d.windType.name,
              'windValue': d.windValue,
              'windNotes': d.windNotes,
              'windageLeft': d.windageLeft,
              'windageRight': d.windageRight,
            })
        .toList(),
  };

  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(map)));
  return _crc32(bytes).toRadixString(16).padLeft(8, '0');
}


String _buildCasePacket(AppState state, {
  required TrainingSession s,
  bool redactLocation = true,
  bool includePhotoBase64 = false,
}) {
  final rifle = s.rifleId == null ? null : state.findRifleById(s.rifleId!);
  final ammo = s.ammoLotId == null ? null : state.findAmmoLotById(s.ammoLotId!);

  final evidenceId = _sessionEvidenceId(s);

  String rifleLabel() {
    if (rifle != null) return '${rifle.name} (${rifle.caliber})';
    if (s.rifleId == null) return '-';
    return 'Deleted rifle (${s.rifleId})';
  }

  String ammoLabel() {
    if (ammo != null) {
      final m = (ammo.manufacturer ?? ammo.name ?? '').trim();
      final prefix = m.isEmpty ? '' : '$m ';
      return '${prefix}${ammo.bullet} ${ammo.grain}gr';
    }
    if (s.ammoLotId == null) return '-';
    return 'Deleted ammo (${s.ammoLotId})';
  }

  final b = StringBuffer();
  b.writeln('COLD BORE - CASE PACKET');
  b.writeln('Schema: $kExportSchemaVersion');
  b.writeln('Generated: ${_fmtDateTimeIso(DateTime.now())}');
  b.writeln('');
  b.writeln('SESSION');
  b.writeln('• Session ID: ${s.id}');
  b.writeln('• Evidence ID (CRC32): $evidenceId');
  b.writeln('• User ID: ${s.userId}');
  b.writeln('• Date/Time: ${_fmtDateTimeIso(s.dateTime)}');
  b.writeln('• Location: ${redactLocation ? '[REDACTED]' : (s.locationName.isEmpty ? '-' : s.locationName)}');
  if (!redactLocation) {
    b.writeln('• GPS: ${s.latitude?.toStringAsFixed(6) ?? '-'}, ${s.longitude?.toStringAsFixed(6) ?? '-'}');
  } else {
    b.writeln('• GPS: [REDACTED]');
  }
  b.writeln('• Rifle: ${rifleLabel()}');
  b.writeln('• Ammo: ${ammoLabel()}');

  if (s.temperatureF != null || s.windSpeedMph != null || s.windDirectionDeg != null) {
    b.writeln('• Weather: '
        '${s.temperatureF != null ? '${s.temperatureF!.toStringAsFixed(1)}°F' : '-'}; '
        '${s.windSpeedMph != null ? '${s.windSpeedMph!.toStringAsFixed(1)} mph' : '-'} '
        '${s.windDirectionDeg != null ? '@ ${s.windDirectionDeg}°' : ''}');
  }

  b.writeln('');
  b.writeln('NOTES');
  b.writeln(s.notes.trim().isEmpty ? '-' : s.notes.trim());

  // Session-level photos (caption-only notes)
  b.writeln('');
  b.writeln('SESSION PHOTOS (NOTES)');
  if (s.photos.isEmpty) {
    b.writeln('-');
  } else {
    for (final p in s.photos) {
      b.writeln('• ${_fmtDateTimeIso(p.time)} - ${p.caption} (id: ${p.id})');
    }
  }

  // Dope
  b.writeln('');
  b.writeln('TRAINING DOPE');
  if (s.trainingDope.isEmpty) {
    b.writeln('-');
  } else {
    for (final d in s.trainingDope) {
      b.writeln('• ${d.distance} - Elev: ${d.elevation} ${d.elevationUnit.name} '
          '(notes: ${d.elevationNotes.isEmpty ? '-' : d.elevationNotes}); '
          'Wind: ${d.windType.name}: ${d.windValue} '
          '(notes: ${d.windNotes.isEmpty ? '-' : d.windNotes})');
    }
  }

  // Shots
  b.writeln('');
  b.writeln('SHOTS');
  if (s.shots.isEmpty) {
    b.writeln('-');
  } else {
    for (final sh in s.shots) {
      b.writeln('• ${_fmtDateTimeIso(sh.time)}'
          '${sh.isColdBore ? ' [COLD]' : ''}'
          '${sh.isBaseline ? ' [BASELINE]' : ''}');
      b.writeln('  - Distance: ${sh.distance}');
      b.writeln('  - Result: ${sh.result}');
      b.writeln('  - Notes: ${sh.notes.trim().isEmpty ? '-' : sh.notes.trim()}');

      if (sh.photos.isEmpty) {
        b.writeln('  - Photos: -');
      } else {
        b.writeln('  - Photos (${sh.photos.length}):');
        for (final ph in sh.photos) {
          final crc = _crc32(ph.bytes);
          b.writeln('    • ${_fmtDateTimeIso(ph.time)} - ${ph.caption} '
              '(id: ${ph.id}; bytes: ${ph.bytes.length}; crc32: 0x${crc.toRadixString(16).padLeft(8, '0')})');
          if (includePhotoBase64) {
            final b64 = base64Encode(ph.bytes);
            b.writeln('      base64: $b64');
          }
        }
      }
    }
  }

  b.writeln('');
  b.writeln('END OF CASE PACKET');
  return _cleanText(b.toString());
}


String _buildCourtReport(AppState state, {required bool redactLocation}) {
  final now = DateTime.now();
  final b = StringBuffer();
  b.writeln('COLD BORE - DATA EXPORT (TEXT)');
  b.writeln('Schema: $kExportSchemaVersion');
  b.writeln('Generated: ${_fmtDateTimeIso(now)}');
  b.writeln('Active user: ${state.activeUser?.name ?? '-'} (${state.activeUser?.identifier ?? '-'})');
  b.writeln('Users: ${state.users.length} | Rifles: ${state.rifles.length} | Ammo lots: ${state.ammoLots.length} | Sessions: ${state.allSessions.length}');
  b.writeln('');
  for (final sess in state.allSessions) {
    b.writeln('SESSION ${sess.id} | ${_fmtDateTimeIso(sess.dateTime)} | user ${sess.userId}');
    b.writeln('Evidence ID: ${_sessionEvidenceId(sess)}');
    b.writeln('Location: ${redactLocation ? '[REDACTED]' : sess.locationName}');
    final rifle = state.rifleById(sess.rifleId);
    final ammo = state.ammoById(sess.ammoLotId);
    final rifleLabel = rifle == null
        ? (sess.rifleId == null ? '-' : 'Deleted (${sess.rifleId})')
        : '${(rifle.name ?? 'Rifle').trim()} (${rifle.caliber})';
    final ammoLabel = ammo == null
        ? (sess.ammoLotId == null ? '-' : 'Deleted (${sess.ammoLotId})')
        : '${(ammo.name ?? 'Ammo').trim()} (${ammo.caliber})';
    b.writeln('Rifle: $rifleLabel');
    b.writeln('Ammo: $ammoLabel');
    if (sess.trainingDope.isNotEmpty) b.writeln('Training DOPE count: ${sess.trainingDope.length}');
    if (sess.shots.isNotEmpty) b.writeln('Shots count: ${sess.shots.length}');
    b.writeln('');
  }

  final bytes = Uint8List.fromList(utf8.encode(b.toString()));
  b.writeln('CRC32(export_text): ${_crc32(bytes).toRadixString(16).padLeft(8, '0')}');
  return b.toString();
}

String _buildCsvBundle(AppState state, {required bool redactLocation}) {
  final b = StringBuffer();
  b.writeln('### rifles.csv');
  b.writeln('rifle_id,caliber,nickname,manufacturer,model,serial_number,barrel_length,twist_rate,purchase_date,purchase_price,purchase_location,notes,dope');
  for (final r in state.rifles) {
    b.writeln([
      r.id,
      r.caliber,
      r.name ?? '',
      r.manufacturer ?? '',
      r.model ?? '',
      r.serialNumber ?? '',
      r.barrelLength ?? '',
      r.twistRate ?? '',
      r.purchaseDate == null ? '' : _fmtDateIso(r.purchaseDate!),
      r.purchasePrice ?? '',
      r.purchaseLocation ?? '',
      r.notes,
      r.dope,
    ].map((x) => _csvEscape(x.toString())).join(','));
  }
  b.writeln('');
  b.writeln('### ammo_lots.csv');
  b.writeln('ammo_lot_id,caliber,grain,name,bullet,bc,manufacturer,lot_number,purchase_date,purchase_price,notes');
  for (final a in state.ammoLots) {
    b.writeln([
      a.id,
      a.caliber,
      a.grain.toString(),
      a.name ?? '',
      a.bullet,
      a.ballisticCoefficient?.toString() ?? '',
      a.manufacturer ?? '',
      a.lotNumber ?? '',
      a.purchaseDate == null ? '' : _fmtDateIso(a.purchaseDate!),
      a.purchasePrice ?? '',
      a.notes,
    ].map((x) => _csvEscape(x.toString())).join(','));
  }
  b.writeln('');
  b.writeln('### sessions.csv');
  b.writeln('session_id,evidence_id,user_id,datetime,location_name,latitude,longitude,temperature_f,wind_speed_mph,wind_direction_deg,rifle_id,rifle_label,ammo_lot_id,ammo_label,notes');
  for (final sess in state.allSessions) {
    final rifle = state.rifleById(sess.rifleId);
    final ammo = state.ammoById(sess.ammoLotId);
    final rifleLabel = rifle == null
        ? (sess.rifleId == null ? '' : 'Deleted (${sess.rifleId})')
        : '${(rifle.name ?? 'Rifle').trim()} (${rifle.caliber})';
    final ammoLabel = ammo == null
        ? (sess.ammoLotId == null ? '' : 'Deleted (${sess.ammoLotId})')
        : '${(ammo.name ?? 'Ammo').trim()} (${ammo.caliber})';
    b.writeln([
      sess.id,
      _sessionEvidenceId(sess),
      sess.userId,
      _fmtDateTimeIso(sess.dateTime),
      redactLocation ? '[REDACTED]' : sess.locationName,
      redactLocation ? '' : (sess.latitude?.toString() ?? ''),
      redactLocation ? '' : (sess.longitude?.toString() ?? ''),
      sess.temperatureF?.toString() ?? '',
      sess.windSpeedMph?.toString() ?? '',
      sess.windDirectionDeg?.toString() ?? '',
      sess.rifleId ?? '',
      rifleLabel,
      sess.ammoLotId ?? '',
      ammoLabel,
      sess.notes,
    ].map((x) => _csvEscape(x.toString())).join(','));
  }

b.writeln('');
b.writeln('### shots.csv');
b.writeln('shot_id,session_id,session_evidence_id,time,is_cold_bore,is_baseline,distance,result,notes,photo_count');
for (final sess in state.allSessions) {
  final evid = _sessionEvidenceId(sess);
  for (final shot in sess.shots) {
    b.writeln([
      shot.id,
      sess.id,
      evid,
      _fmtDateTimeIso(shot.time),
      shot.isColdBore ? '1' : '0',
      shot.isBaseline ? '1' : '0',
      shot.distance,
      shot.result,
      shot.notes,
      shot.photos.length.toString(),
    ].map((x) => _csvEscape(x.toString())).join(','));
  }
}

b.writeln('');
b.writeln('### training_dope.csv');
b.writeln('dope_id,session_id,session_evidence_id,time,rifle_id,ammo_lot_id,distance,distance_unit,elevation,elevation_unit,elevation_notes,wind_type,wind_value,wind_notes,windage_left,windage_right');
for (final sess in state.allSessions) {
  final evid = _sessionEvidenceId(sess);
  for (final d in sess.trainingDope) {
    b.writeln([
      d.id,
      sess.id,
      evid,
      _fmtDateTimeIso(d.time),
      d.rifleId ?? '',
      d.ammoLotId ?? '',
      d.distance.toString(),
      d.distanceUnit.name,
      d.elevation.toString(),
      d.elevationUnit.name,
      d.elevationNotes,
      d.windType.name,
      d.windValue,
      d.windNotes,
      d.windageLeft.toString(),
      d.windageRight.toString(),
    ].map((x) => _csvEscape(x.toString())).join(','));
  }
}


  final bytes = Uint8List.fromList(utf8.encode(b.toString()));
  b.writeln('');
  b.writeln('### integrity');
  b.writeln('crc32_csv_bundle,${_crc32(bytes).toRadixString(16).padLeft(8, '0')}');
  return b.toString();
}

// ---------------------------------------------------------------------------
enum ScopeUnit { mil, moa, inches }

enum DistanceUnit { yards, meters }

enum ElevationUnit { mil, moa, inches }

enum WindType { fullValue, clock }

class DistanceKey {
  final double value;
  final DistanceUnit unit;

  const DistanceKey(this.value, this.unit);

  @override
  bool operator ==(Object other) =>
      other is DistanceKey && other.value == value && other.unit == unit;

  @override
  int get hashCode => value.hashCode ^ unit.hashCode;
}

class DopeEntry {
  final String id;
  final DateTime time;
  final String? rifleId;
  final String? ammoLotId;
  final double distance;
  final DistanceUnit distanceUnit;
  final double elevation;
  final ElevationUnit elevationUnit;
  final String elevationNotes;
  final WindType windType;
  final String windValue;
  final String windNotes;
  final double windageLeft;
  final double windageRight;
  DopeEntry({
    required this.id,
    required this.time,
    this.rifleId,
    this.ammoLotId,
    required this.distance,
    required this.distanceUnit,
    required this.elevation,
    required this.elevationUnit,
    required this.elevationNotes,
    required this.windType,
    required this.windValue,
    required this.windNotes,
    this.windageLeft = 0.0,
    this.windageRight = 0.0,
  });
}


// Separate DOPE entry model for Rifle DOPE list (simple text fields).
// This avoids colliding with the main DopeEntry model used for working/training DOPE.
class RifleDopeEntry {
  final String id;
  final String distance;
  final String elevation;
  final String windage;
  final String notes;
  const RifleDopeEntry({
    required this.id,
    required this.distance,
    required this.elevation,
    required this.windage,
    required this.notes,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'distance': distance,
        'elevation': elevation,
        'windage': windage,
        'notes': notes,
      };

  static RifleDopeEntry fromMap(Map<String, dynamic> m) => RifleDopeEntry(
        id: (m['id'] ?? '').toString(),
        distance: (m['distance'] ?? '').toString(),
        elevation: (m['elevation'] ?? '').toString(),
        windage: (m['windage'] ?? '').toString(),
        notes: (m['notes'] ?? '').toString(),
      );

  RifleDopeEntry copyWith({
    String? id,
    String? distance,
    String? elevation,
    String? windage,
    String? notes,
  }) {
    return RifleDopeEntry(
      id: id ?? this.id,
      distance: distance ?? this.distance,
      elevation: elevation ?? this.elevation,
      windage: windage ?? this.windage,
      notes: notes ?? this.notes,
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint(details.toString());
  };

  runZonedGuarded(() async {
    bool firebaseReady = false;
    String? firebaseError;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
    } catch (e, st) {
      firebaseReady = false;
      firebaseError = '$e';
      debugPrint('Firebase init failed: $e');
      debugPrint('$st');
    }

    runApp(ColdBoreApp(firebaseReady: firebaseReady, firebaseError: firebaseError));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error');
    debugPrint('$stack');
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text('Startup error:\n\n$error\n\n$stack'),
            ),
          ),
        ),
      ),
    ));
  });
}

///
/// Cold Bore (MVP Shell + First Feature Set)
/// - Unlock (biometrics attempt; falls back to allow unlock during MVP)
/// - Users (in-memory)
/// - Equipment: Rifles + Ammo Lots (in-memory)
/// - Sessions: assign rifle/ammo + add Cold Bore entries + photos + training DOPE
///
/// NOTE: Still "no database yet". We'll swap AppState storage to a real DB later.
class RifleServiceEntry {
  final String id;
  final String service;
  final DateTime date;
  final int roundsAtService;
  final String notes;

  const RifleServiceEntry({
    required this.id,
    required this.service,
    required this.date,
    required this.roundsAtService,
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'service': service,
        'date': date.toIso8601String(),
        'roundsAtService': roundsAtService,
        'notes': notes,
      };

  static RifleServiceEntry fromMap(Map<String, dynamic> m) => RifleServiceEntry(
        id: (m['id'] ?? '').toString(),
        service: (m['service'] ?? '').toString(),
        date: DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now(),
        roundsAtService: (m['roundsAtService'] is num)
            ? (m['roundsAtService'] as num).round()
            : int.tryParse((m['roundsAtService'] ?? '0').toString()) ?? 0,
        notes: (m['notes'] ?? '').toString(),
      );
}


class ColdBoreApp extends StatelessWidget {
  final bool firebaseReady;
  final String? firebaseError;

  const ColdBoreApp({super.key, this.firebaseReady = false, this.firebaseError});

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return MaterialApp(
        title: 'Cold Bore',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Text(
                  'Firebase failed to start.\n\n'
                  'Error:\n${firebaseError ?? "Unknown"}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Cold Bore',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  final AppState _state = AppState();

  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _state.ensureSeedData();
  }

  @override
  Widget build(BuildContext context) {
    // Usable-now mode: skip biometrics/unlock screen (local_auth removed for iOS 26 stability).
    return HomeShell(state: _state);
  }

}

/// Simple in-memory state (replace with DB later).
class AppState extends ChangeNotifier {
  final List<UserProfile> _users = [];
  final List<Rifle> _rifles = [];
  final List<AmmoLot> _ammoLots = [];
  final List<TrainingSession> _sessions = [];
  final Map<String, Map<DistanceKey, DopeEntry>> _workingDopeRifleOnly = {};
  final Map<String, Map<DistanceKey, DopeEntry>> _workingDopeRifleAmmo = {};

  UserProfile? _activeUser;


  // Current environment (optional)
  double? _latitude;
  double? _longitude;
  double? _temperatureF;
  double? _windSpeedMph;
  int? _windDirectionDeg;

  double? get latitude => _latitude;
  double? get longitude => _longitude;
  double? get temperatureF => _temperatureF;
  double? get windSpeedMph => _windSpeedMph;
  int? get windDirectionDeg => _windDirectionDeg;

  void setEnvironment({
    double? latitude,
    double? longitude,
    double? temperatureF,
    double? windSpeedMph,
    int? windDirectionDeg,
  }) {
    _latitude = latitude;
    _longitude = longitude;
    _temperatureF = temperatureF;
    _windSpeedMph = windSpeedMph;
    _windDirectionDeg = windDirectionDeg;
    notifyListeners();
  }

  List<UserProfile> get users => List.unmodifiable(_users);
  List<Rifle> get rifles => List.unmodifiable(_rifles);
  List<AmmoLot> get ammoLots => List.unmodifiable(_ammoLots);

  List<TrainingSession> get sessions => List.unmodifiable(
        _sessions.where((s) => s.memberUserIds.contains(_activeUser?.id)),
      );
  /// Convenience lookups used by exports/case packets.
  Rifle? findRifleById(String id) {
    try {
      return _rifles.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  AmmoLot? findAmmoLotById(String id) {
    try {
      return _ammoLots.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }



  UserProfile? get activeUser => _activeUser;

  Map<String, Map<DistanceKey, DopeEntry>> get workingDopeRifleOnly => _workingDopeRifleOnly;
  Map<String, Map<DistanceKey, DopeEntry>> get workingDopeRifleAmmo => _workingDopeRifleAmmo;

  List<TrainingSession> get allSessions => List.unmodifiable(_sessions);

  void ensureSeedData() {
    if (_users.isNotEmpty) return;

    final u = UserProfile(
      id: _newId(),
      name: 'Demo User',
      identifier: 'DEMO',
    );
    _users.add(u);
    _activeUser = u;

    // Start with a clean slate (no placeholder rifle/ammo).
    final sid = _newId();
    _sessions.add(
      TrainingSession(
        id: _newId(),
        userId: u.id,
        memberUserIds: [u.id],
        dateTime: DateTime.now(),
        locationName: '',
        notes: '',
        latitude: null,
        longitude: null,
        temperatureF: null,
        windSpeedMph: null,
        windDirectionDeg: null,
        rifleId: null,
        ammoLotId: null,
        shots: const [],
        photos: const [],
        sessionPhotos: const [],
        trainingDope: const [],
        trainingDopeByString: {sid: const []},
        shotsByString: {sid: const []},
        strings: [
          SessionStringMeta(
            id: sid,
            startedAt: DateTime.now(),
            endedAt: null,
            rifleId: null,
            ammoLotId: null,
          ),
        ],
        activeStringId: sid,
      ),
    );

    notifyListeners();
  }

  void addUser({required String name, required String identifier}) {
    final u = UserProfile(
      id: _newId(),
      name: name.trim(),
      identifier: identifier.trim(),
    );
    _users.add(u);
    _activeUser ??= u;
    notifyListeners();
  }

  void switchUser(UserProfile user) {
    _activeUser = user;
    notifyListeners();
  }

  void addRifle({
    ScopeUnit? scopeUnit,
    int manualRoundCount = 0,
    String? scopeMake,
    String? scopeModel,
    String? scopeSerial,
    String? scopeMount,
    String? scopeNotes,
    required String name,
    required String caliber,
    String notes = '',
    String dope = '',
    String? manufacturer,
    String? model,
    String? serialNumber,
    String? barrelLength,
    String? twistRate,
    DateTime? purchaseDate,
    String? purchasePrice,
    String? purchaseLocation,
  }) {
    _rifles.add(
      Rifle(id: _newId(),
      scopeUnit: scopeUnit ?? ScopeUnit.mil,
        manualRoundCount: manualRoundCount,
        scopeMake: scopeMake?.trim().isEmpty == true ? null : scopeMake?.trim(),
        scopeModel: scopeModel?.trim().isEmpty == true ? null : scopeModel?.trim(),
        scopeSerial: scopeSerial?.trim().isEmpty == true ? null : scopeSerial?.trim(),
        scopeMount: scopeMount?.trim().isEmpty == true ? null : scopeMount?.trim(),
        scopeNotes: scopeNotes?.trim().isEmpty == true ? null : scopeNotes?.trim(),
        name: name.trim().isEmpty ? null : name.trim(),
        caliber: caliber.trim(),
        notes: notes.trim(),
        dope: dope.trim(),
        manufacturer: manufacturer?.trim().isEmpty == true ? null : manufacturer?.trim(),
        model: model?.trim().isEmpty == true ? null : model?.trim(),
        serialNumber: serialNumber?.trim().isEmpty == true ? null : serialNumber?.trim(),
        barrelLength: barrelLength?.trim().isEmpty == true ? null : barrelLength?.trim(),
        twistRate: twistRate?.trim().isEmpty == true ? null : twistRate?.trim(),
        purchaseDate: purchaseDate,
        purchasePrice: purchasePrice?.trim().isEmpty == true ? null : purchasePrice?.trim(),
        purchaseLocation: purchaseLocation?.trim().isEmpty == true ? null : purchaseLocation?.trim(),
      ),
    );
    notifyListeners();
  }


  void updateRifle({
    required String rifleId,
    String? name,
    required String caliber,
    String notes = '',
    String dope = '',
    ElevationUnit? preferredUnit,
    ScopeUnit? scopeUnit,
    String? scopeMake,
    String? scopeModel,
    String? scopeSerial,
    String? scopeMount,
    String? scopeNotes,
    String? manufacturer,
    String? model,
    String? serialNumber,
    String? barrelLength,
    String? twistRate,
    DateTime? purchaseDate,
    String? purchasePrice,
    String? purchaseLocation,
  }) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx < 0) return;
    final r = _rifles[idx];
    _rifles[idx] = r.copyWith(
      name: (name == null || name.trim().isEmpty) ? null : name.trim(),
      caliber: caliber.trim(),
      notes: notes.trim(),
      dope: dope.trim(),
      preferredUnit: preferredUnit ?? r.preferredUnit,
      manufacturer: manufacturer?.trim().isEmpty == true ? null : manufacturer?.trim(),
      model: model?.trim().isEmpty == true ? null : model?.trim(),
      serialNumber: serialNumber?.trim().isEmpty == true ? null : serialNumber?.trim(),
      barrelLength: barrelLength?.trim().isEmpty == true ? null : barrelLength?.trim(),
      twistRate: twistRate?.trim().isEmpty == true ? null : twistRate?.trim(),
      purchaseDate: purchaseDate,
      purchasePrice: purchasePrice?.trim().isEmpty == true ? null : purchasePrice?.trim(),
      purchaseLocation: purchaseLocation?.trim().isEmpty == true ? null : purchaseLocation?.trim(),
      scopeUnit: scopeUnit ?? r.scopeUnit,
      scopeMake: scopeMake?.trim().isEmpty == true ? null : scopeMake?.trim(),
        scopeModel: scopeModel?.trim().isEmpty == true ? null : scopeModel?.trim(),
        scopeSerial: scopeSerial?.trim().isEmpty == true ? null : scopeSerial?.trim(),
        scopeMount: scopeMount?.trim().isEmpty == true ? null : scopeMount?.trim(),
        scopeNotes: scopeNotes?.trim().isEmpty == true ? null : scopeNotes?.trim(),
    );    notifyListeners();
  }

  /// Deletes a rifle from active equipment lists. Historical sessions keep the rifleId;
  /// UI/export should show "Deleted" when the rifle record no longer exists.
  void deleteRifle(String rifleId) {
    _rifles.removeWhere((r) => r.id == rifleId);
    _workingDopeRifleOnly.remove(rifleId);
    _workingDopeRifleAmmo.removeWhere((k, _) => k.startsWith('${rifleId}_'));
    notifyListeners();
  }

  /// Deletes an ammo lot from active equipment lists. Historical sessions keep the ammoLotId.
  void deleteAmmoLot(String ammoLotId) {
    _ammoLots.removeWhere((a) => a.id == ammoLotId);
    _workingDopeRifleAmmo.removeWhere((k, _) => k.endsWith('_$ammoLotId'));
    notifyListeners();
  }

  void addRifleDopeEntry(String rifleId, RifleDopeEntry entry) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx == -1) return;
    final r = _rifles[idx];
    final list = List<RifleDopeEntry>.from(r.dopeEntries);
    list.add(entry);
    _rifles[idx] = r.copyWith(dopeEntries: list);
    notifyListeners();
  }

  void updateRifleDopeEntry(String rifleId, RifleDopeEntry entry) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx == -1) return;
    final r = _rifles[idx];
    final list = List<RifleDopeEntry>.from(r.dopeEntries);
    final eIdx = list.indexWhere((e) => e.id == entry.id);
    if (eIdx == -1) return;
    list[eIdx] = entry;
    _rifles[idx] = r.copyWith(dopeEntries: list);
    notifyListeners();
  }

  void deleteRifleDopeEntry(String rifleId, String entryId) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx == -1) return;
    final r = _rifles[idx];
    final list = r.dopeEntries.where((e) => e.id != entryId).toList();
    _rifles[idx] = r.copyWith(dopeEntries: list);
    notifyListeners();
  }

  void updateRifleDope({required String rifleId, required String dope}) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx < 0) return;
    final r = _rifles[idx];
    _rifles[idx] = r.copyWith(dope: dope.trim());
    notifyListeners();
  }

  void addAmmoLot({
    String? name,
    required String caliber,
    required int grain,
    String bullet = '',
    String notes = '',
    String? manufacturer,
    String? lotNumber,
    DateTime? purchaseDate,
    String? purchasePrice,
    double? ballisticCoefficient,
  }) {
    _ammoLots.add(
      AmmoLot(
        id: _newId(),
        name: (name == null || name.trim().isEmpty) ? null : name.trim(),
        caliber: caliber.trim(),
        grain: grain,
        bullet: bullet.trim(),
        notes: notes.trim(),
        manufacturer: manufacturer?.trim().isEmpty == true ? null : manufacturer?.trim(),
        lotNumber: lotNumber?.trim().isEmpty == true ? null : lotNumber?.trim(),
        purchaseDate: purchaseDate,
        purchasePrice: purchasePrice?.trim().isEmpty == true ? null : purchasePrice?.trim(),
        ballisticCoefficient: ballisticCoefficient,
      ),
    );
    notifyListeners();
  }


  void updateAmmoLot({
    required String ammoLotId,
    String? name,
    required String caliber,
    required int grain,
    required String bullet,
    String notes = '',
    String? manufacturer,
    String? lotNumber,
    DateTime? purchaseDate,
    String? purchasePrice,
    double? ballisticCoefficient,
  }) {
    final idx = _ammoLots.indexWhere((a) => a.id == ammoLotId);
    if (idx < 0) return;
    _ammoLots[idx] = AmmoLot(
      id: _ammoLots[idx].id,
      name: (name?.trim().isEmpty == true ? null : name?.trim()),
      caliber: caliber.trim(),
        grain: grain,
        bullet: bullet.trim(),
      notes: notes.trim(),
      manufacturer: manufacturer?.trim().isEmpty == true ? null : manufacturer?.trim(),
      lotNumber: lotNumber?.trim().isEmpty == true ? null : lotNumber?.trim(),
      purchaseDate: purchaseDate,
      purchasePrice: purchasePrice?.trim().isEmpty == true ? null : purchasePrice?.trim(),
      ballisticCoefficient: ballisticCoefficient,
    );
    notifyListeners();
  }

  TrainingSession? addSession({
    required String locationName,
    required DateTime dateTime,
    String notes = '',
    double? latitude,
    double? longitude,
    double? temperatureF,
    double? windSpeedMph,
    int? windDirectionDeg,
  }) {
    final user = _activeUser;
    if (user == null) return null;

    final stringId = _newId();

    final created = TrainingSession(
      id: _newId(),
      userId: user.id,
      memberUserIds: [user.id],
      dateTime: dateTime,
      locationName: locationName.trim(),
      notes: notes.trim(),
      latitude: latitude,
      longitude: longitude,
      temperatureF: temperatureF,
      windSpeedMph: windSpeedMph,
      windDirectionDeg: windDirectionDeg,
      rifleId: null,
      ammoLotId: null,
      shots: const [],
      photos: const [],
      sessionPhotos: const [],
      trainingDope: const [],
      trainingDopeByString: {stringId: const []},
      shotsByString: {stringId: const []},
      strings: [
        SessionStringMeta(
          id: stringId,
          startedAt: dateTime,
          endedAt: null,
          rifleId: null,
          ammoLotId: null,
        ),
      ],
      activeStringId: stringId,
    );

    _sessions.add(created);
    notifyListeners();
    return created;
  }

  TrainingSession? getSessionById(String id) {
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  void shareSessionWithUsers({
    required String sessionId,
    required List<String> userIds,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;

    final existing = _sessions[idx];
    final merged = <String>{
      ...existing.memberUserIds,
      ...userIds,
    }.toList();

    _sessions[idx] = existing.copyWith(memberUserIds: merged);
    notifyListeners();
  }

  Rifle? rifleById(String? id) {
    if (id == null) return null;
    try {
      return _rifles.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  AmmoLot? ammoById(String? id) {
    if (id == null) return null;
    try {
      return _ammoLots.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

    void updateSessionLoadout({
    required String sessionId,
    String? rifleId,
    String? ammoLotId,
    bool startNewString = true,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];

    String? nextRifleId = rifleId ?? s.rifleId;
    String? nextAmmoId = ammoLotId ?? s.ammoLotId;

    // If rifle changes, clear ammo when incompatible with the new rifle.
    if (nextRifleId != null && nextAmmoId != null) {
      final newRifle = rifleById(nextRifleId);
      final a = ammoById(nextAmmoId);
      if (newRifle != null && (a == null || a.caliber != newRifle.caliber)) {
        nextAmmoId = null;
      }
    }

    final loadoutChanged = (nextRifleId != s.rifleId) || (nextAmmoId != s.ammoLotId);
    if (!loadoutChanged) return;

    final now = DateTime.now();
    final currentStrings = [...s.strings];
    final activeIndex = currentStrings.indexWhere((x) => x.id == s.activeStringId);

    SessionStringMeta? activeMeta = activeIndex == -1 ? null : currentStrings[activeIndex];
    final activeHasLoadout = (activeMeta?.rifleId != null) && (activeMeta?.ammoLotId != null);
    final activeIsEmpty = (activeMeta?.rifleId == null) && (activeMeta?.ammoLotId == null);

    // If the active string has no loadout yet, just bind the initial selection to it (no prompt/new string).
    if (activeIndex != -1 && (activeIsEmpty || !activeHasLoadout)) {
      currentStrings[activeIndex] = activeMeta!.copyWith(
        rifleId: nextRifleId,
        ammoLotId: nextAmmoId,
      );
      _sessions[idx] = s.copyWith(
        rifleId: nextRifleId,
        ammoLotId: nextAmmoId,
        strings: currentStrings,
      );
      notifyListeners();
      return;
    }

    // If user is still selecting (missing either rifle or ammo), never create a new string yet.
    if (nextRifleId == null || nextAmmoId == null) {
      _sessions[idx] = s.copyWith(rifleId: nextRifleId, ammoLotId: nextAmmoId);
      notifyListeners();
      return;
    }

    // If we aren't starting a new string (user cancelled prompt), only update session-level display.
    if (!startNewString) {
      _sessions[idx] = s.copyWith(rifleId: nextRifleId, ammoLotId: nextAmmoId);
      notifyListeners();
      return;
    }

    // Close the active string (if any).
    if (activeIndex != -1 && currentStrings[activeIndex].endedAt == null) {
      currentStrings[activeIndex] = currentStrings[activeIndex].copyWith(endedAt: now);
    }

    final newStringId = _newId();
    currentStrings.add(
      SessionStringMeta(
        id: newStringId,
        startedAt: now,
        endedAt: null,
        rifleId: nextRifleId,
        ammoLotId: nextAmmoId,
      ),
    );

    _sessions[idx] = s.copyWith(
      rifleId: nextRifleId,
      ammoLotId: nextAmmoId,
      strings: currentStrings,
      activeStringId: newStringId,
      trainingDopeByString: {
        ...s.trainingDopeByString,
        newStringId: const <DopeEntry>[],
      },
      shotsByString: {
        ...s.shotsByString,
        newStringId: const <ShotEntry>[],
      },
    );
    notifyListeners();
  }


  void setActiveString({
    required String sessionId,
    required String stringId,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;
    final s = _sessions[idx];
    final st = s.strings.firstWhere((x) => x.id == stringId, orElse: () => s.strings.isNotEmpty ? s.strings.last : SessionStringMeta(id: stringId, startedAt: DateTime.now(), endedAt: null, rifleId: s.rifleId, ammoLotId: s.ammoLotId));
    _sessions[idx] = s.copyWith(
      activeStringId: stringId,
      // Snap loadout display to the string meta (if present)
      rifleId: st.rifleId ?? s.rifleId,
      ammoLotId: st.ammoLotId ?? s.ammoLotId,
    );
    notifyListeners();
  }

  void updateSessionNotes({
    required String sessionId,
    required String notes,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];
    _sessions[idx] = s.copyWith(notes: notes.trim());
    notifyListeners();
  }

  void addColdBoreEntry({
    required String sessionId,
    required DateTime time,
    required String distance,
    required String result,
    String notes = '',
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];

    final entry = ShotEntry(
      id: _newId(),
      time: time,
      isColdBore: true,
      isBaseline: false,
      distance: distance.trim(),
      result: result.trim(),
      notes: notes.trim(),
      photos: const [],
    );

        final sid = (s.activeStringId.isEmpty && s.strings.isNotEmpty) ? s.strings.last.id : s.activeStringId;
    final currentList = List<ShotEntry>.from(s.shotsByString[sid] ?? const <ShotEntry>[]);
    _sessions[idx] = s.copyWith(
      shots: [...s.shots, entry],
      shotsByString: {
        ...s.shotsByString,
        sid: [...currentList, entry],
      },
    );
    notifyListeners();
  }

  void addTrainingDope({
    required String sessionId,
    required DopeEntry entry,
    bool promote = true,
    bool rifleOnly = false,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];

    final String? rid = entry.rifleId ?? s.rifleId;
    final String? aid = entry.ammoLotId ?? s.ammoLotId;

    final updatedEntry = DopeEntry(
      id: _newId(),
      time: entry.time,
      rifleId: rid,
      ammoLotId: aid,
      distance: entry.distance,
      distanceUnit: entry.distanceUnit,
      elevation: entry.elevation,
      elevationUnit: entry.elevationUnit,
      elevationNotes: entry.elevationNotes,
      windType: entry.windType,
      windValue: entry.windValue,
      windNotes: entry.windNotes,
      windageLeft: entry.windageLeft,
      windageRight: entry.windageRight,
    );

    // Overwrite existing entry for same rifle+ammo+distance.
    final dk = DistanceKey(updatedEntry.distance, updatedEntry.distanceUnit);
    final filtered = s.trainingDope.where((e) {
      if (e.rifleId != updatedEntry.rifleId) return true;
      if (e.ammoLotId != updatedEntry.ammoLotId) return true;
      final edk = DistanceKey(e.distance, e.distanceUnit);
      return edk != dk;
    }).toList();

        final sid = (s.activeStringId.isEmpty && s.strings.isNotEmpty) ? s.strings.last.id : s.activeStringId;
    final currentList = List<DopeEntry>.from(s.trainingDopeByString[sid] ?? const <DopeEntry>[]);
    final filtered2 = currentList.where((e) {
      if (e.rifleId != updatedEntry.rifleId) return true;
      if (e.ammoLotId != updatedEntry.ammoLotId) return true;
      final edk = DistanceKey(e.distance, e.distanceUnit);
      return edk != dk;
    }).toList();

    _sessions[idx] = s.copyWith(
      trainingDope: [...filtered, updatedEntry],
      trainingDopeByString: {
        ...s.trainingDopeByString,
        sid: [...filtered2, updatedEntry],
      },
    );


    if (promote) {
      final rifleId = updatedEntry.rifleId;
      if (rifleId == null) return;

      String key;
      Map<String, Map<DistanceKey, DopeEntry>> workingMap;

      if (rifleOnly || updatedEntry.ammoLotId == null) {
        key = rifleId;
        workingMap = _workingDopeRifleOnly;
      } else {
        key = '${rifleId}_${updatedEntry.ammoLotId}';
        workingMap = _workingDopeRifleAmmo;
      }

      workingMap[key] ??= {};
      final dk = DistanceKey(updatedEntry.distance, updatedEntry.distanceUnit);
      workingMap[key]![dk] = updatedEntry;
    }

    notifyListeners();
  }

  ShotEntry? shotById({required String sessionId, required String shotId}) {
    final s = getSessionById(sessionId);
    if (s == null) return null;
    try {
      return s.shots.firstWhere((x) => x.id == shotId);
    } catch (_) {
      return null;
    }
  }

  /// Adds a cold-bore-only photo to a specific cold bore shot.
  void addColdBorePhoto({
    required String sessionId,
    required String shotId,
    required Uint8List bytes,
    String? caption,
  }) {
    final sIdx = _sessions.indexWhere((s) => s.id == sessionId);
    if (sIdx < 0) return;
    final s = _sessions[sIdx];

    final shotIdx = s.shots.indexWhere((x) => x.id == shotId);
    if (shotIdx < 0) return;
    final shot = s.shots[shotIdx];
    if (!shot.isColdBore) return;

    final photo = ColdBorePhoto(
      id: _newId(),
      time: DateTime.now(),
      bytes: bytes,
      caption: (caption ?? '').trim(),
    );

    final updatedShot = shot.copyWith(photos: [...shot.photos, photo]);
    final updatedShots = [...s.shots];
    updatedShots[shotIdx] = updatedShot;

    _sessions[sIdx] = s.copyWith(shots: updatedShots);
    notifyListeners();
  }

  /// Sets one cold bore entry as the baseline for the active user (and unsets any prior baseline).
  void setBaselineColdBore({required String sessionId, required String shotId}) {
    final user = _activeUser;
    if (user == null) return;

    for (var i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      if (s.userId != user.id) continue;

      final updatedShots = <ShotEntry>[];
      for (final sh in s.shots) {
        if (!sh.isColdBore) {
          updatedShots.add(sh);
          continue;
        }

        final shouldBeBaseline = (s.id == sessionId && sh.id == shotId);
        updatedShots.add(sh.copyWith(isBaseline: shouldBeBaseline));
      }

      _sessions[i] = s.copyWith(shots: updatedShots);
    }

    notifyListeners();
  }

  /// Returns the current baseline cold bore shot (if any) for the active user.
  ShotEntry? baselineColdBoreShot() {
    final user = _activeUser;
    if (user == null) return null;

    for (final s in _sessions.where((x) => x.userId == user.id)) {
      for (final sh in s.shots.where((x) => x.isColdBore && x.isBaseline)) {
        return sh;
      }
    }
    return null;
  }

  /// Finds the session that contains a given shot (useful for baseline lookups).
  TrainingSession? sessionContainingShot(String shotId) {
    final user = _activeUser;
    if (user == null) return null;
    for (final s in _sessions.where((x) => x.userId == user.id)) {
      if (s.shots.any((x) => x.id == shotId)) return s;
    }
    return null;
  }

  void addPhotoNote({
    required String sessionId,
    required DateTime time,
    required String caption,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];

    final p = PhotoNote(
      id: _newId(),
      time: time,
      caption: caption.trim(),
    );

    _sessions[idx] = s.copyWith(photos: [...s.photos, p]);
    notifyListeners();
  }


  /// Adds a session-level photo captured from the Session screen.
  void addSessionPhoto({
    required String sessionId,
    required Uint8List bytes,
    String? caption,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];

    final photo = SessionPhoto(
      id: _newId(),
      time: DateTime.now(),
      bytes: bytes,
      caption: (caption ?? '').trim(),
    );

    _sessions[idx] = s.copyWith(sessionPhotos: [...s.sessionPhotos, photo]);
    notifyListeners();
  }

  List<_ColdBoreRow> coldBoreRowsForActiveUser() {
    final user = _activeUser;
    if (user == null) return const [];

    final rows = <_ColdBoreRow>[];
    for (final s in _sessions.where((x) => x.userId == user.id)) {
      for (final shot in s.shots.where((x) => x.isColdBore)) {
        rows.add(
          _ColdBoreRow(
            session: s,
            shot: shot,
            rifle: rifleById(s.rifleId),
            ammo: ammoById(s.ammoLotId),
          ),
        );
      }
    }

    rows.sort((a, b) => b.shot.time.compareTo(a.shot.time));
    return rows;
  }

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  // Public helper used by widgets that need a fresh id without accessing a static private method.
  String newIdForChild() => _newId();


  int roundsFiredForRifle(String rifleId) {
    int total = 0;
    for (final s in _sessions) {
      for (final st in s.strings) {
        if (st.rifleId != rifleId) continue;
        final shots = s.shotsByString[st.id] ?? const <ShotEntry>[];
        total += shots.length;
      }
    }
    return total;
  }

  int totalRoundsForRifle(String rifleId) {
    final r = rifleById(rifleId);
    if (r == null) return 0;
    return r.manualRoundCount + roundsFiredForRifle(rifleId);
  }

  void addRifleService({
    required String rifleId,
    required RifleServiceEntry entry,
  }) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx < 0) return;
    final r = _rifles[idx];
    final next = [...r.services, entry]..sort((a, b) => b.date.compareTo(a.date));
    _rifles[idx] = r.copyWith(services: next);
    notifyListeners();
  }

  void deleteRifleService({
    required String rifleId,
    required String serviceId,
  }) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx < 0) return;
    final r = _rifles[idx];
    final next = r.services.where((e) => e.id != serviceId).toList();
    _rifles[idx] = r.copyWith(services: next);
    notifyListeners();
  }

  String exportBackupJson() {
    final payload = <String, dynamic>{
      'schema': kBackupSchemaVersion,
      'generatedAt': DateTime.now().toIso8601String(),
      'rifles': _rifles.map((r) => {
        'id': r.id,
        'name': r.name,
        'caliber': r.caliber,
        'manufacturer': r.manufacturer,
        'model': r.model,
        'serialNumber': r.serialNumber,
        'barrelLength': r.barrelLength,
        'twistRate': r.twistRate,
        'scopeUnit': r.scopeUnit.name,
        'notes': r.notes,
        'dope': r.dope,
        'manualRoundCount': r.manualRoundCount,
        'services': r.services.map((s) => s.toMap()).toList(),
        'purchaseDate': r.purchaseDate?.toIso8601String(),
        'purchasePrice': r.purchasePrice,
        'purchaseLocation': r.purchaseLocation,
        'scopeMake': r.scopeMake,
        'scopeModel': r.scopeModel,
        'scopeSerial': r.scopeSerial,
        'scopeMount': r.scopeMount,
        'scopeNotes': r.scopeNotes,
      }).toList(),
      'ammoLots': _ammoLots.map((a) => {
        'id': a.id,
        'name': a.name,
        'caliber': a.caliber,
        'manufacturer': a.manufacturer,
        'grain': a.grain,
        'bullet': a.bullet,
        'notes': a.notes,
        'lotNumber': a.lotNumber,
        'purchaseDate': a.purchaseDate?.toIso8601String(),
        'purchasePrice': a.purchasePrice,
        'ballisticCoefficient': a.ballisticCoefficient,
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  void importBackupJson(String jsonText, {required bool replaceExisting}) {
    final decoded = json.decode(jsonText);
    if (decoded is! Map) throw FormatException('Invalid backup JSON');
    final map = Map<String, dynamic>.from(decoded as Map);

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString().trim()) ?? 0;
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

String _toStr(dynamic v) => v == null ? '' : v.toString();


    final rifles = ((map['rifles'] as List?) ?? const []).map((x) {
      final m = Map<String, dynamic>.from(x as Map);
      return Rifle(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        caliber: (m['caliber'] as String?) ?? '',
        manufacturer: m['manufacturer'] as String?,
        model: m['model'] as String?,
        serialNumber: m['serialNumber'] as String?,
        barrelLength: m['barrelLength'] as String?,
        twistRate: m['twistRate'] as String?,
      scopeUnit: ScopeUnit.values.firstWhere(
          (e) => e.name == (m['scopeUnit'] as String? ?? 'mil'),
          orElse: () => ScopeUnit.mil,
        ),
        notes: (m['notes'] as String?) ?? '',
        dope: (m['dope'] as String?) ?? '',
        manualRoundCount: (m['manualRoundCount'] as num?)?.round() ?? 0,
        purchaseDate: (m['purchaseDate'] as String?) == null ? null : DateTime.tryParse(m['purchaseDate'] as String),
        purchasePrice: m['purchasePrice'] as String?,
        purchaseLocation: m['purchaseLocation'] as String?,
        scopeMake: m['scopeMake'] as String?,
        scopeModel: m['scopeModel'] as String?,
        scopeSerial: m['scopeSerial'] as String?,
        scopeMount: m['scopeMount'] as String?,
        scopeNotes: m['scopeNotes'] as String?,
      );
    }).toList();

    final ammo = ((map['ammoLots'] as List?) ?? const []).map((x) {
      final m = Map<String, dynamic>.from(x as Map);
      return AmmoLot(
        id: _toStr(m['id']).isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : _toStr(m['id']),
        caliber: _toStr(m['caliber']),
        grain: _toInt(m['grain']),
        name: (m['name'] as String?)?.trim(),
        bullet: (() {
          final b = _toStr(m['bullet']).trim();
          if (b.isNotEmpty) return b;
          final b2 = _toStr(m['bulletName']).trim();
          if (b2.isNotEmpty) return b2;
          return 'Bullet';
        })(),
        ballisticCoefficient: _toDouble(m['ballisticCoefficient'] ?? m['bc']),
        manufacturer: (m['manufacturer'] as String?)?.trim(),
        lotNumber: (m['lotNumber'] as String?)?.trim(),
        purchaseDate: (m['purchaseDate'] as String?) == null ? null : DateTime.tryParse((m['purchaseDate'] as String).trim()),
        purchasePrice: (m['purchasePrice'] as String?)?.trim(),
        notes: _toStr(m['notes']),
      );
    }).toList();

    if (replaceExisting) {
      _rifles..clear()..addAll(rifles);
      _ammoLots..clear()..addAll(ammo);
    } else {
      for (final r in rifles) {
        final i = _rifles.indexWhere((e) => e.id == r.id);
        if (i >= 0) _rifles[i] = r; else _rifles.add(r);
      }
      for (final a in ammo) {
        final i = _ammoLots.indexWhere((e) => e.id == a.id);
        if (i >= 0) _ammoLots[i] = a; else _ammoLots.add(a);
      }
    }
    notifyListeners();
  }

  // Merge rifles/ammo from a backup JSON into the current app state.
  // - Keeps existing IDs (so historical sessions/shots keep pointing at the right equipment)
  // - Adds any new rifles/ammo that don't match
  // - Overwrites scope fields on matched rifles when overwriteScope == true
  void mergeBackupJson(String jsonText, {bool overwriteScope = true}) {
    final decoded = json.decode(jsonText);
    if (decoded is! Map) throw FormatException('Invalid backup JSON');
    final map = Map<String, dynamic>.from(decoded as Map);

    final importedRifles = ((map['rifles'] as List?) ?? const []).map((x) {
      final m = Map<String, dynamic>.from(x as Map);
      return Rifle(
        id: (m['id'] ?? '').toString(),
        caliber: (m['caliber'] ?? '').toString(),
        name: (m['name'] as String?)?.toString(),
        manufacturer: (m['manufacturer'] as String?)?.toString(),
        model: (m['model'] as String?)?.toString(),
        serialNumber: (m['serialNumber'] as String?)?.toString(),
        barrelLength: (m['barrelLength'] as String?)?.toString(),
        twistRate: (m['twistRate'] as String?)?.toString(),
        purchaseDate: (m['purchaseDate'] as String?) != null
            ? DateTime.tryParse((m['purchaseDate'] as String))
            : null,
        purchasePrice: (m['purchasePrice'] as String?)?.toString(),
        purchaseLocation: (m['purchaseLocation'] as String?)?.toString(),
        notes: (m['notes'] as String?)?.toString() ?? '',
        dope: (m['dope'] as String?)?.toString() ?? '',
        scopeMake: (m['scopeMake'] as String?)?.toString(),
        scopeModel: (m['scopeModel'] as String?)?.toString(),
        scopeSerial: (m['scopeSerial'] as String?)?.toString(),
        scopeMount: (m['scopeMount'] as String?)?.toString(),
        scopeNotes: (m['scopeNotes'] as String?)?.toString(),
      scopeUnit: ScopeUnit.values.firstWhere(
          (u) => u.name == (m['scopeUnit'] ?? ScopeUnit.mil.name).toString(),
          orElse: () => ScopeUnit.mil,
        ),
        manualRoundCount: (m['manualRoundCount'] as int?) ?? 0,
        dopeEntries: (m['dopeEntries'] as List?)
                ?.map((e) => RifleDopeEntry.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );
    }).where((r) => r.caliber.trim().isNotEmpty).toList();

    final importedAmmo = ((map['ammoLots'] as List?) ?? const []).map((x) {
      final m = Map<String, dynamic>.from(x as Map);
      return AmmoLot(
        id: (m['id'] ?? '').toString(),
        caliber: (m['caliber'] ?? '').toString(),
        grain: (m['grain'] as num?)?.round() ?? 0,
        name: (m['name'] as String?)?.toString(),
        bullet: (m['bullet'] as String?) ?? '',
        ballisticCoefficient: (m['ballisticCoefficient'] as num?)?.toDouble(),
        manufacturer: (m['manufacturer'] as String?)?.toString(),
        lotNumber: (m['lotNumber'] as String?)?.toString(),
        purchaseDate: (m['purchaseDate'] as String?) != null
            ? DateTime.tryParse((m['purchaseDate'] as String))
            : null,
        purchasePrice: (m['purchasePrice'] as String?)?.toString(),
        notes: (m['notes'] as String?)?.toString() ?? '',
      );
    }).where((a) => a.caliber.trim().isNotEmpty).toList();

    int _findRifleMatchIndex(Rifle incoming) {
      String norm(dynamic s) => (s ?? '').toString().trim().toLowerCase();
      final inCal = norm(incoming.caliber);
      final inMan = norm(incoming.manufacturer);
      final inMod = norm(incoming.model);
      final inSer = norm(incoming.serialNumber);
      for (int i = 0; i < _rifles.length; i++) {
        final r = _rifles[i];
        if (norm(r.caliber) != inCal) continue;

        final rSer = norm(r.serialNumber);
        if (inSer.isNotEmpty && rSer.isNotEmpty) {
          if (inSer == rSer) return i;
          continue;
        }

        if (inMan.isNotEmpty && inMod.isNotEmpty) {
          if (norm(r.manufacturer) == inMan && norm(r.model) == inMod) return i;
        } else {
          // fallback: caliber + name
          if (norm(r.name).isNotEmpty && norm(r.name) == norm(incoming.name)) return i;
        }
      }
      return -1;
    }

    int _findAmmoMatchIndex(AmmoLot incoming) {
      String norm(dynamic s) => (s ?? '').toString().trim().toLowerCase();
      final inCal = norm(incoming.caliber);
      final inMan = norm(incoming.manufacturer);
      final inGr = norm(incoming.grain);
      final inBullet = norm(incoming.bullet);
      for (int i = 0; i < _ammoLots.length; i++) {
        final a = _ammoLots[i];
        if (norm(a.caliber) != inCal) continue;
        // Prefer match on manufacturer + grain + bullet
        final okMan = inMan.isEmpty || norm(a.manufacturer) == inMan;
        final okGr = inGr.isEmpty || norm(a.grain) == inGr;
        final okBullet = inBullet.isEmpty || norm(a.bullet) == inBullet;
        if (okMan && okGr && okBullet) return i;
        // fallback: caliber + name
        if (norm(a.name).isNotEmpty && norm(a.name) == norm(incoming.name)) return i;
      }
      return -1;
    }

    String? _preferExistingNullable(String? existing, String? incoming) {
  final e = (existing ?? '').trim();
  if (e.isNotEmpty) return existing;
  final n = (incoming ?? '').trim();
  return n.isEmpty ? existing : incoming;
}

DateTime? _preferExistingDateTime(DateTime? existing, DateTime? incoming) {
  return incoming ?? existing;
}


String _preferExistingRequired(String existing, String incoming) {
  final e = existing.trim();
  if (e.isNotEmpty) return existing;
  final n = incoming.trim();
  return n.isNotEmpty ? incoming : existing;
}

int _preferExistingInt(int existing, int incoming) => existing != 0 ? existing : incoming;

double? _preferExistingDouble(double? existing, double? incoming) => existing ?? incoming;


    // Merge rifles
    for (final incoming in importedRifles) {
      final idx = _findRifleMatchIndex(incoming);
      if (idx < 0) {
        _rifles.add(incoming);
        continue;
      }
      final existing = _rifles[idx];

      final updated = existing.copyWith(
        name: _preferExistingNullable(existing.name, incoming.name),
        manufacturer: _preferExistingNullable(existing.manufacturer, incoming.manufacturer),
        model: _preferExistingNullable(existing.model, incoming.model),
        serialNumber: _preferExistingNullable(existing.serialNumber, incoming.serialNumber),
        barrelLength: _preferExistingNullable(existing.barrelLength, incoming.barrelLength),
        twistRate: _preferExistingNullable(existing.twistRate, incoming.twistRate),
        purchaseDate: existing.purchaseDate ?? incoming.purchaseDate,
        purchasePrice: _preferExistingNullable(existing.purchasePrice, incoming.purchasePrice),
        purchaseLocation: _preferExistingNullable(existing.purchaseLocation, incoming.purchaseLocation),
        notes: _preferExistingRequired(existing.notes, incoming.notes),
        dope: _preferExistingRequired(existing.dope, incoming.dope),
        // Never overwrite history fields here (manualRoundCount, dopeEntries).
      scopeUnit: overwriteScope ? incoming.scopeUnit : existing.scopeUnit,
        scopeMake: overwriteScope ? incoming.scopeMake : existing.scopeMake,
        scopeModel: overwriteScope ? incoming.scopeModel : existing.scopeModel,
        scopeSerial: overwriteScope ? incoming.scopeSerial : existing.scopeSerial,
        scopeMount: overwriteScope ? incoming.scopeMount : existing.scopeMount,
        scopeNotes: overwriteScope ? incoming.scopeNotes : existing.scopeNotes,
      );

      _rifles[idx] = updated;
    }

    // Merge ammo
    for (final incoming in importedAmmo) {
      final idx = _findAmmoMatchIndex(incoming);
      if (idx < 0) {
        _ammoLots.add(incoming);
        continue;
      }
      final existing = _ammoLots[idx];
      final updated = AmmoLot(
  id: existing.id,
  caliber: existing.caliber,
  grain: _preferExistingInt(existing.grain, incoming.grain),
  name: _preferExistingNullable(existing.name, incoming.name),
  bullet: _preferExistingRequired(existing.bullet, incoming.bullet),
  ballisticCoefficient: _preferExistingDouble(existing.ballisticCoefficient, incoming.ballisticCoefficient),
  manufacturer: _preferExistingNullable(existing.manufacturer, incoming.manufacturer),
  lotNumber: _preferExistingNullable(existing.lotNumber, incoming.lotNumber),
  purchaseDate: _preferExistingDateTime(existing.purchaseDate, incoming.purchaseDate),
  purchasePrice: _preferExistingNullable(existing.purchasePrice, incoming.purchasePrice),
  notes: _preferExistingRequired(existing.notes, incoming.notes),
);
      _ammoLots[idx] = updated;
    }

    // Persist (if available in this app) and refresh UI
    try {
    } catch (_) {}
    notifyListeners();
  }

}

class UserProfile {
  final String id;
  final String? name;
  final String identifier;

  UserProfile({
    required this.id,
    this.name,
    required this.identifier,
  });
}

class Rifle {
  final String id;
  final String? name;
  final String caliber;

  final String notes;
  final String dope;
  final List<RifleDopeEntry> dopeEntries;

  final ElevationUnit preferredUnit;

  final ScopeUnit scopeUnit;

  final int manualRoundCount;

  final List<RifleServiceEntry> services;

  final String? scopeMake;
  final String? scopeModel;
  final String? scopeSerial;
  final String? scopeMount;
  final String? scopeNotes;

  final String? manufacturer;
  final String? model;
  final String? serialNumber;
  final String? barrelLength;
  final String? twistRate;
  final DateTime? purchaseDate;
  final String? purchasePrice;
  final String? purchaseLocation;

  Rifle({
    required this.id,
    this.name,
    required this.caliber,
    this.notes = '',
    this.dope = '',
    this.dopeEntries = const [],
    this.preferredUnit = ElevationUnit.mil,
    this.scopeUnit = ScopeUnit.mil,
    this.manualRoundCount = 0,
    this.services = const [],
    this.scopeMake,
    this.scopeModel,
    this.scopeSerial,
    this.scopeMount,
    this.scopeNotes,
    this.manufacturer,
    this.model,
    this.serialNumber,
    this.barrelLength,
    this.twistRate,
    this.purchaseDate,
    this.purchasePrice,
    this.purchaseLocation,
  });

  Rifle copyWith({
    String? id,
    String? name,
    String? caliber,
    String? notes,
    String? dope,
    List<RifleDopeEntry>? dopeEntries,
    ElevationUnit? preferredUnit,
    ScopeUnit? scopeUnit,
    int? manualRoundCount,
    List<RifleServiceEntry>? services,
    String? scopeMake,
    String? scopeModel,
    String? scopeSerial,
    String? scopeMount,
    String? scopeNotes,
    String? manufacturer,
    String? model,
    String? serialNumber,
    String? barrelLength,
    String? twistRate,
    DateTime? purchaseDate,
    String? purchasePrice,
    String? purchaseLocation,
  }) {
    return Rifle(
      id: id ?? this.id,
      name: name ?? this.name,
      caliber: caliber ?? this.caliber,
      notes: notes ?? this.notes,
      dope: dope ?? this.dope,
      dopeEntries: dopeEntries ?? this.dopeEntries,
      preferredUnit: preferredUnit ?? this.preferredUnit,
      scopeUnit: scopeUnit ?? this.scopeUnit,
      manualRoundCount: manualRoundCount ?? this.manualRoundCount,
      services: services ?? this.services,
      scopeMake: scopeMake ?? this.scopeMake,
      scopeModel: scopeModel ?? this.scopeModel,
      scopeSerial: scopeSerial ?? this.scopeSerial,
      scopeMount: scopeMount ?? this.scopeMount,
      scopeNotes: scopeNotes ?? this.scopeNotes,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      serialNumber: serialNumber ?? this.serialNumber,
      barrelLength: barrelLength ?? this.barrelLength,
      twistRate: twistRate ?? this.twistRate,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      purchaseLocation: purchaseLocation ?? this.purchaseLocation,
    );
  }
}

class AmmoLot {
  final String id;
  final String? name;
  final String caliber;
  final int grain;
  final String bullet;
  final String notes;

  // Optional details
  final String? manufacturer;
  final String? lotNumber;
  final DateTime? purchaseDate;
  final String? purchasePrice;

  // Optional ballistics
  final double? ballisticCoefficient;

  AmmoLot({
    required this.id,
    this.name,
    required this.caliber,
required this.grain,
    required this.bullet,
    required this.notes,
    this.manufacturer,
    this.lotNumber,
    this.purchaseDate,
    this.purchasePrice,
    this.ballisticCoefficient,
  });
}



class SessionStringMeta {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? rifleId;
  final String? ammoLotId;

  const SessionStringMeta({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.rifleId,
    this.ammoLotId,
  });

  SessionStringMeta copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    String? rifleId,
    String? ammoLotId,
  }) {
    return SessionStringMeta(
      id: id,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      rifleId: rifleId ?? this.rifleId,
      ammoLotId: ammoLotId ?? this.ammoLotId,
    );
  }
}


class TrainingSession {
  final String id;
  final String userId;
  final List<String> memberUserIds;
  final DateTime dateTime;
  final String locationName;
  final String notes;

  // Optional GPS (saved only if user taps Use GPS)
  final double? latitude;
  final double? longitude;

  // Optional Weather (stored on the session)
  final double? temperatureF;
  final double? windSpeedMph;
  final int? windDirectionDeg;

  final String? rifleId;
  final String? ammoLotId;

  final List<SessionStringMeta> strings;
  final String activeStringId;

  // Phase 2: per-string storage (keeps session-level lists for backward compatibility)
  final Map<String, List<DopeEntry>> trainingDopeByString;
  final Map<String, List<ShotEntry>> shotsByString;

  final List<ShotEntry> shots;
  final List<PhotoNote> photos;
  final List<SessionPhoto> sessionPhotos;
  final List<DopeEntry> trainingDope;

  TrainingSession({
    required this.id,
    required this.userId,
    required this.memberUserIds,
    required this.dateTime,
    required this.locationName,
    required this.notes,
    this.latitude,
    this.longitude,
    this.temperatureF,
    this.windSpeedMph,
    this.windDirectionDeg,
    required this.rifleId,
    required this.ammoLotId,
    required this.shots,
    required this.photos,
    required this.sessionPhotos,
    required this.trainingDope,
    required this.trainingDopeByString,
    required this.shotsByString,
    required this.strings,
    required this.activeStringId,
  });


  TrainingSession copyWith({
    List<String>? memberUserIds,
    DateTime? dateTime,
    String? locationName,
    String? notes,
    double? latitude,
    double? longitude,
    double? temperatureF,
    double? windSpeedMph,
    int? windDirectionDeg,
    String? rifleId,
    String? ammoLotId,
    List<ShotEntry>? shots,
    List<PhotoNote>? photos,
    List<SessionPhoto>? sessionPhotos,
    List<DopeEntry>? trainingDope,
    Map<String, List<DopeEntry>>? trainingDopeByString,
    Map<String, List<ShotEntry>>? shotsByString,
    List<SessionStringMeta>? strings,
    String? activeStringId,
  }) {
    return TrainingSession(
      id: id,
      userId: userId,
      memberUserIds: memberUserIds ?? this.memberUserIds,
      dateTime: dateTime ?? this.dateTime,
      locationName: locationName ?? this.locationName,
      notes: notes ?? this.notes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      temperatureF: temperatureF ?? this.temperatureF,
      windSpeedMph: windSpeedMph ?? this.windSpeedMph,
      windDirectionDeg: windDirectionDeg ?? this.windDirectionDeg,
      rifleId: rifleId ?? this.rifleId,
      ammoLotId: ammoLotId ?? this.ammoLotId,
      shots: shots ?? this.shots,
      photos: photos ?? this.photos,
      sessionPhotos: sessionPhotos ?? this.sessionPhotos,
      trainingDope: trainingDope ?? this.trainingDope,
      trainingDopeByString: trainingDopeByString ?? this.trainingDopeByString,
      shotsByString: shotsByString ?? this.shotsByString,
      strings: strings ?? this.strings,
      activeStringId: activeStringId ?? this.activeStringId,
    );
  }


}

class ShotEntry {
  final String id;
  final DateTime time;
  final bool isColdBore;

  /// When true, this cold bore entry is the baseline "first shot" to compare against.
  /// (We enforce a single baseline per active user, for now.)
  final bool isBaseline;

  final String distance;
  final String result;
  final String notes;

  /// Cold-bore-only photos (stored in-memory as bytes for MVP).
  final List<ColdBorePhoto> photos;

  ShotEntry({
    required this.id,
    required this.time,
    required this.isColdBore,
    required this.isBaseline,
    required this.distance,
    required this.result,
    required this.notes,
    required this.photos,
  });

  ShotEntry copyWith({
    DateTime? time,
    bool? isColdBore,
    bool? isBaseline,
    String? distance,
    String? result,
    String? notes,
    List<ColdBorePhoto>? photos,
  }) {
    return ShotEntry(
      id: id,
      time: time ?? this.time,
      isColdBore: isColdBore ?? this.isColdBore,
      isBaseline: isBaseline ?? this.isBaseline,
      distance: distance ?? this.distance,
      result: result ?? this.result,
      notes: notes ?? this.notes,
      photos: photos ?? this.photos,
    );
  }
}

class ColdBorePhoto {
  final String id;
  final DateTime time;
  final Uint8List bytes;
  final String caption;

  ColdBorePhoto({
    required this.id,
    required this.time,
    required this.bytes,
    required this.caption,
  });
}

/// Session-level photo captured from the Session screen.
class SessionPhoto {
  final String id;
  final DateTime time;
  final Uint8List bytes;
  final String caption;

  SessionPhoto({
    required this.id,
    required this.time,
    required this.bytes,
    required this.caption,
  });
}

/// Text-only session note (kept for quick caption-only notes).
class PhotoNote {
  final String id;
  final DateTime time;
  final String caption;

  PhotoNote({
    required this.id,
    required this.time,
    required this.caption,
  });
}

class _ColdBoreRow {
  final TrainingSession session;
  final ShotEntry shot;
  final Rifle? rifle;
  final AmmoLot? ammo;
  _ColdBoreRow({
    required this.session,
    required this.shot,
    required this.rifle,
    required this.ammo,
  });
}

///
/// Screens
///



class HomeShell extends StatefulWidget {
  final AppState state;
  const HomeShell({super.key, required this.state});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      SessionsScreen(state: widget.state),
      ColdBoreScreen(state: widget.state),
      EquipmentScreen(state: widget.state),
      DataScreen(state: widget.state),
      ExportPlaceholderScreen(state: widget.state),
    ];

    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final user = widget.state.activeUser;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Cold Bore'),
            actions: [
              if (user != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text(
                      user.identifier,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Users',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UsersScreen(state: widget.state),
                    ),
                  );
                  setState(() {});
                },
                icon: const Icon(Icons.person_outline),
              ),
            ],
          ),
          body: pages[_tab],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.event_note_outlined), label: 'Sessions'),
              NavigationDestination(icon: Icon(Icons.ac_unit_outlined), label: 'Cold Bore'),
              NavigationDestination(icon: Icon(Icons.build_outlined), label: 'Equipment'),
              NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: 'Data'),
              NavigationDestination(icon: Icon(Icons.ios_share_outlined), label: 'Export'),
            ],
          ),
        );
      },
    );
  }
}

class DataScreen extends StatefulWidget {
  final AppState state;
  const DataScreen({super.key, required this.state});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool _rifleOnly = false;
  bool _allDistances = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final rifles = widget.state.rifles;
        final withDope = rifles.where((r) => r.dope.trim().isNotEmpty).toList();
        final wmap = _rifleOnly ? widget.state.workingDopeRifleOnly : widget.state.workingDopeRifleAmmo;

        final workingSections = <Widget>[];
        if (wmap.isNotEmpty) {
          final sortedKeys = wmap.keys.toList()..sort();
          for (final key in sortedKeys) {
            final inner = wmap[key]!;
            var dks = inner.keys.toList();
            dks.sort((a, b) => a.value.compareTo(b.value));
            if (!_allDistances) {
              dks = dks.where((dk) => (dk.value.round() % 25 == 0)).toList();
            }

            String title;
            if (_rifleOnly) {
              final rifle = widget.state.rifleById(key);
              title = rifle?.name ?? 'Unknown Rifle';
            } else {
              final parts = key.split('_');
              final rifle = widget.state.rifleById(parts[0]);
              final ammo = widget.state.ammoById(parts[1]);
              title = '${rifle?.name ?? 'Unknown'} / ${ammo?.name ?? 'Unknown'}';
            }

            workingSections.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Distance')),
                          DataColumn(label: Text('Elevation')),
                          DataColumn(label: Text('Wind')),
                          DataColumn(label: Text('Windage Left')),
                          DataColumn(label: Text('Windage Right')),
                        ],
                        rows: dks.map((dk) {
                          final e = inner[dk]!;
                          return DataRow(cells: [
                            DataCell(Text('${dk.value} ${dk.unit.name[0]}')),
                            DataCell(Text(_cleanText('${e.elevation} ${e.elevationUnit.name}${e.elevationNotes.isNotEmpty ? " • ${e.elevationNotes}" : ""}'))),
                            DataCell(Text(_cleanText('${e.windType.name}: ${e.windValue}${e.windNotes.isNotEmpty ? " • ${e.windNotes}" : ""}'))),
                            DataCell(Text(e.windageLeft.toStringAsFixed(2))),
                            DataCell(Text(e.windageRight.toStringAsFixed(2))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        } else {
          workingSections.add(
            Text(
              'No working DOPE yet. Promote from a session.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              Text(
                'Data & Quick Reference',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.my_location_outlined),
                          const SizedBox(width: 8),
                          Text('DOPE (Quick Reference)', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (withDope.isEmpty)
                        Text(
                          'No DOPE saved yet. Add it under Equipment -> Rifles.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                        )
                      else
                        ...withDope.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r.name ?? 'Rifle'} • ${r.caliber}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(r.dope),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.table_chart_outlined),
                          const SizedBox(width: 8),
                          Text('Working DOPE Chart', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          const Text('Rifle only'),
                          Switch(
                            value: _rifleOnly,
                            onChanged: (v) => setState(() => _rifleOnly = v),
                          ),
                          const Text('All distances'),
                          Switch(
                            value: _allDistances,
                            onChanged: (v) => setState(() => _allDistances = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...workingSections,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_none),
                          const SizedBox(width: 8),
                          Text('Maintenance reminders', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Coming next: round-count reminders, cleaning schedule, and per-rifle checklists.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class UsersScreen extends StatefulWidget {
  final AppState state;
  const UsersScreen({super.key, required this.state});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  Future<void> _addUser() async {
    final res = await showDialog<_NewUserResult>(
      context: context,
      builder: (_) => const _NewUserDialog(),
    );
    if (res == null) return;
    widget.state.addUser(name: (res.name ?? res.identifier), identifier: res.identifier);
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.state.users;
    final active = widget.state.activeUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addUser,
        icon: const Icon(Icons.add),
        label: const Text('Add user'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('Maintenance'),
                subtitle: const Text('View round counts and service history'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MaintenanceHubScreen(state: widget.state),
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final u = users[index];
                final isActive = active?.id == u.id;
                return ListTile(
                  title: Text(u.name ?? ''),
                  subtitle: Text(u.identifier),
                  trailing: isActive ? const Icon(Icons.check_circle_outline) : null,
                  onTap: () {
                    widget.state.switchUser(u);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SessionsScreen extends StatelessWidget {
  final AppState state;
  const SessionsScreen({super.key, required this.state});

  Future<void> _newSession(BuildContext context) async {
    final res = await showDialog<_NewSessionResult>(
      context: context,
      builder: (_) => const _NewSessionDialog(),
    );
    if (res == null) return;
    final created = state.addSession(
      locationName: res.locationName,
      dateTime: res.dateTime,
      notes: res.notes ?? '',
    );

    if (created == null) return;
    // Automatically open the newly created session.
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionDetailScreen(state: state, sessionId: created.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final user = state.activeUser;
        final sessions = [...state.sessions]..sort((a, b) => b.dateTime.compareTo(a.dateTime));

        if (user == null) {
          return const _EmptyState(
            icon: Icons.person_outline,
            title: 'No active user',
            message: 'Create or select a user to start logging sessions.',
          );
        }

        if (sessions.isEmpty) {
          return _EmptyState(
            icon: Icons.event_note_outlined,
            title: 'No sessions yet',
            message: 'Tap "New Session" to add your first training day.',
            actionLabel: 'New Session',
            onAction: () => _newSession(context),
          );
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _newSession(context),
            icon: const Icon(Icons.add),
            label: const Text('New Session'),
          ),
          body: ListView.separated(
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final rifle = state.rifleById(s.rifleId);
        final ammo = state.ammoById(s.ammoLotId);

        String _joinNonEmpty(List<String?> parts) {
          final out = <String>[];
          for (final p in parts) {
            final v = (p ?? '').trim();
            if (v.isNotEmpty) out.add(v);
          }
          return out.join(' • ');
        }

        final rifleDesc = (rifle == null)
            ? (s.rifleId == null ? '-' : 'Deleted (${s.rifleId})')
            : _joinNonEmpty([
                rifle.caliber,
                rifle.manufacturer,
                rifle.model,
                (rifle.name ?? '').trim().isEmpty ? null : rifle.name,
              ]);

        final ammoDesc = (ammo == null)
            ? (s.ammoLotId == null ? '-' : 'Deleted (${s.ammoLotId})')
            : _joinNonEmpty([
                ammo.caliber,
                ammo.manufacturer,
                (ammo.bullet.isNotEmpty ? ammo.bullet : (ammo.name ?? 'Ammo')),
                ammo.grain > 0 ? '${ammo.grain}gr' : null,
              ]);
        final subtitleBits = <String>[
                _fmtDateTime(s.dateTime),
                if (rifle != null) rifle.name ?? '',
                if (ammo != null) ammo.name ?? '',
              ];

              return ListTile(
                title: Text(s.locationName),
                subtitle: Text(_cleanText(subtitleBits.join(' • '))),
                trailing: s.shots.any((x) => x.isColdBore)
                    ? const Icon(Icons.ac_unit_outlined)
                    : null,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SessionDetailScreen(state: state, sessionId: s.id),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _DopeResult {
  final DopeEntry entry;
  final bool promote;
  final bool rifleOnly;

  _DopeResult(this.entry, this.promote, this.rifleOnly);
}

class _DopeEntryDialog extends StatefulWidget {
  const _DopeEntryDialog({
    super.key,
    this.defaultTime,
    required this.rifleId,
    required this.ammoOptions,
    required this.defaultAmmoId,
    required this.lockedUnit,
  });

  final DateTime? defaultTime;
  final String rifleId;
  final List<AmmoLot> ammoOptions;
  final String? defaultAmmoId;
  final ElevationUnit lockedUnit;

  @override
  State<_DopeEntryDialog> createState() => _DopeEntryDialogState();
}

class _DopeEntryDialogState extends State<_DopeEntryDialog> {
  final _distanceCtrl = TextEditingController();
  DistanceUnit _distanceUnit = DistanceUnit.yards;
  double _elevation = 0.0;
  late ElevationUnit _elevationUnit;
  String? _ammoLotId;
  final _elevationNotesCtrl = TextEditingController();
  WindType _windType = WindType.fullValue;

  @override
  void initState() {
    super.initState();
    _elevationUnit = widget.lockedUnit;
    _ammoLotId = widget.defaultAmmoId ?? (widget.ammoOptions.isNotEmpty ? widget.ammoOptions.first.id : null);
  }

  final _windValueCtrl = TextEditingController();
  final _windNotesCtrl = TextEditingController();
  double _windageLeft = 0.0;
  double _windageRight = 0.0;
  bool _promote = true;
  bool _rifleOnly = false;


  @override
  void dispose() {
    _distanceCtrl.dispose();
    _elevationNotesCtrl.dispose();
    _windValueCtrl.dispose();
    _windNotesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ammoById = <String, AmmoLot>{ for (final a in widget.ammoOptions) a.id: a };
    final uniqueAmmoOptions = ammoById.values.toList();
    final safeAmmoLotId = ammoById.containsKey(_ammoLotId)
        ? _ammoLotId
        : (uniqueAmmoOptions.isNotEmpty ? uniqueAmmoOptions.first.id : null);

    return AlertDialog(
      title: const Text('Add Training DOPE'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              value: safeAmmoLotId,
              decoration: const InputDecoration(labelText: 'Ammo (for this entry)'),
              items: uniqueAmmoOptions
                  .map((a) => DropdownMenuItem<String?>(value: a.id, child: Text('${a.name ?? 'Ammo'} (${a.caliber})')))
                  .toList(),
              onChanged: (v) => setState(() => _ammoLotId = v),
            ),

const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _distanceCtrl,
                    decoration: const InputDecoration(labelText: 'Distance'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<DistanceUnit>(
                  value: _distanceUnit,
                  items: DistanceUnit.values
                      .map((u) => DropdownMenuItem(value: u, child: Text(u.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _distanceUnit = v!),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Elevation (${_elevationUnit.name.toUpperCase()})'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Down',
                      onPressed: () {
                        final step = _elevationUnit == ElevationUnit.mil
                            ? 0.1
                            : (_elevationUnit == ElevationUnit.moa ? 0.25 : 0.5);
                        setState(() => _elevation = (_elevation - step).clamp(0.0, 999.0));
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(_elevation.toStringAsFixed(2), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    IconButton(
                      tooltip: 'Up',
                      onPressed: () {
                        final step = _elevationUnit == ElevationUnit.mil
                            ? 0.1
                            : (_elevationUnit == ElevationUnit.moa ? 0.25 : 0.5);
                        setState(() => _elevation = (_elevation + step).clamp(0.0, 999.0));
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<ElevationUnit>(
                      value: _elevationUnit,
                      items: ElevationUnit.values.map((u) => DropdownMenuItem(value: u, child: Text(u.name.toUpperCase()))).toList(),
                      onChanged: (v) => setState(() => _elevationUnit = v!),
                    ),
                  ],
                ),
                TextField(
                  controller: _elevationNotesCtrl,
                  decoration: const InputDecoration(labelText: 'Elevation notes (optional)'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final isLeft = _windageLeft > 0 || (_windageRight == 0);
                final val = isLeft ? _windageLeft : _windageRight;
                final step = _elevationUnit == ElevationUnit.mil
                    ? 0.1
                    : (_elevationUnit == ElevationUnit.moa ? 0.25 : 0.5);

                void setWind(bool left, double v) {
                  final nv = v.clamp(0.0, 999.0);
                  setState(() {
                    if (left) {
                      _windageLeft = nv;
                      _windageRight = 0.0;
                    } else {
                      _windageRight = nv;
                      _windageLeft = 0.0;
                    }
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Windage'),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ToggleButtons(
                          isSelected: [isLeft, !isLeft],
                          onPressed: (i) => setWind(i == 0, val),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('L')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('R')),
                          ],
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Down',
                          onPressed: () => setWind(isLeft, val - step),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(val.toStringAsFixed(2), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        IconButton(
                          tooltip: 'Up',
                          onPressed: () => setWind(isLeft, val + step),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            CheckboxListTile(
              title: const Text('Promote to Working DOPE'),
              value: _promote,
              onChanged: (v) => setState(() => _promote = v!),
            ),
            if (_promote)
              CheckboxListTile(
                title: const Text('Rifle only (uncheck for Rifle + Ammo)'),
                value: _rifleOnly,
                onChanged: (v) => setState(() => _rifleOnly = v!),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final dist = double.tryParse(_distanceCtrl.text.trim());
            if (dist == null) return;
            if (_ammoLotId == null) return;

            final entry = DopeEntry(
              id: '', // will be set in state
              time: widget.defaultTime ?? DateTime.now(),
              rifleId: widget.rifleId,
              ammoLotId: _ammoLotId,
              distance: dist,
              distanceUnit: _distanceUnit,
              elevation: _elevation,
              elevationUnit: _elevationUnit,
              elevationNotes: _elevationNotesCtrl.text.trim(),
              windType: _windType,
              windValue: _windValueCtrl.text.trim(),
              windNotes: _windNotesCtrl.text.trim(),
              windageLeft: _windageLeft,
              windageRight: _windageRight,
            );

            Navigator.pop(context, _DopeResult(entry, _promote, _rifleOnly));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class SessionDetailScreen extends StatelessWidget {
  final AppState state;
  final String sessionId;
  const SessionDetailScreen({super.key, required this.state, required this.sessionId});


  Future<bool> _promptStartNewStringDialog(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new string?'),
        content: const Text(
          'Changing the rifle or ammo can start a new string so data stays separated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Edit current'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start new'),
          ),
        ],
      ),
    );
    // Default to starting a new string (Option A).
    return res ?? true;
  }



  Future<void> _shareSession(BuildContext context, TrainingSession s) async {
    final me = state.activeUser;
    if (me == null) return;

    final others = state.users.where((u) => u.id != me.id).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other users found. Create another user first.')),
      );
      return;
    }

    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _ShareSessionDialog(
        sessionTitle: s.locationName.isEmpty ? 'Session' : s.locationName,
        users: others,
        initiallySelected: s.memberUserIds.where((id) => id != me.id).toSet(),
      ),
    );

    if (selected == null) return;
    state.shareSessionWithUsers(sessionId: s.id, userIds: selected.toList());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Session shared with ${selected.length} user(s).')),
    );
  }

  Future<void> _addColdBore(BuildContext context, TrainingSession s) async {
    final res = await showDialog<_ColdBoreResult>(
      context: context,
      builder: (_) => _ColdBoreDialog(defaultTime: s.dateTime),
    );
    if (res == null) return;

    state.addColdBoreEntry(
      sessionId: s.id,
      time: res.time,
      distance: res.distance,
      result: res.result,
      notes: res.notes ?? '',
    );
  }

  Future<void> _addPhotoNote(BuildContext context, TrainingSession s) async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _PhotoNoteDialog(),
    );
    if (res == null || res.trim().isEmpty) return;

    state.addPhotoNote(sessionId: s.id, time: DateTime.now(), caption: res);
  }

  Future<void> _editTrainingNotes(BuildContext context, TrainingSession s) async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _EditNotesDialog(initialNotes: s.notes),
    );
    if (res == null) return;
    state.updateSessionNotes(sessionId: s.id, notes: res);
  }

  
  Future<void> _exportCasePacket(BuildContext context, TrainingSession s) async {
    bool redact = true;
    bool includeB64 = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final packet = _buildCasePacket(
              state,
              s: s,
              redactLocation: redact,
              includePhotoBase64: includeB64,
            );

            return AlertDialog(
              title: const Text('Case packet'),
              content: SizedBox(
                width: 720,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Redact location & GPS'),
                      value: redact,
                      onChanged: (v) => setState(() => redact = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Include photo base64 (large)'),
                      value: includeB64,
                      onChanged: (v) => setState(() => includeB64 = v),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 420,
                      child: SingleChildScrollView(child: SelectableText(packet)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: packet));
                    if (Navigator.of(dialogCtx).canPop()) {
                      Navigator.of(dialogCtx).pop();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Case packet copied to clipboard.')),
                    );
                  },
                  child: const Text('Copy'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

Future<void> _addDope(BuildContext context, TrainingSession s) async {
    if (s.rifleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a rifle first.')),
      );
      return;
    }
    if (s.ammoLotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select ammo first.')),
      );
      return;
    }

    final rifle = state.rifleById(s.rifleId);
    final ammoOptions = (rifle == null)
        ? <AmmoLot>[]
        : state.ammoLots.where((a) => a.caliber == rifle.caliber).toList();
    if (ammoOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No compatible ammo lots found for this rifle.')),
      );
      return;
    }

    final res = await showDialog<_DopeResult>(
      context: context,
      builder: (_) {
        final rifle = state.rifleById(s.rifleId);
        return _DopeEntryDialog(
          defaultTime: DateTime.now(),
          rifleId: s.rifleId!,
          ammoOptions: ammoOptions,
          defaultAmmoId: s.ammoLotId,
          lockedUnit: (rifle?.scopeUnit == ScopeUnit.moa ? ElevationUnit.moa : ElevationUnit.mil),
        );
      },
    );
    if (res == null) return;

    if (res.promote) {
      if (s.rifleId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a rifle in Loadout to promote DOPE.')),
        );
        return;
      }
      if (!res.rifleOnly && res.entry.ammoLotId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select ammo to promote to Rifle + Ammo scope.')),
        );
        return;
      }

      final key = res.rifleOnly ? s.rifleId! : '${s.rifleId}_${res.entry.ammoLotId}';
      final wmap = res.rifleOnly ? state.workingDopeRifleOnly[key] ?? {} : state.workingDopeRifleAmmo[key] ?? {};
      final dk = DistanceKey(res.entry.distance, res.entry.distanceUnit);

      if (wmap.containsKey(dk)) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Replace existing?'),
            content: Text('Replace existing DOPE at ${dk.value} ${dk.unit.name}?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
            ],
          ),
        );
        if (confirm != true) return;
      }

      state.addTrainingDope(
        sessionId: s.id,
        entry: res.entry,
        promote: res.promote,
        rifleOnly: res.rifleOnly,
      );
    } else {
      state.addTrainingDope(sessionId: s.id, entry: res.entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final s = state.getSessionById(sessionId);
        if (s == null) {
          return const Scaffold(body: Center(child: Text('Session not found')));
        }

        final rifle = state.rifleById(s.rifleId);
        final ammo = state.ammoById(s.ammoLotId);

        String _joinNonEmptyParts(List<String?> parts) {
          final out = <String>[];
          for (final p in parts) {
            final v = (p ?? '').trim();
            if (v.isNotEmpty) out.add(v);
          }
          return out.join(' • ');
        }

        final rifleDesc = (rifle == null)
            ? (s.rifleId == null ? '-' : 'Deleted (${s.rifleId})')
            : _joinNonEmptyParts([
                rifle.caliber,
                rifle.manufacturer,
                rifle.model,
                (rifle.name ?? '').trim().isEmpty ? null : rifle.name,
              ]);

        final ammoDesc = (ammo == null)
            ? (s.ammoLotId == null ? '-' : 'Deleted (${s.ammoLotId})')
            : _joinNonEmptyParts([
                ammo.caliber,
                ammo.manufacturer,
                (ammo.bullet.isNotEmpty ? ammo.bullet : (ammo.name ?? 'Ammo')),
                ammo.grain > 0 ? '${ammo.grain}gr' : null,
              ]);
        final compatibleAmmo = (rifle == null)
            ? <AmmoLot>[]
            : state.ammoLots.where((a) => a.caliber == rifle.caliber).toList();

        // Defensive: avoid DropdownButton value mismatch and duplicate IDs.
        final rifleById = <String, Rifle>{ for (final r in state.rifles) r.id: r };
        final uniqueRifles = rifleById.values.toList();

        final compatibleAmmoById = <String, AmmoLot>{ for (final a in compatibleAmmo) a.id: a };
        final uniqueCompatibleAmmo = compatibleAmmoById.values.toList();

        final ammoIsCompatible = s.ammoLotId == null || compatibleAmmoById.containsKey(s.ammoLotId);
        final safeAmmoLotId = ammoIsCompatible ? s.ammoLotId : null;

        final currentTrainingDope = s.trainingDopeByString[s.activeStringId] ?? const <DopeEntry>[];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Session'),
            actions: [
              IconButton(
                tooltip: 'Share session',
                onPressed: () => _shareSession(context, s),
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: 'Edit training notes',
                onPressed: () => _editTrainingNotes(context, s),
                icon: const Icon(Icons.edit_note_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'case_packet', child: Text('Export case packet')),
                ],
                onSelected: (v) async {
                  if (v == 'case_packet') {
                    await _exportCasePacket(context, s);
                  }
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addColdBore(context, s),
            icon: const Icon(Icons.ac_unit_outlined),
            label: const Text('Add Cold Bore'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(s.locationName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_fmtDateTime(s.dateTime)),

const SizedBox(height: 8),
Card(
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Session information', style: TextStyle(fontWeight: FontWeight.w700)),
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
      children: [
        Align(alignment: Alignment.centerLeft, child: SelectableText('Session ID: ${s.id}')),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerLeft, child: SelectableText('Date/Time: ${_fmtDateTime(s.dateTime)}')),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerLeft, child: SelectableText('Location: ${s.locationName.isEmpty ? '-' : s.locationName}')),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Rifle: $rifleDesc'
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Ammo: $ammoDesc'
          ),
        ),
      ],
    ),
  ),
),

              const SizedBox(height: 16),
              _SectionTitle('Notes'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.notes.isEmpty ? 'No notes yet. Tap Edit to add training notes.' : s.notes,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _editTrainingNotes(context, s),
                          icon: const Icon(Icons.edit_note_outlined),
                          label: const Text('Edit'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
                            _SectionTitle('String'),
              const SizedBox(height: 8),
              _StringSummaryCard(state: state, session: s),
              const SizedBox(height: 16),
_SectionTitle('Loadout'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: s.rifleId,
                      decoration: const InputDecoration(labelText: 'Rifle'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('- None -')),
                        if (s.rifleId != null && rifle == null)
                          DropdownMenuItem<String?>(
                            value: s.rifleId,
                            child: Text('Deleted rifle (${s.rifleId})'),
                          ),
                        ...state.rifles.map(
                          (r) => DropdownMenuItem<String?>(
                            value: r.id,
                            child: Text('${r.caliber} • ${r.manufacturer ?? ''}${(r.manufacturer ?? '').trim().isEmpty ? '' : ''} • ${r.model ?? ''}${(r.name ?? '').trim().isEmpty ? '' : ' • ${r.name}'}'),
                          ),
                        ),
                      ],
                      onChanged: (v) async {
                        if (v == s.rifleId) return;

                        final current = s.strings.firstWhere(
                          (x) => x.id == s.activeStringId,
                          orElse: () => s.strings.isNotEmpty ? s.strings.last : SessionStringMeta(id: s.activeStringId, startedAt: DateTime.now(), endedAt: null),
                        );

                        // If we haven't completed a loadout yet, just set it (no prompt).
                        if (current.rifleId == null || current.ammoLotId == null) {
                          state.updateSessionLoadout(
                            sessionId: s.id,
                            rifleId: v,
                            ammoLotId: s.ammoLotId,
                            startNewString: false,
                          );
                          return;
                        }

                        // User is changing rifle; clear ammo for now (force re-select). No prompt until BOTH are selected.
                        state.updateSessionLoadout(
                          sessionId: s.id,
                          rifleId: v,
                          ammoLotId: null,
                          startNewString: false,
                        );
                      },
                  ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: safeAmmoLotId,
                      decoration: const InputDecoration(labelText: 'Ammo'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('- None -')),
                        if (s.ammoLotId != null && ammo == null)
                          DropdownMenuItem<String?>(
                            value: s.ammoLotId,
                            child: Text('Deleted ammo (${s.ammoLotId})'),
                          ),
                        ...compatibleAmmo.map(
                          (a) => DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text('${a.caliber} • ${a.manufacturer ?? ''} • ${a.bullet ?? (a.name ?? 'Ammo')} • ${a.grain}gr'),
                          ),
                        ),
                      ],
                      onChanged: (rifle == null)
                          ? null
                          : (v) async {
                              if (v == s.ammoLotId) return;

                              final current = s.strings.firstWhere(
                                (x) => x.id == s.activeStringId,
                                orElse: () => s.strings.isNotEmpty ? s.strings.last : SessionStringMeta(id: s.activeStringId, startedAt: DateTime.now(), endedAt: null),
                              );

                              // If we haven't completed a loadout yet, just set it (no prompt).
                              if (current.rifleId == null || current.ammoLotId == null) {
                                state.updateSessionLoadout(
                                  sessionId: s.id,
                                  rifleId: s.rifleId,
                                  ammoLotId: v,
                                  startNewString: false,
                                );
                                return;
                              }

                              // Only prompt when BOTH rifle + ammo are selected (i.e., loadout is complete).
                              if (s.rifleId != null && v != null) {
                                final nextRifle = s.rifleId;
                                final nextAmmo = v;

                                final changed = (nextRifle != current.rifleId) || (nextAmmo != current.ammoLotId);
                                if (!changed) return;

                                final startNew = await _promptStartNewStringDialog(context);
                                if (!startNew) {
                                  // Revert to current active string loadout.
                                  state.updateSessionLoadout(
                                    sessionId: s.id,
                                    rifleId: current.rifleId,
                                    ammoLotId: current.ammoLotId,
                                    startNewString: false,
                                  );
                                  return;
                                }

                                state.updateSessionLoadout(
                                  sessionId: s.id,
                                  rifleId: nextRifle,
                                  ammoLotId: nextAmmo,
                                  startNewString: true,
                                );
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _SectionTitle('Training DOPE')) ,
                  TextButton.icon(
                    onPressed: () => _addDope(context, s),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (s.trainingDope.isEmpty)
                _HintCard(
                  icon: Icons.my_location_outlined,
                  title: 'No training DOPE yet',
                  message: 'Add dialed elevation/wind for this session. It will stay saved on the session.',
                )
              else
                ...(() {
                  final list = [...currentTrainingDope];
                  list.sort((a, b) {
                    final cmp = a.distance.compareTo(b.distance);
                    if (cmp != 0) return cmp;
                    return a.time.compareTo(b.time);
                  });
                  return list.map((e) {
                    final wind = (e.windageLeft > 0)
                        ? 'L ${e.windageLeft.toStringAsFixed(2)}'
                        : (e.windageRight > 0 ? 'R ${e.windageRight.toStringAsFixed(2)}' : '-');
                    return Card(
                      child: ListTile(
                        title: Text('${e.distance} ${e.distanceUnit.name}  •  ${e.elevation.toStringAsFixed(2)} ${e.elevationUnit.name.toUpperCase()}'),
                        subtitle: Text('Wind: $wind${e.windNotes.trim().isEmpty ? '' : ' • ${e.windNotes.trim()}'}'),
                      ),
                    );
                  }).toList();
                })(),
              _SectionTitle('Cold Bore Entries'),
              const SizedBox(height: 8),
              if (s.shots.where((x) => x.isColdBore).isEmpty)
                _HintCard(
                  icon: Icons.ac_unit_outlined,
                  title: 'No cold bore entries yet',
                  message: 'Tap "Add Cold Bore" to log the first shot for this session.',
                )
              else
                ...s.shots.where((x) => x.isColdBore).map(
                      (shot) => Card(
                        child: ListTile(
                          leading: Icon(
                            shot.isBaseline ? Icons.star : Icons.ac_unit_outlined,
                          ),
                          title: Text('${shot.distance} • ${shot.result}'),
                          subtitle: Text(
                            '${_fmtDateTime(shot.time)}'
                            '${shot.photos.isEmpty ? '' : ' • ${shot.photos.length} photo(s)'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ColdBoreEntryScreen(
                                  state: state,
                                  sessionId: s.id,
                                  shotId: shot.id,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _SectionTitle('Working DOPE (quick reference)')),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => DataScreen(state: state)),
                      );
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open Data'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  if (s.rifleId == null) {
                    return _HintCard(
                      icon: Icons.info_outline,
                      title: 'Select a rifle',
                      message: 'Choose a rifle in Loadout to view working DOPE.',
                    );
                  }

                  final rifleKey = s.rifleId!;
                  final ammoKey = (s.ammoLotId == null) ? null : '${s.rifleId}_${s.ammoLotId}';
                  final rifleAmmoMap = (ammoKey == null) ? null : state.workingDopeRifleAmmo[ammoKey];
                  final rifleOnlyMap = state.workingDopeRifleOnly[rifleKey];

                  final useAmmoScoped = (rifleAmmoMap != null && rifleAmmoMap.isNotEmpty);
                  final useMap = useAmmoScoped
                      ? rifleAmmoMap!
                      : (rifleOnlyMap ?? <DistanceKey, DopeEntry>{});

                  final scopeLabel = useAmmoScoped ? 'Rifle + Ammo' : 'Rifle only';

                  if (useMap.isEmpty) {
                    return _HintCard(
                      icon: Icons.my_location_outlined,
                      title: 'No working DOPE yet',
                      message: 'Promote DOPE from Training DOPE (when adding an entry) or add it in Data.',
                    );
                  }

                  final dks = useMap.keys.toList()..sort((a, b) => a.value.compareTo(b.value));

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          scopeLabel,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                        ),
                      ),
                      ...dks.map((dk) {
                        final e = useMap[dk]!;
                        final wind = (e.windageLeft > 0)
                            ? 'L ${e.windageLeft.toStringAsFixed(2)}'
                            : (e.windageRight > 0 ? 'R ${e.windageRight.toStringAsFixed(2)}' : '-');
                        return Card(
                          child: ListTile(
                            title: Text(
                              '${dk.value.toStringAsFixed(0)} ${dk.unit == DistanceUnit.yards ? 'yd' : 'm'}'
                              '  •  ${e.elevation.toStringAsFixed(2)} ${e.elevationUnit == ElevationUnit.mil ? 'mil' : (e.elevationUnit == ElevationUnit.moa ? 'MOA' : 'in')}',
                            ),
                            subtitle: Text(
                              'Wind: $wind'
                              '${e.windNotes.trim().isEmpty ? '' : ' • ${e.windNotes.trim()}'}'
                              '${e.elevationNotes.trim().isEmpty ? '' : ' • Elev: ${e.elevationNotes.trim()}'}',
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _SectionTitle('Photos'),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      try {
                        final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                        if (x == null) return;
                        final bytes = await x.readAsBytes();

                        String caption = '';
                        final cap = await showDialog<String>(
                          context: context,
                          builder: (_) => _PhotoNoteDialog(),
                        );
                        if (cap != null) caption = cap;

                        state.addSessionPhoto(sessionId: s.id, bytes: bytes, caption: caption);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Camera error: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Capture'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _addPhotoNote(context, s),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Add note'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (s.sessionPhotos.isEmpty && s.photos.isEmpty)
                _HintCard(
                  icon: Icons.photo_outlined,
                  title: 'No photos yet',
                  message: 'Capture a photo for this session or add a note.',
                ),
              if (s.sessionPhotos.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...s.sessionPhotos.map(
                  (p) => Card(
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(p.bytes, width: 52, height: 52, fit: BoxFit.cover),
                      ),
                      title: Text(p.caption.trim().isEmpty ? 'Photo' : p.caption.trim()),
                      subtitle: Text('${_fmtDateTime(p.time)} • ${p.bytes.lengthInBytes} bytes'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(p.caption.trim().isEmpty ? 'Photo' : p.caption.trim()),
                                ),
                                InteractiveViewer(
                                  child: Image.memory(p.bytes),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (s.photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...s.photos.map(
                  (p) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.sticky_note_2_outlined),
                      title: Text(p.caption),
                      subtitle: Text(_fmtDateTime(p.time)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Loadout: ${rifle?.name ?? '-'} / ${ammo?.name ?? '-'}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ColdBoreScreen extends StatelessWidget {
  final AppState state;
  const ColdBoreScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final user = state.activeUser;
        if (user == null) {
          return const _EmptyState(
            icon: Icons.person_outline,
            title: 'No active user',
            message: 'Create or select a user to view cold bore history.',
          );
        }

        final rows = state.coldBoreRowsForActiveUser();
        if (rows.isEmpty) {
          return const _EmptyState(
            icon: Icons.ac_unit_outlined,
            title: 'No cold bore entries yet',
            message: 'Open a session and tap "Add Cold Bore".',
          );
        }

        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = rows[i];
            final rifle = r.rifle;
            final ammo = r.ammo;
            return ListTile(
              leading: Icon(r.shot.isBaseline ? Icons.star : Icons.ac_unit_outlined),
              title: Text('${r.shot.distance} • ${r.shot.result}' + (r.shot.photos.isEmpty ? '' : ' • ${r.shot.photos.length} photo(s)')),
              subtitle: Text(
                [
                  _fmtDateTime(r.shot.time),
                  r.session.locationName,
                  if (rifle != null) rifle.name ?? '',
                  if (ammo != null) ammo.name ?? '',
                ].join(' • '),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ColdBoreEntryScreen(
                      state: state,
                      sessionId: r.session.id,
                      shotId: r.shot.id,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class ColdBoreEntryScreen extends StatefulWidget {
  final AppState state;
  final String sessionId;
  final String shotId;
  const ColdBoreEntryScreen({
    super.key,
    required this.state,
    required this.sessionId,
    required this.shotId,
  });

  @override
  State<ColdBoreEntryScreen> createState() => _ColdBoreEntryScreenState();
}

class _ColdBoreEntryScreenState extends State<ColdBoreEntryScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pick({required ImageSource source}) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: 2200,
      );
      if (x == null) return;

      final bytes = await x.readAsBytes();
      widget.state.addColdBorePhoto(
        sessionId: widget.sessionId,
        shotId: widget.shotId,
        bytes: bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo failed: $e')),
      );
    }
  }

  void _setBaseline() {
    widget.state.setBaselineColdBore(sessionId: widget.sessionId, shotId: widget.shotId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked as baseline (first shot).')),
    );
  }

  void _compare() {
    final baseline = widget.state.baselineColdBoreShot();
    if (baseline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No baseline set yet. Tap "Mark as Baseline" first.')),
      );
      return;
    }
    final current = widget.state.shotById(sessionId: widget.sessionId, shotId: widget.shotId);
    if (current == null) return;

    if (baseline.id == current.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This entry is already the baseline.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (_) {
        final baseImg = baseline.photos.isNotEmpty ? baseline.photos.last.bytes : null;
        final curImg = current.photos.isNotEmpty ? current.photos.last.bytes : null;
        return AlertDialog(
          title: const Text('Compare to Baseline'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Baseline: ${baseline.distance} • ${baseline.result}'),
                  const SizedBox(height: 8),
                  if (baseImg != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(baseImg, fit: BoxFit.cover),
                    )
                  else
                    const Text('No baseline photo yet.'),
                  const SizedBox(height: 16),
                  Text('Selected: ${current.distance} • ${current.result}'),
                  const SizedBox(height: 8),
                  if (curImg != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(curImg, fit: BoxFit.cover),
                    )
                  else
                    const Text('No photo on this entry yet.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final s = widget.state.getSessionById(widget.sessionId);
        final shot = widget.state.shotById(sessionId: widget.sessionId, shotId: widget.shotId);
        if (s == null || shot == null) {
          return const Scaffold(body: Center(child: Text('Entry not found')));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(shot.isBaseline ? 'Cold Bore (Baseline)' : 'Cold Bore'),
            actions: [
              IconButton(
                tooltip: 'Compare to baseline',
                onPressed: _compare,
                icon: const Icon(Icons.compare_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: Text('${shot.distance} • ${shot.result}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  if (shot.isBaseline)
                    const Chip(label: Text('Baseline'), avatar: Icon(Icons.star, size: 18)),
                ],
              ),
              const SizedBox(height: 6),
              Text(_fmtDateTime(shot.time) + ' • ' + s.locationName),
              if (shot.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(shot.notes),
              ],
              const SizedBox(height: 16),
              _SectionTitle('Cold Bore Photos'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pick(source: ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take Photo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(source: ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Pick from Library'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _setBaseline,
                    icon: const Icon(Icons.star_border),
                    label: const Text('Mark as Baseline'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (shot.photos.isEmpty)
                _HintCard(
                  icon: Icons.photo_outlined,
                  title: 'No cold bore photos yet',
                  message: 'Add a photo here. These photos stay attached to this cold bore entry only.',
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: shot.photos
                      .map(
                        (p) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            p.bytes,
                            width: 140,
                            height: 140,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 16),
              Text(
                'Tip: Set a baseline once, then open another cold bore entry and tap Compare.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class EquipmentScreen extends StatefulWidget {
  final AppState state;
  const EquipmentScreen({super.key, required this.state});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  int _seg = 0;

  Future<void> _addRifle() async {
    final res = await showDialog<_NewRifleResult>(
      context: context,
      builder: (_) => _NewRifleDialog(),
    );
    if (res == null) return;
    widget.state.addRifle(
      name: (res.name ?? ''),
      caliber: res.caliber,
      notes: res.notes ?? '',
      dope: res.dope,
      manufacturer: res.manufacturer,
      model: res.model,
      serialNumber: res.serialNumber,
      barrelLength: res.barrelLength,
      twistRate: res.twistRate,
      purchaseDate: res.purchaseDate,
      purchasePrice: res.purchasePrice,
      scopeUnit: res.scopeUnit,
      manualRoundCount: res.manualRoundCount,
      scopeMake: res.scopeMake,
      scopeModel: res.scopeModel,
      scopeSerial: res.scopeSerial,
      scopeMount: res.scopeMount,
      scopeNotes: res.scopeNotes,
      purchaseLocation: res.purchaseLocation,
    );
  }

  Future<void> _addAmmo() async {
    final res = await showDialog<_NewAmmoResult>(
      context: context,
      builder: (_) => _NewAmmoDialog(),
    );
    if (res == null) return;
    widget.state.addAmmoLot(
      name: (res.name ?? ''),
      caliber: res.caliber,
      grain: res.grain,
      bullet: res.bullet,
      notes: res.notes ?? '',
      manufacturer: res.manufacturer,
      lotNumber: res.lotNumber,
      purchaseDate: res.purchaseDate,
      purchasePrice: res.purchasePrice,
      ballisticCoefficient: res.ballisticCoefficient,
    );
  }


  Future<void> _editRifle(Rifle r) async {
    final res = await showDialog<_NewRifleResult>(
      context: context,
      builder: (_) => _NewRifleDialog(existing: r),
    );
    if (res == null) return;
    widget.state.updateRifle(
      rifleId: r.id,
      name: res.name,
      caliber: res.caliber,
      notes: res.notes ?? '',
      dope: res.dope,
      manufacturer: res.manufacturer,
      model: res.model,
      serialNumber: res.serialNumber,
      barrelLength: res.barrelLength,
      twistRate: res.twistRate,
      purchaseDate: res.purchaseDate,
      purchasePrice: res.purchasePrice,
      purchaseLocation: res.purchaseLocation,
      scopeUnit: res.scopeUnit,
      scopeMake: res.scopeMake,
      scopeModel: res.scopeModel,
      scopeSerial: res.scopeSerial,
      scopeMount: res.scopeMount,
      scopeNotes: res.scopeNotes,
    );
  }

  Future<void> _editAmmo(AmmoLot a) async {
    final res = await showDialog<_NewAmmoResult>(
      context: context,
      builder: (_) => _NewAmmoDialog(existing: a),
    );
    if (res == null) return;
    widget.state.updateAmmoLot(
      ammoLotId: a.id,
      name: res.name,
      caliber: res.caliber,
      grain: res.grain,
      bullet: res.bullet,
      notes: res.notes ?? '',
      manufacturer: res.manufacturer,
      lotNumber: res.lotNumber,
      purchaseDate: res.purchaseDate,
      purchasePrice: res.purchasePrice,
      ballisticCoefficient: res.ballisticCoefficient,
    );
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
    String confirmText = 'Delete',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteRifle(Rifle r) async {
    final ok = await _confirmDelete(
      title: 'Delete rifle?',
      message:
          'This removes the rifle from your equipment list.\n\nHistorical sessions will keep their records and exports will show the rifle as Deleted.',
    );
    if (!ok) return;
    widget.state.deleteRifle(r.id);
  }

  Future<void> _deleteAmmo(AmmoLot a) async {
    final ok = await _confirmDelete(
      title: 'Delete ammo lot?',
      message:
          'This removes the ammo lot from your equipment list.\n\nHistorical sessions will keep their records and exports will show the ammo lot as Deleted.',
    );
    if (!ok) return;
    widget.state.deleteAmmoLot(a.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final rifles = widget.state.rifles;
        final ammo = widget.state.ammoLots;

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _seg == 0 ? _addRifle : _addAmmo,
            icon: const Icon(Icons.add),
            label: Text(_seg == 0 ? 'Add Rifle' : 'Add Ammo'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Rifles'), icon: Icon(Icons.sports_martial_arts_outlined)),
                    ButtonSegment(value: 1, label: Text('Ammo'), icon: Icon(Icons.inventory_2_outlined)),
                  ],
                  selected: {_seg},
                  onSelectionChanged: (s) => setState(() => _seg = s.first),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _seg == 0
                      ? _EquipmentList(
                          emptyTitle: 'No rifles yet',
                          emptyMessage: 'Tap "Add Rifle" to create your first rifle.',
                          items: rifles
                              .map(
                                (r) => ListTile(
                                  leading: const Icon(Icons.sports_martial_arts_outlined),
                                  title: Text((((r.manufacturer ?? '').trim() + ' ' + (r.model ?? '').trim()).trim().isNotEmpty) ? ((r.manufacturer ?? '').trim() + ' ' + (r.model ?? '').trim()).trim() : (((r.name ?? '').trim().isNotEmpty) ? (r.name ?? '').trim() : 'Rifle')),
                                  subtitle: Text(
                                    r.caliber + (((r.name ?? '').trim().isEmpty) ? '' : ' • Nickname: ${(r.name ?? '').trim()}') +
                                        (((r.manufacturer ?? '').trim().isEmpty) ? '' : ' • ${(r.manufacturer ?? '').trim()}') +
                                        (((r.model ?? '').trim().isEmpty) ? '' : ' • ${(r.model ?? '').trim()}') +
                                        ((r.serialNumber == null || r.serialNumber!.isEmpty) ? '' : ' • SN ${r.serialNumber!}') +
                                        (r.purchaseDate == null ? '' : ' • ${_fmtDate(r.purchaseDate!)}') +
                                        (r.notes.isEmpty ? '' : ' • ${r.notes}') +
                                        (r.dope.trim().isEmpty ? '' : ' • DOPE saved'),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'edit') {
                                        await _editRifle(r);
                                        return;
                                      }
                                      if (v == 'dope') {
                                        final updated = await showDialog<String>(
                                          context: context,
                                          builder: (_) => _EditDopeDialog(initialValue: r.dope),
                                        );
                                        if (updated == null) return;
                                        widget.state.updateRifleDope(rifleId: r.id, dope: updated);
                                        return;
                                      }
                                      if (v == 'service') {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => RifleServiceLogScreen(
                                              state: widget.state,
                                              rifleId: r.id,
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      if (v == 'delete') {
                                        await _deleteRifle(r);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit rifle')),
                                      PopupMenuItem(value: 'dope', child: Text('Edit DOPE')),
                                      PopupMenuItem(value: 'service', child: Text('Service log')),
                                      PopupMenuDivider(),
                                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      : _EquipmentList(
                          emptyTitle: 'No ammo lots yet',
                          emptyMessage: 'Tap "Add Ammo" to create your first ammo lot.',
                          items: ammo
                              .map(
                                (a) => ListTile(
                                  leading: const Icon(Icons.inventory_2_outlined),
                                  title: Text('${a.caliber} • ${a.grain}gr • ${a.bullet}${((a.name ?? '').trim().isEmpty) ? '' : ' (${(a.name ?? '').trim()})'}'.trim()),
                                  subtitle: Text(
                                    ((a.manufacturer == null || a.manufacturer!.isEmpty) ? '' : '${a.manufacturer!} • ') +
                                        ((a.lotNumber == null || a.lotNumber!.isEmpty) ? '' : 'Lot ${a.lotNumber!} • ') +
                                        (a.purchaseDate == null ? '' : '${_fmtDate(a.purchaseDate!)} • ') +
                                        (a.ballisticCoefficient == null ? '' : 'BC ${a.ballisticCoefficient} • ') +
                                        (a.notes.isEmpty ? '' : a.notes),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'edit') {
                                        await _editAmmo(a);
                                        return;
                                      }
                                      if (v == 'delete') {
                                        await _deleteAmmo(a);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit ammo')),
                                      PopupMenuDivider(),
                                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                  onTap: () => _editAmmo(a),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EquipmentList extends StatelessWidget {
  final String emptyTitle;
  final String emptyMessage;
  final List<Widget> items;

  const _EquipmentList({
    required this.emptyTitle,
    required this.emptyMessage,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _HintCard(
        icon: Icons.info_outline,
        title: emptyTitle,
        message: emptyMessage,
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => items[i],
    );
  }
}

class ExportPlaceholderScreen extends StatefulWidget {
  final AppState state;
  const ExportPlaceholderScreen({super.key, required this.state});

  @override
  State<ExportPlaceholderScreen> createState() => _ExportPlaceholderScreenState();
}

class _ExportPlaceholderScreenState extends State<ExportPlaceholderScreen> {
  bool _redactLocation = true;

  Future<void> _showExportText(String title, String text) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
            },
            child: const Text('Copy'),
          ),
          if (kIsWeb)
            TextButton(
              onPressed: () {
                final safe = title
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                    .replaceAll(RegExp(r'_+'), '_')
                    .replaceAll(RegExp(r'^_|_$'), '');
                final ext = title.toLowerCase().contains('csv') ? 'csv' : 'txt';
                _downloadTextFileWeb(
                  'cold_bore_${safe.isEmpty ? 'export' : safe}.$ext',
                  text,
                  mimeType: ext == 'csv' ? 'text/csv' : 'text/plain',
                );
              },
              child: const Text('Download'),
            ),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                const _SectionTitle('Export for review / court'),
                SwitchListTile(
                  value: _redactLocation,
                  title: const Text('Redact location & GPS'),
                  onChanged: (v) => setState(() => _redactLocation = v),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: const Text('Court-style report (text)'),
                    onTap: () => _showExportText(
                      'Court-style report',
                      _buildCourtReport(widget.state, redactLocation: _redactLocation),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.table_view_outlined),
                    title: const Text('CSV bundle'),
                    onTap: () => _showExportText(
                      'CSV bundle',
                      _buildCsvBundle(widget.state, redactLocation: _redactLocation),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.swap_vert),
                    title: const Text('Backup / restore (JSON)'),
                    subtitle: const Text('Download a backup file or import one (merge: scope/data only).'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _BackupScreen(state: widget.state),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


///
/// Widgets
///

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.onSurface.withOpacity(0.7)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}



class _StringSummaryCard extends StatelessWidget {
  final AppState state;
  final TrainingSession session;
  const _StringSummaryCard({required this.state, required this.session});

  String _rifleLabel(String? id) {
    if (id == null) return '—';
    final r = state.rifles.firstWhere((x) => x.id == id, orElse: () => Rifle(id: id, caliber: '', notes: '', dope: '', dopeEntries: const [], preferredUnit: ElevationUnit.mil));
    final parts = <String>[];
    if (r.manufacturer != null && r.manufacturer!.trim().isNotEmpty) parts.add(r.manufacturer!.trim());
    if (r.model != null && r.model!.trim().isNotEmpty) parts.add(r.model!.trim());
    if (r.caliber.trim().isNotEmpty) parts.add(r.caliber.trim());
    if (r.name != null && r.name!.trim().isNotEmpty) parts.add('"${r.name!.trim()}"');
    return parts.isEmpty ? id : parts.join(' • ');
  }

  String _ammoLabel(String? id) {
    if (id == null) return '—';
    final a = state.ammoLots.firstWhere((x) => x.id == id, orElse: () => AmmoLot(id: id, caliber: '', grain: 0, bullet: '', notes: ''));
    final parts = <String>[];
    if (a.manufacturer != null && a.manufacturer!.trim().isNotEmpty) parts.add(a.manufacturer!.trim());
    if (a.name != null && a.name!.trim().isNotEmpty) parts.add(a.name!.trim());
    final bullet = a.bullet.trim().isEmpty ? null : a.bullet.trim();
    if (bullet != null) parts.add(bullet);
    if (a.grain > 0) parts.add('${a.grain}gr');
    if (a.caliber.trim().isNotEmpty) parts.add(a.caliber.trim());
    return parts.isEmpty ? id : parts.join(' • ');
  }

  String _fmt(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = session.strings.length;
    final activeIdx = session.strings.indexWhere((x) => x.id == session.activeStringId);
    final n = (activeIdx >= 0) ? (activeIdx + 1) : total;
    final active = (activeIdx >= 0) ? session.strings[activeIdx] : null;

    final started = (active == null) ? '—' : _fmt(active.startedAt);

    return Card(
      child: ListTile(
        title: Text('String $n of $total'),
        subtitle: Text('Started: $started\nRifle: ${_rifleLabel(active?.rifleId)}\nAmmo: ${_ammoLabel(active?.ammoLotId)}'),
        trailing: const Icon(Icons.list),
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => _StringsDialog(state: state, session: session),
          );
        },
      ),
    );
  }
}

class _StringsDialog extends StatelessWidget {
  final AppState state;
  final TrainingSession session;
  const _StringsDialog({required this.state, required this.session});

  String _fmt(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _rifleLabel(String? id) {
    if (id == null) return '—';
    final r = state.rifles.firstWhere((x) => x.id == id, orElse: () => Rifle(id: id, caliber: '', notes: '', dope: '', dopeEntries: const [], preferredUnit: ElevationUnit.mil));
    final parts = <String>[];
    if (r.manufacturer != null && r.manufacturer!.trim().isNotEmpty) parts.add(r.manufacturer!.trim());
    if (r.model != null && r.model!.trim().isNotEmpty) parts.add(r.model!.trim());
    if (r.caliber.trim().isNotEmpty) parts.add(r.caliber.trim());
    if (r.name != null && r.name!.trim().isNotEmpty) parts.add('"${r.name!.trim()}"');
    return parts.isEmpty ? id : parts.join(' • ');
  }

  String _ammoLabel(String? id) {
    if (id == null) return '—';
    final a = state.ammoLots.firstWhere((x) => x.id == id, orElse: () => AmmoLot(id: id, caliber: '', grain: 0, bullet: '', notes: ''));
    final parts = <String>[];
    if (a.manufacturer != null && a.manufacturer!.trim().isNotEmpty) parts.add(a.manufacturer!.trim());
    if (a.name != null && a.name!.trim().isNotEmpty) parts.add(a.name!.trim());
    final bullet = a.bullet.trim().isEmpty ? null : a.bullet.trim();
    if (bullet != null) parts.add(bullet);
    if (a.grain > 0) parts.add('${a.grain}gr');
    if (a.caliber.trim().isNotEmpty) parts.add(a.caliber.trim());
    return parts.isEmpty ? id : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Strings'),
      content: SizedBox(
        width: 520,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: session.strings.length,
          itemBuilder: (context, i) {
            final st = session.strings[i];
            final isActive = st.id == session.activeStringId;

            final parts = <String>[
              'Started: ${_fmt(st.startedAt)}',
              if (st.endedAt != null) 'Ended: ${_fmt(st.endedAt!)}',
              'Rifle: ${_rifleLabel(st.rifleId)}',
              'Ammo: ${_ammoLabel(st.ammoLotId)}',
            ];
            final subtitle = parts.join('\n');

            return Card(
              child: ListTile(
                title: Text('String ${i + 1}${isActive ? ' (active)' : ''}'),
                subtitle: Text(subtitle),
                onTap: () {
                  state.setActiveString(sessionId: session.id, stringId: st.id);
                  Navigator.pop(context);
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w800));
  }
}

class _HintCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _HintCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(message),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

///
/// Dialogs
///

class _NewUserResult {
  final String? name;
  final String identifier;
  _NewUserResult(this.name, this.identifier);
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _name = TextEditingController();
  final _id = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            decoration: const InputDecoration(labelText: 'Identifier *'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final nameRaw = _name.text.trim();
            final name = nameRaw.isEmpty ? null : nameRaw;
            final identifier = _id.text.trim();
            if (identifier.isEmpty) return;
            Navigator.of(context).pop(_NewUserResult(((name ?? '').trim().isEmpty) ? identifier : (name ?? '').trim(), identifier));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _NewSessionResult {
  final String locationName;
  final DateTime dateTime;
  final String notes;
  final double? latitude;
  final double? longitude;
  final double? temperatureF;
  final double? windSpeedMph;
  final int? windDirectionDeg;
  _NewSessionResult({
    required this.locationName,
    required this.dateTime,
    required this.notes,
    this.latitude,
    this.longitude,
    this.temperatureF,
    this.windSpeedMph,
    this.windDirectionDeg,
  });
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog();

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _tempF = TextEditingController();
  final _windMph = TextEditingController();
  final _windDir = TextEditingController();
  DateTime _dateTime = DateTime.now();
  double? _lat;
  double? _lon;
  bool _busy = false;
  String? _gpsError;

  Future<void> _fillGps() async {
    await _useGps();
  }

  Future<void> _grabWeather() async {
    await _fetchWeather();
  }
@override
  void dispose() {
    _location.dispose();
    _notes.dispose();
    _tempF.dispose();
    _windMph.dispose();
    _windDir.dispose();
    super.dispose();
  }

  
  Future<void> _useGps() async {
    setState(() {
      _busy = true;
      _gpsError = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => _gpsError = 'Location Services are off.');
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _gpsError = 'Location permission denied.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _lat = pos.latitude;
      _lon = pos.longitude;
      _location.text = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    } catch (e) {
      setState(() => _gpsError = 'GPS failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchWeather() async {
    if (_lat == null || _lon == null) {
      setState(() => _gpsError = 'Tap "Use GPS" first (or enter coordinates).');
      return;
    }
    setState(() {
      _busy = true;
      _gpsError = null;
    });
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${_lat}&longitude=${_lon}'
        '&current=temperature_2m,wind_speed_10m,wind_direction_10m'
        '&temperature_unit=fahrenheit&wind_speed_unit=mph',
      );
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        throw 'HTTP ${resp.statusCode}';
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      if (current == null) throw 'No current weather data.';
      final t = (current['temperature_2m'] as num?)?.toDouble();
      final w = (current['wind_speed_10m'] as num?)?.toDouble();
      final d = (current['wind_direction_10m'] as num?)?.toInt();
      if (t != null) _tempF.text = t.toStringAsFixed(1);
      if (w != null) _windMph.text = w.toStringAsFixed(1);
      if (d != null) _windDir.text = d.toString();
    } catch (e) {
      setState(() => _gpsError = 'Weather fetch failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDate: _dateTime,
    );
    if (d == null) return;
    if (!mounted) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (t == null) return;

    setState(() {
      _dateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Location *'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('Date/Time: ${_fmtDateTime(_dateTime)}')),
              TextButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.event),
                label: const Text('Change'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _lat == null || _lon == null
                      ? (_gpsError ?? 'GPS: not set')
                      : 'GPS: ${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}',
                ),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : _fillGps,
                child: Text(_busy ? '...' : 'Use GPS'),
              ),
            const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _busy ? null : _grabWeather,
                child: Text(_busy ? '...' : 'Grab Weather'),
              ),
],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tempF,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Temp (°F)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _windMph,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Wind (mph)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _windDir,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Wind dir (°)'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final loc = _location.text.trim();
            if (loc.isEmpty) return;
            Navigator.of(context).pop(
              _NewSessionResult(locationName: loc, dateTime: _dateTime, notes: _notes.text, latitude: _lat, longitude: _lon, temperatureF: double.tryParse(_tempF.text.trim()), windSpeedMph: double.tryParse(_windMph.text.trim()), windDirectionDeg: int.tryParse(_windDir.text.trim())),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _ColdBoreResult {
  final DateTime time;
  final String distance;
  final String result;
  final String notes;
  _ColdBoreResult({required this.time, required this.distance, required this.result, required this.notes});
}

class _ColdBoreDialog extends StatefulWidget {
  _ColdBoreDialog({super.key, DateTime? defaultTime}) : defaultTime = defaultTime ?? DateTime.now();

  final DateTime defaultTime;

  @override
  State<_ColdBoreDialog> createState() => _ColdBoreDialogState();
}

class _ColdBoreDialogState extends State<_ColdBoreDialog> {
  final _distance = TextEditingController(text: '100 yd');
  final _result = TextEditingController(text: 'Impact OK');
  final _notes = TextEditingController();
  late DateTime _time;

  @override
  void initState() {
    super.initState();
    _time = widget.defaultTime;
  }

  @override
  void dispose() {
    _distance.dispose();
    _result.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (t == null) return;
    setState(() {
      _time = DateTime(_time.year, _time.month, _time.day, t.hour, t.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cold bore entry'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('Time: ${_fmtDateTime(_time)}')),
              TextButton(onPressed: _pickTime, child: const Text('Edit')),
            ],
          ),
          TextField(
            controller: _distance,
            decoration: const InputDecoration(labelText: 'Distance'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _result,
            decoration: const InputDecoration(labelText: 'Result'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final distance = _distance.text.trim();
            final result = _result.text.trim();
            if (distance.isEmpty || result.isEmpty) return;
            Navigator.of(context).pop(
              _ColdBoreResult(time: _time, distance: distance, result: result, notes: _notes.text),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditNotesDialog extends StatefulWidget {
  final String initialNotes;
  const _EditNotesDialog({required this.initialNotes});

  @override
  State<_EditNotesDialog> createState() => _EditNotesDialogState();
}

class _EditNotesDialogState extends State<_EditNotesDialog> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notes'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _c,
              decoration: const InputDecoration(labelText: 'DOPE notes (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: Keep this in whatever format you prefer (e.g., come-ups, holds, or a quick reference table).',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_c.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}




class _PhotoNoteDialog extends StatefulWidget {
  const _PhotoNoteDialog();

  @override
  State<_PhotoNoteDialog> createState() => _PhotoNoteDialogState();
}

class _PhotoNoteDialogState extends State<_PhotoNoteDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Photo caption'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _c,
          decoration: const InputDecoration(labelText: 'Caption (optional)'),
          textInputAction: TextInputAction.done,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_c.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditDopeDialog extends StatefulWidget {
  final String initialValue;
  const _EditDopeDialog({required this.initialValue});

  @override
  State<_EditDopeDialog> createState() => _EditDopeDialogState();
}

class _EditDopeDialogState extends State<_EditDopeDialog> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit DOPE'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _c,
          decoration: const InputDecoration(labelText: 'DOPE notes'),
          maxLines: 6,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_c.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}


class _ShareSessionDialog extends StatefulWidget {
  final String sessionTitle;
  final List<UserProfile> users;
  final Set<String> initiallySelected;

  const _ShareSessionDialog({
    required this.sessionTitle,
    required this.users,
    required this.initiallySelected,
  });

  @override
  State<_ShareSessionDialog> createState() => _ShareSessionDialogState();
}

class _ShareSessionDialogState extends State<_ShareSessionDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelected};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Share "${_cleanText(widget.sessionTitle)}"'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: widget.users.map((u) {
            final checked = _selected.contains(u.id);
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checked,
              title: Text(u.identifier),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(u.id);
                  } else {
                    _selected.remove(u.id);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Share'),
        ),
      ],
    );
  }
}


class _NewRifleDialog extends StatefulWidget {
  const _NewRifleDialog({this.existing});

  final Rifle? existing;

  @override
  State<_NewRifleDialog> createState() => _NewRifleDialogState();
}

class _NewRifleDialogState extends State<_NewRifleDialog> {
  final _name = TextEditingController();
  final _caliber = TextEditingController();
  final _manufacturer = TextEditingController();
  final _model = TextEditingController();
  final _scopeMake = TextEditingController();
  final _scopeModel = TextEditingController();
  final _scopeSerial = TextEditingController();
  final _scopeMount = TextEditingController();
  final _scopeNotes = TextEditingController();
  final _serialNumber = TextEditingController();
  final _barrelLength = TextEditingController();
  final _twistRate = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _purchaseLocation = TextEditingController();
  final _notes = TextEditingController();
  final _dope = TextEditingController();
  DateTime? _purchaseDate;
  ScopeUnit _scopeUnit = ScopeUnit.mil;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r != null) {
      _name.text = r.name ?? '';
      _caliber.text = r.caliber;
      _manufacturer.text = r.manufacturer ?? '';
      _model.text = r.model ?? '';
      _scopeUnit = r.scopeUnit;
      _scopeMake.text = r.scopeMake ?? '';
      _scopeModel.text = r.scopeModel ?? '';
      _scopeSerial.text = r.scopeSerial ?? '';
      _scopeMount.text = r.scopeMount ?? '';
      _scopeNotes.text = r.scopeNotes ?? '';
      _serialNumber.text = r.serialNumber ?? '';
      _barrelLength.text = r.barrelLength ?? '';
      _twistRate.text = r.twistRate ?? '';
      _purchaseDate = r.purchaseDate;
      _purchasePrice.text = r.purchasePrice ?? '';
      _purchaseLocation.text = r.purchaseLocation ?? '';
      _notes.text = r.notes;
      _dope.text = r.dope;
      _scopeUnit = r.scopeUnit;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _caliber.dispose();
    _manufacturer.dispose();
    _model.dispose();
    _serialNumber.dispose();
    _barrelLength.dispose();
    _twistRate.dispose();
    _purchasePrice.dispose();
    _purchaseLocation.dispose();
    _notes.dispose();
    _dope.dispose();
    _scopeMake.dispose();
    _scopeModel.dispose();
    _scopeSerial.dispose();
    _scopeMount.dispose();
    _scopeNotes.dispose();
    super.dispose();
  }

  void _save() {
    final caliber = _caliber.text.trim();
    if (caliber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caliber is required')),
      );
      return;
    }

    
    final man = _manufacturer.text.trim();
    final mod = _model.text.trim();
    if (man.isEmpty || mod.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manufacturer and model are required')),
      );
      return;
    }

Navigator.of(context).pop(
      _NewRifleResult(
      scopeUnit: _scopeUnit,
        manualRoundCount: widget.existing?.manualRoundCount ?? 0,
        scopeMake: _scopeMake.text.trim().isEmpty ? null : _scopeMake.text.trim(),
        scopeModel: _scopeModel.text.trim().isEmpty ? null : _scopeModel.text.trim(),
        scopeSerial: _scopeSerial.text.trim().isEmpty ? null : _scopeSerial.text.trim(),
        scopeMount: _scopeMount.text.trim().isEmpty ? null : _scopeMount.text.trim(),
        scopeNotes: _scopeNotes.text.trim().isEmpty ? null : _scopeNotes.text.trim(),
name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        caliber: caliber,
        notes: _notes.text.trim(),
        dope: _dope.text.trim(),
        dopeEntries: widget.existing?.dopeEntries ?? const [],
        manufacturer: _manufacturer.text.trim().isEmpty ? null : _manufacturer.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
        serialNumber: _serialNumber.text.trim().isEmpty ? null : _serialNumber.text.trim(),
        barrelLength: _barrelLength.text.trim().isEmpty ? null : _barrelLength.text.trim(),
        twistRate: _twistRate.text.trim().isEmpty ? null : _twistRate.text.trim(),
        purchaseDate: _purchaseDate,
        purchasePrice: _purchasePrice.text.trim().isEmpty ? null : _purchasePrice.text.trim(),
        purchaseLocation: _purchaseLocation.text.trim().isEmpty ? null : _purchaseLocation.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add rifle' : 'Edit rifle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            TextField(
              controller: _caliber,
              decoration: const InputDecoration(labelText: 'Caliber (ex: .308) *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manufacturer,
              decoration: const InputDecoration(labelText: 'Manufacturer *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Other details'),
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: _serialNumber,
                  decoration: const InputDecoration(labelText: 'Serial number (optional)'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _barrelLength,
                        decoration: const InputDecoration(labelText: 'Barrel length (optional)'),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _twistRate,
                        decoration: const InputDecoration(labelText: 'Twist rate (optional)'),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(_purchaseDate == null
                          ? 'Purchase date (optional)'
                          : 'Purchase date: ${_purchaseDate!.month}/${_purchaseDate!.day}/${_purchaseDate!.year}'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(1970),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _purchaseDate = picked);
                        }
                      },
                      child: const Text('Pick'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _purchasePrice,
                  decoration: const InputDecoration(labelText: 'Purchase price (optional)'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _purchaseLocation,
                  decoration: const InputDecoration(labelText: 'Purchase location (optional)'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
              ],
            ),

            const SizedBox(height: 12),

            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Scope'),
              subtitle: Text('Adjustment unit: ${_scopeUnit.name.toUpperCase()}'),
              children: [
                const SizedBox(height: 8),
                DropdownButtonFormField<ScopeUnit>(
                  value: _scopeUnit,
                  decoration: const InputDecoration(labelText: 'Adjustment unit'),
                  items: ScopeUnit.values
                      .map((u) => DropdownMenuItem(value: u, child: Text(u.name.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setState(() => _scopeUnit = v ?? ScopeUnit.mil),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _scopeMake,
                  decoration: const InputDecoration(labelText: 'Scope make (optional)'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _scopeModel,
                  decoration: const InputDecoration(labelText: 'Scope model (optional)'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _scopeSerial,
                  decoration: const InputDecoration(labelText: 'Scope serial (optional)'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _scopeMount,
                  decoration: const InputDecoration(labelText: 'Mount/rings (optional)'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _scopeNotes,
                  decoration: const InputDecoration(labelText: 'Scope notes (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
              ],
            ),
],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _NewRifleResult {
  final ScopeUnit scopeUnit;
  final int manualRoundCount;

  final String? scopeMake;
  final String? scopeModel;
  final String? scopeSerial;
  final String? scopeMount;
  final String? scopeNotes;

final String? name;
  final String caliber;
  final String notes;
  final String dope;
  final List<RifleDopeEntry> dopeEntries;

  final String? manufacturer;
  final String? model;
  final String? serialNumber;
  final String? barrelLength;
  final String? twistRate;
  final DateTime? purchaseDate;
  final String? purchasePrice;
  final String? purchaseLocation;

  _NewRifleResult({
    this.scopeUnit = ScopeUnit.mil,
    this.manualRoundCount = 0,
    this.scopeMake,
    this.scopeModel,
    this.scopeSerial,
    this.scopeMount,
    this.scopeNotes,
    this.name,
    required this.caliber,
required this.notes,
    required this.dope,
    this.dopeEntries = const [],
    this.manufacturer,
    this.model,
    this.serialNumber,
    this.barrelLength,
    this.twistRate,
    this.purchaseDate,
    this.purchasePrice,
    this.purchaseLocation,
  });
}



class _NewAmmoResult {
  _NewAmmoResult({
    this.name,
    required this.caliber,
required this.grain,
    required this.bullet,
    this.ballisticCoefficient,
    this.manufacturer,
    this.lotNumber,
    this.purchaseDate,
    this.purchasePrice,
    this.notes,
  });

  final String? name;
  final String caliber;
  final int grain;
  final String bullet;
  final double? ballisticCoefficient;
  final String? manufacturer;
  final String? lotNumber;
  final DateTime? purchaseDate;
  final String? purchasePrice;
  final String? notes;
}

class _NewAmmoDialog extends StatefulWidget {
  const _NewAmmoDialog({this.existing});
  final AmmoLot? existing;

  @override
  State<_NewAmmoDialog> createState() => _NewAmmoDialogState();
}

class _NewAmmoDialogState extends State<_NewAmmoDialog> {
  final _name = TextEditingController();
  final _caliber = TextEditingController();
  final _manufacturer = TextEditingController();
  final _bullet = TextEditingController();
  final _grain = TextEditingController();
  final _bc = TextEditingController();
  final _lot = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _purchaseDate;
  ScopeUnit _scopeUnit = ScopeUnit.mil;
  final _purchasePrice = TextEditingController();


  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    if (a != null) {
      _name.text = a.name ?? '';
      _caliber.text = a.caliber;
      _manufacturer.text = a.manufacturer ?? '';
      _bullet.text = a.bullet;
      _grain.text = a.grain.toString();
      _bc.text = (a.ballisticCoefficient?.toString() ?? '');
      _lot.text = a.lotNumber ?? '';
      _purchaseDate = a.purchaseDate;
      _purchasePrice.text = a.purchasePrice ?? '';
      _notes.text = a.notes;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _caliber.dispose();
    _manufacturer.dispose();
    _bullet.dispose();
    _grain.dispose();
    _bc.dispose();
    _lot.dispose();
    _notes.dispose();
    _purchasePrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add ammo' : 'Edit ammo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _caliber,
              decoration: const InputDecoration(labelText: 'Caliber (ex: .308) *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bullet,
              decoration: const InputDecoration(labelText: 'Bullet (ex: SMK) *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _grain,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Bullet grain (ex: 175) *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bc,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Ballistic coefficient (optional)'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manufacturer,
              decoration: const InputDecoration(labelText: 'Manufacturer *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lot,
              decoration: const InputDecoration(labelText: 'Lot number (optional)'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _purchaseDate == null
                        ? 'Purchase date (optional)'
                        : 'Purchase date: ${_fmtDate(_purchaseDate!)}',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _purchaseDate ?? DateTime(now.year, now.month, now.day),
                      firstDate: DateTime(1990),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (picked != null) setState(() => _purchaseDate = picked);
                  },
                  child: const Text('Pick'),
                ),
                if (_purchaseDate != null)
                  IconButton(
                    tooltip: 'Clear',
                    onPressed: () => setState(() => _purchaseDate = null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purchasePrice,
              decoration: const InputDecoration(labelText: 'Purchase price (optional)'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              minLines: 2,
              maxLines: 5,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final caliber = _caliber.text.trim();
            final bullet = _bullet.text.trim();
            final grainStr = _grain.text.trim();

            if (caliber.isEmpty || bullet.isEmpty || grainStr.isEmpty) return;

            final grain = int.tryParse(grainStr);
            if (grain == null) return;

            final nameRaw = _name.text.trim();
            final name = nameRaw.isEmpty ? null : nameRaw;

            final manufacturerRaw = _manufacturer.text.trim();
            final manufacturer = manufacturerRaw.isEmpty ? null : manufacturerRaw;

            final lotRaw = _lot.text.trim();
            final lot = lotRaw.isEmpty ? null : lotRaw;

            final bcRaw = _bc.text.trim();
            final bc = bcRaw.isEmpty ? null : double.tryParse(bcRaw);

            final priceRaw = _purchasePrice.text.trim();
            final price = priceRaw.isEmpty ? null : priceRaw;

            final notesRaw = _notes.text.trim();
            final notes = notesRaw.isEmpty ? null : notesRaw;

            Navigator.of(context).pop(
              _NewAmmoResult(
                name: name,
                caliber: caliber,
                grain: grain,
                bullet: bullet,
                ballisticCoefficient: bc,
                manufacturer: manufacturer,
                lotNumber: lot,
                purchaseDate: _purchaseDate,
                purchasePrice: price,
                notes: notes,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _fmtDateTime(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final y = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$m/$d/$y $hh:$mm';
}

class DopeManagerScreen extends StatelessWidget {
  final AppState state;
  final Rifle rifle;
  const DopeManagerScreen({super.key, required this.state, required this.rifle});

  @override
  Widget build(BuildContext context) {
    final entries = rifle.dopeEntries;
    return Scaffold(
      appBar: AppBar(
        title: Text('DOPE • ${rifle.name}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final res = await showDialog<RifleDopeEntry>(
            context: context,
            builder: (_) => const _RifleDopeEntryDialog(),
          );
          if (res != null) {
            state.addRifleDopeEntry(
              rifle.id,
              RifleDopeEntry(
                id: state.newIdForChild(),
                distance: res.distance,
                elevation: res.elevation,
                windage: res.windage,
                notes: res.notes ?? '',
              ),
            );
          }
        },
        child: const Icon(Icons.add),
      ),
      body: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No DOPE entries yet.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to add your first DOPE entry.'),
                  if (rifle.dope.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Legacy DOPE (single field)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(rifle.dope),
                  ],
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = entries[i];
                return ListTile(
                  title: Text('${e.distance} • Elev ${e.elevation} • Wind ${e.windage}'),
                  subtitle: e.notes.trim().isEmpty ? null : Text(e.notes),
                  onTap: () async {
                    final edited = await showDialog<RifleDopeEntry>(
                      context: context,
                      builder: (_) => _RifleDopeEntryDialog(existing: e),
                    );
                    if (edited != null) {
                      state.updateRifleDopeEntry(
                        rifle.id,
                        e.copyWith(
                          distance: edited.distance,
                          elevation: edited.elevation,
                          windage: edited.windage,
                          notes: edited.notes,
                        ),
                      );
                    }
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete DOPE entry?'),
                          content: const Text('This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        state.deleteRifleDopeEntry(rifle.id, e.id);
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _RifleDopeEntryDialog extends StatefulWidget {
  final RifleDopeEntry? existing;
  const _RifleDopeEntryDialog({this.existing});

  @override
  State<_RifleDopeEntryDialog> createState() => _RifleDopeEntryDialogState();
}

class _RifleDopeEntryDialogState extends State<_RifleDopeEntryDialog> {
  late final TextEditingController _distance;
  late final TextEditingController _elev;
  late final TextEditingController _wind;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _distance = TextEditingController(text: widget.existing?.distance ?? '');
    _elev = TextEditingController(text: widget.existing?.elevation ?? '');
    _wind = TextEditingController(text: widget.existing?.windage ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _distance.dispose();
    _elev.dispose();
    _wind.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add DOPE' : 'Edit DOPE'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _distance,
              decoration: const InputDecoration(labelText: 'Distance (yd/m)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _elev,
              decoration: const InputDecoration(labelText: 'Elevation (dial)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _wind,
              decoration: const InputDecoration(labelText: 'Windage (e.g., R0.2 / L0.1 / 0)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              RifleDopeEntry(
                id: 'tmp',
                distance: _distance.text.trim(),
                elevation: _elev.text.trim(),
                windage: _wind.text.trim(),
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );

  }
}


class MaintenanceHubScreen extends StatelessWidget {
  final AppState state;
  const MaintenanceHubScreen({super.key, required this.state});

  String _rifleLabel(Rifle r) {
    final m = (r.manufacturer ?? '').trim();
    final model = (r.model ?? '').trim();
    final name = (r.name ?? '').trim();
    final parts = <String>[
      r.caliber.trim(),
      if (m.isNotEmpty) m,
      if (model.isNotEmpty) model,
      if (name.isNotEmpty) name,
    ];
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final rifles = state.rifles;
        return Scaffold(
          appBar: AppBar(title: const Text('Maintenance')),
          body: ListView.separated(
            itemCount: rifles.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rifles[i];
              final total = state.totalRoundsForRifle(r.id);
              return ListTile(
                leading: const Icon(Icons.build_outlined),
                title: Text(_rifleLabel(r)),
                subtitle: Text('Total rounds: $total'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RifleServiceLogScreen(state: state, rifleId: r.id),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class RifleServiceLogScreen extends StatefulWidget {
  final AppState state;
  final String rifleId;
  const RifleServiceLogScreen({super.key, required this.state, required this.rifleId});

  @override
  State<RifleServiceLogScreen> createState() => _RifleServiceLogScreenState();
}

class _RifleServiceLogScreenState extends State<RifleServiceLogScreen> {
  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$mm/$dd/$yyyy';
  }

  Future<void> _addService() async {
    final res = await showDialog<RifleServiceEntry>(
      context: context,
      builder: (_) => _AddRifleServiceDialog(state: widget.state, rifleId: widget.rifleId),
    );
    if (res == null) return;
    widget.state.addRifleService(rifleId: widget.rifleId, entry: res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Service log')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addService,
        child: const Icon(Icons.add),
      ),
      body: AnimatedBuilder(
        animation: widget.state,
        builder: (context, _) {
          final rifle = widget.state.rifleById(widget.rifleId);
          final services = rifle?.services ?? const <RifleServiceEntry>[];

          if (rifle == null) return const Center(child: Text('Rifle not found.'));
          if (services.isEmpty) return const Center(child: Text('No services logged yet.'));

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: services.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = services[i];
              return ListTile(
                title: Text(s.service),
                subtitle: Text('${_fmtDate(s.date)} • ${s.roundsAtService} rds' +
                    (s.notes.trim().isEmpty ? '' : ' • ${s.notes.trim()}')),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete service entry?'),
                        content: const Text('This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      widget.state.deleteRifleService(rifleId: widget.rifleId, serviceId: s.id);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddRifleServiceDialog extends StatefulWidget {
  final AppState state;
  final String rifleId;
  const _AddRifleServiceDialog({required this.state, required this.rifleId});

  @override
  State<_AddRifleServiceDialog> createState() => _AddRifleServiceDialogState();
}

class _AddRifleServiceDialogState extends State<_AddRifleServiceDialog> {
  final _serviceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _useCurrentRounds = true;
  final _roundsCtrl = TextEditingController();

  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$mm/$dd/$yyyy';
  }

  @override
  void dispose() {
    _serviceCtrl.dispose();
    _notesCtrl.dispose();
    _roundsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentRounds = widget.state.totalRoundsForRifle(widget.rifleId);

    return AlertDialog(
      title: const Text('Log service'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _serviceCtrl,
              decoration: const InputDecoration(labelText: 'Service'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_fmtDate(_date)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use current total rounds'),
              subtitle: Text(_useCurrentRounds ? '$currentRounds rds' : 'Enter manually'),
              value: _useCurrentRounds,
              onChanged: (v) => setState(() => _useCurrentRounds = v),
            ),
            if (!_useCurrentRounds)
              TextField(
                controller: _roundsCtrl,
                decoration: const InputDecoration(labelText: 'Rounds at service'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final service = _serviceCtrl.text.trim();
            if (service.isEmpty) return;

            final rounds = _useCurrentRounds
                ? currentRounds
                : (int.tryParse(_roundsCtrl.text.trim()) ?? currentRounds);

            final entry = RifleServiceEntry(
              id: widget.state.newIdForChild(),
              service: service,
              date: _date,
              roundsAtService: rounds,
              notes: _notesCtrl.text.trim(),
            );

            Navigator.pop(context, entry);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}


class _BackupScreen extends StatelessWidget {
  final AppState state;
  const _BackupScreen({required this.state});

  
  void _showExportText(BuildContext context, String title, String text) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: SelectableText(text),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')),
            );
          },
          child: const Text('Copy'),
        ),
        if (kIsWeb)
          TextButton(
            onPressed: () {
              final safe = title
                  .toLowerCase()
                  .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                  .replaceAll(RegExp(r'_+'), '_')
                  .replaceAll(RegExp(r'^_|_$'), '');
              final ext = title.toLowerCase().contains('csv') ? 'csv' : 'txt';
              _downloadTextFileWeb('cold_bore_${safe.isEmpty ? 'export' : safe}.$ext', text,
                  mimeType: ext == 'csv' ? 'text/csv' : 'text/plain');
            },
            child: const Text('Download'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    ),
  );
}


  Future<void> _exportBackupFile(BuildContext context) async {
    try {
      final ts = DateTime.now();
      final fname = 'cold_bore_backup_${ts.year.toString().padLeft(4,'0')}-${ts.month.toString().padLeft(2,'0')}-${ts.day.toString().padLeft(2,'0')}.json';
      final json = state.exportBackupJson();

      // Web: download directly (no sandboxed filesystem)
      if (kIsWeb) {
        _downloadTextFileWeb(fname, json, mimeType: 'application/json');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup downloaded.')),
        );
        return;
      }

      // Mobile/Desktop: write file then share
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fname');
      await file.writeAsString(json, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Cold Bore backup');
} catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed.')),
      );
    }
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.save_alt_outlined),
              title: const Text('Backup (JSON)'),
              subtitle: const Text('Copy a backup of rifles & ammo'),
              onTap: () => _exportBackupFile(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Restore (JSON)'),
              subtitle: const Text('Import a backup file (web) or paste JSON'),
              onTap: () async {
                // On web: pick a .json file and merge (preserving history).
                if (kIsWeb) {
                  final choice = await showModalBottomSheet<String>(
                    context: context,
                    builder: (_) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.merge_type),
                            title: const Text('Merge (recommended)'),
                            subtitle: const Text('Overwrite scope fields; keep IDs & history'),
                            onTap: () => Navigator.of(context).pop('merge'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.warning_amber_outlined),
                            title: const Text('Replace equipment'),
                            subtitle: const Text('Replace rifles & ammo lists (history stays)'),
                            onTap: () => Navigator.of(context).pop('replace'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (choice == null) return;

                  final jsonText = await _pickWebJsonFile();
                  if (jsonText == null) return;

                  try {
                    if (choice == 'merge') {
                      state.mergeBackupJson(jsonText, overwriteScope: true);
                    } else {
                      state.importBackupJson(jsonText, replaceExisting: true);
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Import complete.')),
                    );
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Import failed. Invalid JSON.')),
                    );
                  }
                  return;
                }

                // Non-web: paste JSON (and choose merge/replace)
                final res = await showDialog<_ImportBackupResult>(
                  context: context,
                  builder: (_) => const _ImportBackupDialog(),
                );
                if (res == null) return;
                try {
                  if (res.mode == _ImportMode.merge) {
                    state.mergeBackupJson(res.jsonText, overwriteScope: true);
                  } else {
                    state.importBackupJson(res.jsonText, replaceExisting: true);
                  }
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Import complete.')),
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Import failed. Invalid JSON.')),
                  );
                }
              },
            ),
          ),

        ],
      ),
    );
  }
}

enum _ImportMode { merge, replace }

class _ImportBackupResult {
  final String jsonText;
  final _ImportMode mode;
  const _ImportBackupResult({required this.jsonText, required this.mode});
}
class _ImportBackupDialog extends StatefulWidget {
  const _ImportBackupDialog();

  @override
  State<_ImportBackupDialog> createState() => _ImportBackupDialogState();
}

class _ImportBackupDialogState extends State<_ImportBackupDialog> {
  final _ctrl = TextEditingController();
  _ImportMode _mode = _ImportMode.merge;
@override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restore backup (JSON)'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Import mode'),
              const SizedBox(height: 8),
              RadioListTile<_ImportMode>(
                value: _ImportMode.merge,
                groupValue: _mode,
                onChanged: (v) => setState(() => _mode = v ?? _ImportMode.merge),
                title: const Text('Merge (recommended)'),
                subtitle: const Text('Overwrite scope fields; keep equipment IDs & all history'),
              ),
              RadioListTile<_ImportMode>(
                value: _ImportMode.replace,
                groupValue: _mode,
                onChanged: (v) => setState(() => _mode = v ?? _ImportMode.merge),
                title: const Text('Replace equipment'),
                subtitle: const Text('Replace rifles & ammo lists (history stays)'),
              ),
            ],
          ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: 'Paste backup JSON',
                border: OutlineInputBorder(),
              ),
              minLines: 6,
              maxLines: 12,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final t = _ctrl.text.trim();
            if (t.isEmpty) return;
            Navigator.of(context).pop(_ImportBackupResult(jsonText: t, mode: _mode));
          },
          child: const Text('Import'),
        ),
      ],
    );
  }
}