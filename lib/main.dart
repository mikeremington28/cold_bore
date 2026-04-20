// ignore_for_file: avoid_types_as_parameter_names, curly_braces_in_flow_control_structures, dead_code, dead_null_aware_expression, deprecated_member_use, library_private_types_in_public_api, unnecessary_underscores, unused_element, unused_element_parameter, unused_local_variable, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'package:noise_meter/noise_meter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:file_picker/file_picker.dart';
import 'cloud_sync_service.dart';
import 'subscription_service.dart';

const String kBackupSchemaVersion = '2026-02-05';
const String kLocalStatePrefsKey = 'cold_bore.local_state.v1';
const String kPdfExportPresetsPrefsKey = 'cold_bore.pdf_export_presets.v1';
const String kThemeModePrefsKey = 'cold_bore.theme_mode.v1';
final AudioPlayer _shotTimerBeepPlayer = AudioPlayer();
const MethodChannel _nearbyShareChannel = MethodChannel(
  'com.remington.coldbore/nearby_share',
);
const MethodChannel _nearbyShareEventsChannel = MethodChannel(
  'com.remington.coldbore/nearby_share_events',
);

class NearbyPeer {
  final String identifier;
  final String displayName;

  const NearbyPeer({required this.identifier, required this.displayName});
}

Uint8List _buildShotTimerBeepWav({
  int sampleRate = 44100,
  double frequencyHz = 1750,
  int durationMs = 260,
}) {
  final sampleCount = (sampleRate * durationMs / 1000).round();
  final dataLength = sampleCount * 2;
  final byteData = ByteData(44 + dataLength);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      byteData.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  byteData.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  byteData.setUint32(16, 16, Endian.little);
  byteData.setUint16(20, 1, Endian.little);
  byteData.setUint16(22, 1, Endian.little);
  byteData.setUint32(24, sampleRate, Endian.little);
  byteData.setUint32(28, sampleRate * 2, Endian.little);
  byteData.setUint16(32, 2, Endian.little);
  byteData.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  byteData.setUint32(40, dataLength, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final fadeIn = math.min(1.0, i / (sampleRate * 0.01));
    final fadeOut = math.min(1.0, (sampleCount - i) / (sampleRate * 0.02));
    final envelope = math.min(fadeIn, fadeOut);
    final sample =
        (math.sin(2 * math.pi * frequencyHz * t) * 0.9 * envelope * 32767)
            .round();
    byteData.setInt16(44 + (i * 2), sample.clamp(-32768, 32767), Endian.little);
  }

  return byteData.buffer.asUint8List();
}

Future<void> _playShotTimerBeep({
  double volume = 1.0,
  double frequencyHz = 1750.0,
}) async {
  await _shotTimerBeepPlayer.setVolume(volume);
  await _shotTimerBeepPlayer.stop();
  final bytes = _buildShotTimerBeepWav(frequencyHz: frequencyHz);
  await _shotTimerBeepPlayer.play(BytesSource(bytes, mimeType: 'audio/wav'));
}

ThemeData _buildTacticalTheme() {
  const baseBg = Color(0xFFE3E0D2);
  const surface = Color(0xFFF1EDDF);
  const surfaceAlt = Color(0xFFE0D8C3);
  const primary = Color(0xFF264653);
  const secondary = Color(0xFF7B6A3C);
  const outline = Color(0xFF8F8A78);
  const onSurface = Color(0xFF1E2019);

  const scheme = ColorScheme.light(
    primary: primary,
    onPrimary: Colors.white,
    secondary: secondary,
    onSecondary: Colors.white,
    surface: surface,
    onSurface: onSurface,
    error: Color(0xFF9D2B2B),
    onError: Colors.white,
    outline: outline,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: baseBg,
    canvasColor: baseBg,
    cardColor: surface,
    dividerColor: outline.withValues(alpha: 0.35),
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceAlt,
      foregroundColor: onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline.withValues(alpha: 0.35)),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: surfaceAlt,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? primary
              : onSurface.withValues(alpha: 0.78),
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          fontSize: 10,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? primary
              : onSurface.withValues(alpha: 0.72),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.32),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline.withValues(alpha: 0.45)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline.withValues(alpha: 0.45)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: primary, width: 1.6),
      ),
      labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.8)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceAlt,
      selectedColor: primary.withValues(alpha: 0.16),
      secondarySelectedColor: primary.withValues(alpha: 0.16),
      side: BorderSide(color: outline.withValues(alpha: 0.4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(color: onSurface),
      secondaryLabelStyle: const TextStyle(color: onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
  );
}

ThemeData _buildTacticalDarkTheme() {
  const baseBg = Color(0xFF121519);
  const surface = Color(0xFF1C2127);
  const surfaceAlt = Color(0xFF262C33);
  const primary = Color(0xFF8EB9C7);
  const secondary = Color(0xFFC6B37A);
  const outline = Color(0xFF5F6770);
  const onSurface = Color(0xFFE8ECF1);

  const scheme = ColorScheme.dark(
    primary: primary,
    onPrimary: Color(0xFF0E1A21),
    secondary: secondary,
    onSecondary: Color(0xFF2A2413),
    surface: surface,
    onSurface: onSurface,
    error: Color(0xFFFF7B7B),
    onError: Color(0xFF2A1010),
    outline: outline,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: baseBg,
    canvasColor: baseBg,
    cardColor: surface,
    dividerColor: outline.withValues(alpha: 0.45),
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceAlt,
      foregroundColor: onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline.withValues(alpha: 0.45)),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: surfaceAlt,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primary.withValues(alpha: 0.22),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? primary
              : onSurface.withValues(alpha: 0.8),
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          fontSize: 10,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? primary
              : onSurface.withValues(alpha: 0.72),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline.withValues(alpha: 0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline.withValues(alpha: 0.55)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: primary, width: 1.6),
      ),
      labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.85)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: const Color(0xFF0E1A21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Color(0xFF0E1A21),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceAlt,
      selectedColor: primary.withValues(alpha: 0.25),
      secondarySelectedColor: primary.withValues(alpha: 0.25),
      side: BorderSide(color: outline.withValues(alpha: 0.45)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(color: onSurface),
      secondaryLabelStyle: const TextStyle(color: onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
  );
}

class AppThemeController extends ChangeNotifier {
  static final AppThemeController _instance = AppThemeController._();
  factory AppThemeController() => _instance;
  AppThemeController._();

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kThemeModePrefsKey) ?? 'system';
    _mode = _themeModeFromRaw(raw);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModePrefsKey, _themeModeToRaw(mode));
    notifyListeners();
  }

  static ThemeMode _themeModeFromRaw(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToRaw(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

// --- Web-only: download a text file (no-op on mobile/desktop) ---
void _downloadTextFileWeb(
  String filename,
  String content, {
  String mimeType = 'text/plain',
}) {
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
  final needs =
      v.contains(',') ||
      v.contains('"') ||
      v.contains('\n') ||
      v.contains('\r');
  if (!needs) return v;
  return '"${v.replaceAll('"', '""')}"';
}

String _fmtDateIso(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  final y = d.year.toString().padLeft(4, '0');
  return '$m/$day/$y';
}

String _fmtDateTimeIso(DateTime d) {
  final mdy = _fmtDateIso(d);
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  final ss = d.second.toString().padLeft(2, '0');
  return '$mdy $hh:$mm:$ss';
}

bool _isSeedUserIdentifier(String identifier) {
  final normalized = identifier.trim().toUpperCase();
  return normalized == 'DEMO' || normalized == 'OWNER';
}

String _normalizeUserIdentifier(String identifier) =>
    identifier.trim().toUpperCase();

bool _isValidUserIdentifierFormat(String identifier) => RegExp(
  r'^[A-Z0-9_-]{3,24}$',
).hasMatch(_normalizeUserIdentifier(identifier));

String? _userIdentifierValidationMessage(
  String identifier, {
  bool allowSeed = false,
}) {
  final normalized = _normalizeUserIdentifier(identifier);
  if (normalized.isEmpty) {
    return 'Enter a unique identifier.';
  }
  if (!_isValidUserIdentifierFormat(normalized)) {
    return 'Use 3-24 characters: letters, numbers, dash, or underscore.';
  }
  if (!allowSeed && _isSeedUserIdentifier(normalized)) {
    return 'Choose something unique, not OWNER or DEMO.';
  }
  return null;
}

String _displayUserIdentifier(String identifier) {
  if (_isSeedUserIdentifier(identifier)) return 'Owner';
  return identifier;
}

String _displayUserName(UserProfile user) {
  final rawName = (user.name ?? '').trim();
  if (_isSeedUserIdentifier(user.identifier) ||
      rawName.toUpperCase() == 'DEMO USER') {
    return 'Owner';
  }
  if (rawName.isEmpty) return _displayUserIdentifier(user.identifier);
  return rawName;
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
    'shotTimerElapsedMs': s.shotTimerElapsedMs,
    'shotTimerFirstShotMs': s.shotTimerFirstShotMs,
    'shotTimerSplitMs': s.shotTimerSplitMs,
    'timerRuns': s.timerRuns
        .map(
          (run) => {
            'id': run.id,
            'time': _fmtDateTimeIso(run.time),
            'elapsedMs': run.elapsedMs,
            'firstShotMs': run.firstShotMs,
            'splitMs': run.splitMs,
          },
        )
        .toList(),
    'shots': s.shots
        .map(
          (x) => {
            'id': x.id,
            'time': _fmtDateTimeIso(x.time),
            'isColdBore': x.isColdBore,
            'isBaseline': x.isBaseline,
            'distance': x.distance,
            'result': x.result,
            'notes': x.notes,
            'photos': x.photos
                .map(
                  (p) => {
                    'id': p.id,
                    'time': _fmtDateTimeIso(p.time),
                    'caption': p.caption,
                  },
                )
                .toList(),
          },
        )
        .toList(),
    'trainingDope': s.trainingDope
        .map(
          (d) => {
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
          },
        )
        .toList(),
  };

  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(map)));
  return _crc32(bytes).toRadixString(16).padLeft(8, '0');
}

String _buildSessionReportText(
  AppState state, {
  required TrainingSession s,
  bool redactLocation = true,
  bool includePhotoBase64 = false,
  bool includeNotes = true,
  bool includeTrainingDope = true,
  bool includeLocation = true,
  bool includePhotos = true,
  bool includeShotResults = true,
  bool includeTimerData = true,
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
      return '$prefix${ammo.bullet} ${ammo.grain}gr';
    }
    if (s.ammoLotId == null) return '-';
    return 'Deleted ammo (${s.ammoLotId})';
  }

  final b = StringBuffer();
  b.writeln('COLD BORE - SESSION REPORT');
  b.writeln('Schema: $kExportSchemaVersion');
  b.writeln('Generated: ${_fmtDateTimeIso(DateTime.now())}');
  if (includeTimerData && s.timerRuns.isNotEmpty) {
    b.writeln('Saved timer runs: ${s.timerRuns.length}');
    for (final run in s.timerRuns) {
      final marks = <int>[
        if (run.firstShotMs > 0) run.firstShotMs,
        ...run.splitMs,
      ];
      b.writeln(
        '  - ${_fmtDateTimeIso(run.time)} | total ${run.elapsedMs} ms | first ${run.firstShotMs} ms | '
        'marks ${marks.isEmpty ? "-" : marks.join(", ")}'
        '${run.startDelayMs > 0 ? ' | delay ${run.startDelayMs} ms' : ''}'
        '${run.goalMs > 0 ? ' | goal ${run.goalMs} ms' : ''}',
      );
    }
  }
  if (includeTimerData &&
      ((s.shotTimerElapsedMs ?? 0) > 0 ||
          (s.shotTimerFirstShotMs ?? 0) > 0 ||
          s.shotTimerSplitMs.isNotEmpty)) {
    b.writeln('• Shot timer total (ms): ${s.shotTimerElapsedMs ?? 0}');
    b.writeln('• First shot (ms): ${s.shotTimerFirstShotMs ?? 0}');
    b.writeln(
      '• Split times (ms): ${s.shotTimerSplitMs.isEmpty ? '-' : s.shotTimerSplitMs.join(', ')}',
    );
  }

  b.writeln('');
  b.writeln('SESSION');
  b.writeln('• Session ID: ${s.id}');
  b.writeln('• Evidence ID (CRC32): $evidenceId');
  b.writeln('• User ID: ${s.userId}');
  b.writeln('• Date/Time: ${_fmtDateTimeIso(s.dateTime)}');
  if (!includeLocation) {
    b.writeln('• Location: [NOT SHARED]');
    b.writeln('• GPS: [NOT SHARED]');
  } else {
    b.writeln(
      '• Location: ${redactLocation ? '[REDACTED]' : (s.locationName.isEmpty ? '-' : s.locationName)}',
    );
    if (!redactLocation) {
      b.writeln(
        '• GPS: ${s.latitude?.toStringAsFixed(6) ?? '-'}, ${s.longitude?.toStringAsFixed(6) ?? '-'}',
      );
    } else {
      b.writeln('• GPS: [REDACTED]');
    }
  }
  b.writeln('• Rifle: ${rifleLabel()}');
  b.writeln('• Ammo: ${ammoLabel()}');

  if (s.temperatureF != null ||
      s.windSpeedMph != null ||
      s.windDirectionDeg != null) {
    b.writeln(
      '• Weather: '
      '${s.temperatureF != null ? '${s.temperatureF!.toStringAsFixed(1)}°F' : '-'}; '
      '${s.windSpeedMph != null ? '${s.windSpeedMph!.toStringAsFixed(1)} mph' : '-'} '
      '${s.windDirectionDeg != null ? '@ ${s.windDirectionDeg}°' : ''}',
    );
  }

  b.writeln('');
  b.writeln('NOTES');
  if (includeNotes) {
    b.writeln(s.notes.trim().isEmpty ? '-' : s.notes.trim());
  } else {
    b.writeln('[NOT SHARED]');
  }

  // Session-level photos (caption-only notes)
  b.writeln('');
  b.writeln('SESSION PHOTOS (NOTES)');
  if (!includePhotos) {
    b.writeln('[NOT SHARED]');
  } else if (s.photos.isEmpty) {
    b.writeln('-');
  } else {
    for (final p in s.photos) {
      b.writeln('• ${_fmtDateTimeIso(p.time)} - ${p.caption} (id: ${p.id})');
    }
  }

  // Dope
  b.writeln('');
  b.writeln('TRAINING DOPE');
  if (!includeTrainingDope) {
    b.writeln('[NOT SHARED]');
  } else {
    if (s.trainingDope.isEmpty) {
      b.writeln('-');
    } else {
      for (final d in s.trainingDope) {
        b.writeln(
          '• ${d.distance} - Elev: ${d.elevation} ${d.elevationUnit.name} '
          '(notes: ${d.elevationNotes.isEmpty ? '-' : d.elevationNotes}); '
          'Wind: ${d.windType.name}: ${d.windValue} '
          '(notes: ${d.windNotes.isEmpty ? '-' : d.windNotes})',
        );
      }
    }
  }

  // Shots
  b.writeln('');
  b.writeln('SHOTS');
  if (!includeShotResults) {
    b.writeln('[NOT SHARED]');
  } else if (s.shots.isEmpty) {
    b.writeln('-');
  } else {
    for (final sh in s.shots) {
      b.writeln(
        '• ${_fmtDateTimeIso(sh.time)}'
        '${sh.isColdBore ? ' [COLD]' : ''}'
        '${sh.isBaseline ? ' [BASELINE]' : ''}',
      );
      b.writeln('  - Distance: ${sh.distance}');
      b.writeln('  - Result: ${sh.result}');
      b.writeln(
        '  - Notes: ${sh.notes.trim().isEmpty ? '-' : sh.notes.trim()}',
      );

      if (sh.photos.isEmpty) {
        b.writeln('  - Photos: -');
      } else {
        b.writeln('  - Photos (${sh.photos.length}):');
        for (final ph in sh.photos) {
          final crc = _crc32(ph.bytes);
          b.writeln(
            '    • ${_fmtDateTimeIso(ph.time)} - ${ph.caption} '
            '(id: ${ph.id}; bytes: ${ph.bytes.length}; crc32: 0x${crc.toRadixString(16).padLeft(8, '0')})',
          );
          if (includePhotoBase64) {
            final b64 = base64Encode(ph.bytes);
            b.writeln('      base64: $b64');
          }
        }
      }
    }
  }

  b.writeln('');
  b.writeln('END OF SESSION REPORT');
  return _cleanText(b.toString());
}

String _buildCsvBundle(AppState state, {required bool redactLocation}) {
  final b = StringBuffer();
  b.writeln('### rifles.csv');
  b.writeln(
    'rifle_id,caliber,nickname,manufacturer,model,serial_number,barrel_length,twist_rate,purchase_date,purchase_price,purchase_location,notes,dope',
  );
  for (final r in state.rifles) {
    b.writeln(
      [
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
      ].map((x) => _csvEscape(x.toString())).join(','),
    );
  }
  b.writeln('');
  b.writeln('### ammo_lots.csv');
  b.writeln(
    'ammo_lot_id,caliber,grain,name,bullet,bc,manufacturer,lot_number,purchase_date,purchase_price,notes',
  );
  for (final a in state.ammoLots) {
    b.writeln(
      [
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
      ].map((x) => _csvEscape(x.toString())).join(','),
    );
  }
  b.writeln('');
  b.writeln('### sessions.csv');
  b.writeln(
    'session_id,evidence_id,user_id,datetime,location_name,latitude,longitude,temperature_f,wind_speed_mph,wind_direction_deg,rifle_id,rifle_label,ammo_lot_id,ammo_label,notes',
  );
  for (final sess in state.allSessions) {
    final rifle = state.rifleById(sess.rifleId);
    final ammo = state.ammoById(sess.ammoLotId);
    final rifleLabel = rifle == null
        ? (sess.rifleId == null ? '' : 'Deleted (${sess.rifleId})')
        : '${(rifle.name ?? 'Rifle').trim()} (${rifle.caliber})';
    final ammoLabel = ammo == null
        ? (sess.ammoLotId == null ? '' : 'Deleted (${sess.ammoLotId})')
        : '${(ammo.name ?? 'Ammo').trim()} (${ammo.caliber})';
    b.writeln(
      [
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
      ].map((x) => _csvEscape(x.toString())).join(','),
    );
  }

  b.writeln('');
  b.writeln('### shots.csv');
  b.writeln(
    'shot_id,session_id,session_evidence_id,time,is_cold_bore,is_baseline,distance,result,notes,photo_count',
  );
  for (final sess in state.allSessions) {
    final evid = _sessionEvidenceId(sess);
    for (final shot in sess.shots) {
      b.writeln(
        [
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
        ].map((x) => _csvEscape(x.toString())).join(','),
      );
    }
  }

  b.writeln('');
  b.writeln('### training_dope.csv');
  b.writeln(
    'dope_id,session_id,session_evidence_id,time,rifle_id,ammo_lot_id,distance,distance_unit,elevation,elevation_unit,elevation_notes,wind_type,wind_value,wind_notes,windage_left,windage_right',
  );
  for (final sess in state.allSessions) {
    final evid = _sessionEvidenceId(sess);
    for (final d in sess.trainingDope) {
      b.writeln(
        [
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
        ].map((x) => _csvEscape(x.toString())).join(','),
      );
    }
  }

  final bytes = Uint8List.fromList(utf8.encode(b.toString()));
  b.writeln('');
  b.writeln('### integrity');
  b.writeln(
    'crc32_csv_bundle,${_crc32(bytes).toRadixString(16).padLeft(8, '0')}',
  );
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AppThemeController().initialize();
  await CloudSyncService().initialize();
  runApp(const ColdBoreApp());
}

class ColdBoreApp extends StatelessWidget {
  const ColdBoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = AppThemeController();
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: 'Cold Bore',
        debugShowCheckedModeBanner: false,
        theme: _buildTacticalTheme(),
        darkTheme: _buildTacticalDarkTheme(),
        themeMode: themeController.mode,
        home: _LaunchSplashGate(child: const _AppRoot()),
      ),
    );
  }
}

class _LaunchSplashGate extends StatefulWidget {
  final Widget child;

  const _LaunchSplashGate({required this.child});

  @override
  State<_LaunchSplashGate> createState() => _LaunchSplashGateState();
}

class _LaunchSplashGateState extends State<_LaunchSplashGate> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE3E0D2), Color(0xFFF1EDDF)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 152,
                  height: 152,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Cold Bore',
                style: TextStyle(
                  color: Color(0xFF1E2019),
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  shadows: [
                    Shadow(
                      color: Color(0x33000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  final AppState _state = AppState();
  final CloudSyncService _cloud = CloudSyncService();
  static const MethodChannel _iCloudChannel = MethodChannel(
    'com.remington.coldbore/icloud',
  );
  static const MethodChannel _incomingShareChannel = MethodChannel(
    'com.remington.coldbore/incoming_share',
  );
  static const String _lastICloudBackupAtPrefsKey =
      'cold_bore.last_icloud_backup_at_utc.v1';
  static const String _lastICloudRestoreAtPrefsKey =
      'cold_bore.last_icloud_restore_at_utc.v1';
  static const String _autoICloudRestoreSuccessPrefsKey =
      'cold_bore.auto_icloud_restore_success.v1';
  static const String _tutorialShownPrefsKey = 'cold_bore.tutorial_shown.v1';

  Timer? _iCloudBackupDebounceTimer;
  DateTime? _lastICloudBackupAt;
  bool _iCloudBackupInFlight = false;
  bool _iCloudBackupQueuedDuringInFlight = false;
  bool _autoICloudBackupArmed = false;
  bool _startGuidedTourOnHome = false;
  bool _promptUniqueIdentifierOnHome = false;
  bool _ready = false;
  int _lastHandledDurableRevision = -1;
  String? _lastCloudIdentifier;
  String? _lastNearbyPresenceIdentifier;
  String? _lastObservedActiveIdentifier;
  Timer? _cloudSyncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadState());
  }

  Future<void> _loadState() async {
    try {
      await _state.loadPersistedState();
      await SubscriptionService().setCurrentUserIdentifier(
        _state.activeUserIdentifier,
      );
      _setupNearbyShareEvents();
      await _attachCloudIdentityIfNeeded();
      await _refreshNearbyPresence(force: true);
      await _attemptAutoICloudRestoreIfEligible();
      await _prepareFirstLaunchTutorialFlag();
      _promptUniqueIdentifierOnHome =
          _promptUniqueIdentifierOnHome || _shouldPromptForUniqueIdentifier();
      await _consumePendingIncomingShareFromPlatform();
      await SubscriptionService().initialize();
      _state.addListener(_onStateChanged);
      _lastHandledDurableRevision = _state.durableRevision;
      _lastObservedActiveIdentifier = _state.activeUserIdentifier?.trim();
      _autoICloudBackupArmed = true;
    } catch (e, st) {
      debugPrint('App startup initialization failed: $e\n$st');
      try {
        _state.removeListener(_onStateChanged);
      } catch (_) {}
      _state.addListener(_onStateChanged);
      _lastHandledDurableRevision = _state.durableRevision;
      _lastObservedActiveIdentifier = _state.activeUserIdentifier?.trim();
      _autoICloudBackupArmed = true;
    }

    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _prepareFirstLaunchTutorialFlag() async {
    if (!_looksLikeFreshLocalInstall()) return;
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_tutorialShownPrefsKey) == true;
    if (shown) return;

    await prefs.setBool(_tutorialShownPrefsKey, true);
    _startGuidedTourOnHome = true;
    _promptUniqueIdentifierOnHome = true;
  }

  bool _shouldPromptForUniqueIdentifier() {
    final user = _state.activeUser;
    return user != null &&
        (_isSeedUserIdentifier(user.identifier) ||
            !_isValidUserIdentifierFormat(user.identifier));
  }

  bool _looksLikeFreshLocalInstall() {
    if (_state.rifles.isNotEmpty || _state.ammoLots.isNotEmpty) return false;
    final user = _state.activeUser;
    if (user == null) return false;
    if (_state.users.length != 1) return false;
    if (!_isSeedUserIdentifier(user.identifier)) return false;

    // Fresh first-launch state may have no sessions yet.
    if (_state.allSessions.length > 1) return false;
    if (_state.allSessions.isEmpty) return true;

    final session = _state.allSessions.first;
    final hasUserData =
        session.notes.trim().isNotEmpty ||
        session.locationName.trim().isNotEmpty ||
        session.rifleId != null ||
        session.ammoLotId != null ||
        session.shots.isNotEmpty ||
        session.photos.isNotEmpty ||
        session.sessionPhotos.isNotEmpty ||
        session.trainingDope.isNotEmpty;
    return !hasUserData;
  }

  Future<void> _attemptAutoICloudRestoreIfEligible() async {
    if (!_canAutoBackupToICloud) return;
    if (!_looksLikeFreshLocalInstall()) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyRestored =
          prefs.getBool(_autoICloudRestoreSuccessPrefsKey) == true;
      if (alreadyRestored) return;

      final jsonText = await _iCloudChannel.invokeMethod<String>(
        'restoreFromiCloud',
      );
      if (jsonText == null || jsonText.trim().isEmpty) return;

      _state.importBackupJson(jsonText, replaceExisting: true);
      await prefs.setBool(_autoICloudRestoreSuccessPrefsKey, true);
      await prefs.setString(
        _lastICloudRestoreAtPrefsKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      debugPrint('Auto iCloud restore applied on first launch.');
    } catch (e, st) {
      debugPrint('Auto iCloud restore skipped/failed: $e\n$st');
    }
  }

  Future<void> _consumePendingIncomingShareFromPlatform() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final jsonText = await _incomingShareChannel.invokeMethod<String>(
        'takePendingSharedJson',
      );
      if (jsonText == null || jsonText.trim().isEmpty) return;
      _state.enqueueIncomingSharedJson(jsonText);
    } catch (e, st) {
      debugPrint('Incoming shared file check failed: $e\n$st');
    }
  }

  void _setupNearbyShareEvents() {
    _nearbyShareEventsChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'peersUpdated':
          final peersRaw = (call.arguments as List?) ?? const <Object>[];
          final peers = peersRaw.map((entry) {
            final map = Map<String, dynamic>.from(entry as Map);
            final identifier = (map['identifier'] ?? '').toString();
            final displayName = (map['displayName'] ?? '').toString();
            return NearbyPeer(identifier: identifier, displayName: displayName);
          }).toList();
          _state.setNearbyPeers(peers);
          break;
        case 'presenceState':
          final args = Map<String, dynamic>.from(
            (call.arguments as Map?) ?? {},
          );
          final message = (args['message'] ?? '').toString();
          _state.setNearbyStatusMessage(message);
          break;
        case 'payloadReceived':
          final args = Map<String, dynamic>.from(
            (call.arguments as Map?) ?? {},
          );
          final jsonText = (args['jsonText'] ?? '').toString();
          final senderIdentifier = (args['senderIdentifier'] ?? '').toString();
          if (senderIdentifier.trim().isNotEmpty) {
            _state.rememberTrustedPartnerIdentifier(senderIdentifier);
          }
          if (jsonText.trim().isNotEmpty) {
            _state.enqueueIncomingSharedJson(jsonText);
          }
          break;
        case 'payloadSent':
          final args = Map<String, dynamic>.from(
            (call.arguments as Map?) ?? {},
          );
          final peerIdentifier = (args['identifier'] ?? '').toString();
          if (peerIdentifier.trim().isNotEmpty) {
            _state.rememberTrustedPartnerIdentifier(peerIdentifier);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  peerIdentifier.trim().isEmpty
                      ? 'Nearby session sent.'
                      : 'Nearby session sent to $peerIdentifier.',
                ),
              ),
            );
          }
          break;
        case 'payloadSendFailed':
          final args = Map<String, dynamic>.from(
            (call.arguments as Map?) ?? {},
          );
          final error = (args['error'] ?? 'Nearby sharing failed.').toString();
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
          }
          break;
      }
      return null;
    });
  }

  Future<void> _refreshNearbyPresence({bool force = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final identifier = _state.activeUserIdentifier?.trim().toUpperCase();
    if (identifier == null || identifier.isEmpty) {
      _state.setNearbyStatusMessage(
        'Nearby discovery is unavailable until a user identifier is set.',
      );
      await _stopNearbyPresence();
      return;
    }
    if (_isSeedUserIdentifier(identifier)) {
      _state.setNearbyStatusMessage(
        'Set a unique user identifier to discover nearby Cold Bore users.',
      );
      await _stopNearbyPresence();
      return;
    }
    if (!_isValidUserIdentifierFormat(identifier)) {
      _state.setNearbyStatusMessage(
        'Current user identifier is invalid for nearby sharing. Use 3-24 letters, numbers, dashes, or underscores.',
      );
      await _stopNearbyPresence();
      return;
    }
    if (!force && _lastNearbyPresenceIdentifier == identifier) return;

    final displayName = _displayUserName(_state.activeUser!);
    try {
      await _nearbyShareChannel.invokeMethod('startPresence', {
        'identifier': identifier,
        'displayName': displayName,
      });
      _lastNearbyPresenceIdentifier = identifier;
      _state.setNearbyStatusMessage(
        'Nearby discovery running as $identifier. Waiting for other Cold Bore users...',
      );
    } catch (e, st) {
      debugPrint('Nearby presence start failed: $e\n$st');
      _state.setNearbyStatusMessage(
        'Nearby discovery failed to start. Check Local Network permission and try again.',
      );
    }
  }

  Future<void> _stopNearbyPresence() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _lastNearbyPresenceIdentifier = null;
    _state.setNearbyPeers(const <NearbyPeer>[]);
    _state.setNearbyStatusMessage('Nearby discovery stopped.');
    try {
      await _nearbyShareChannel.invokeMethod('stopPresence');
    } catch (e, st) {
      debugPrint('Nearby presence stop failed: $e\n$st');
    }
  }

  bool get _canAutoBackupToICloud =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void _onStateChanged() {
    final activeIdentifier = _state.activeUserIdentifier?.trim();
    if (_lastObservedActiveIdentifier != activeIdentifier) {
      _lastObservedActiveIdentifier = activeIdentifier;
      unawaited(
        SubscriptionService().setCurrentUserIdentifier(
          _state.activeUserIdentifier,
        ),
      );
      unawaited(_attachCloudIdentityIfNeeded());
      unawaited(_refreshNearbyPresence());
    }

    final durableRevision = _state.durableRevision;
    if (durableRevision == _lastHandledDurableRevision) return;
    _lastHandledDurableRevision = durableRevision;

    if (_autoICloudBackupArmed && _canAutoBackupToICloud && _ready) {
      _scheduleAutoICloudBackup();
    }

    _cloudSyncDebounce?.cancel();
    _cloudSyncDebounce = Timer(const Duration(milliseconds: 900), () async {
      final ownerIdentifier = _state.activeUserIdentifier;
      if (ownerIdentifier == null || ownerIdentifier.trim().isEmpty) return;
      if (_isSeedUserIdentifier(ownerIdentifier)) return;
      await _cloud.syncOwnedSessions(
        ownerIdentifier: ownerIdentifier,
        sessionsById: _state.exportOwnedSessionMapsById(),
      );
    });
  }

  Future<void> _attachCloudIdentityIfNeeded() async {
    final identifier = _state.activeUserIdentifier?.trim();
    if (identifier == null ||
        identifier.isEmpty ||
        _isSeedUserIdentifier(identifier) ||
        !_isValidUserIdentifierFormat(identifier)) {
      _lastCloudIdentifier = null;
      await _cloud.detachIdentity();
      return;
    }
    if (_lastCloudIdentifier == identifier && _cloud.canSync) return;

    await _cloud.attachIdentity(
      identifier: identifier,
      onRemoteSession: (sessionMap, ownerId, updatedAtMs) {
        _state.upsertSessionFromCloud(
          sessionMap: sessionMap,
          ownerIdentifier: ownerId,
          updatedAtMs: updatedAtMs,
        );
      },
    );
    _lastCloudIdentifier = identifier;
  }

  void _scheduleAutoICloudBackup() {
    _iCloudBackupDebounceTimer?.cancel();
    _iCloudBackupDebounceTimer = Timer(
      const Duration(seconds: 20),
      () => unawaited(_runICloudBackupNow()),
    );
  }

  Future<void> _runICloudBackupNow() async {
    if (!_canAutoBackupToICloud || !_autoICloudBackupArmed) return;

    final now = DateTime.now();
    if (_lastICloudBackupAt != null &&
        now.difference(_lastICloudBackupAt!) < const Duration(seconds: 45)) {
      return;
    }

    if (_iCloudBackupInFlight) {
      _iCloudBackupQueuedDuringInFlight = true;
      return;
    }

    _iCloudBackupInFlight = true;
    try {
      final payload = _state.exportBackupJson();
      final message = await _iCloudChannel
          .invokeMethod<String>('backupToiCloud', {
            'backupData': payload,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
      if (message != null && message.toLowerCase().contains('failed')) {
        throw StateError(message);
      }
      _lastICloudBackupAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastICloudBackupAtPrefsKey,
        _lastICloudBackupAt!.toUtc().toIso8601String(),
      );
    } catch (e, st) {
      debugPrint('Auto iCloud backup failed: $e\n$st');
    } finally {
      _iCloudBackupInFlight = false;
      if (_iCloudBackupQueuedDuringInFlight) {
        _iCloudBackupQueuedDuringInFlight = false;
        _scheduleAutoICloudBackup();
      }
    }
  }

  Future<DateTime?> _readLastICloudBackupAt() async {
    if (!_canAutoBackupToICloud) return null;
    if (_lastICloudBackupAt != null) return _lastICloudBackupAt;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastICloudBackupAtPrefsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  Future<void> _backupToICloudNowFromSettings() async {
    if (!_canAutoBackupToICloud) {
      throw StateError('Cloud backup is currently available on iOS only.');
    }
    final payload = _state.exportBackupJson();
    final message = await _iCloudChannel.invokeMethod<String>(
      'backupToiCloud',
      {
        'backupData': payload,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (message != null && message.toLowerCase().contains('failed')) {
      throw StateError(message);
    }
    _lastICloudBackupAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastICloudBackupAtPrefsKey,
      _lastICloudBackupAt!.toUtc().toIso8601String(),
    );
  }

  Future<DateTime?> _readLastICloudRestoreAt() async {
    if (!_canAutoBackupToICloud) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastICloudRestoreAtPrefsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  Future<bool> _restoreFromICloudFromSettings() async {
    if (!_canAutoBackupToICloud) {
      throw StateError('Cloud restore is currently available on iOS only.');
    }
    String? jsonText;
    for (var attempt = 0; attempt < 3; attempt++) {
      jsonText = await _iCloudChannel.invokeMethod<String>('restoreFromiCloud');
      if (jsonText != null && jsonText.trim().isNotEmpty) {
        break;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: attempt == 0 ? 1 : 2));
      }
    }
    if (jsonText == null || jsonText.trim().isEmpty) {
      return false;
    }
    _state.importBackupJson(jsonText, replaceExisting: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoICloudRestoreSuccessPrefsKey, true);
    await prefs.setString(
      _lastICloudRestoreAtPrefsKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(SubscriptionService().refreshOnResume());
      unawaited(_attemptAutoICloudRestoreIfEligible());
      unawaited(_consumePendingIncomingShareFromPlatform());
      unawaited(_refreshNearbyPresence(force: true));
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stopNearbyPresence());
    }
    if (!_canAutoBackupToICloud) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _iCloudBackupDebounceTimer?.cancel();
      unawaited(_runICloudBackupNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.removeListener(_onStateChanged);
    _iCloudBackupDebounceTimer?.cancel();
    _cloudSyncDebounce?.cancel();
    unawaited(_stopNearbyPresence());
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomeShell(
      state: _state,
      cloud: _cloud,
      startGuidedTour: _startGuidedTourOnHome,
      promptUniqueIdentifierOnLaunch: _promptUniqueIdentifierOnHome,
      cloudRecoverySupported: _canAutoBackupToICloud,
      readLastCloudBackupAt: _readLastICloudBackupAt,
      readLastCloudRestoreAt: _readLastICloudRestoreAt,
      backupNow: _backupToICloudNowFromSettings,
      restoreFromCloud: _restoreFromICloudFromSettings,
    );
  }
}

// ── Subscription gate helper ───────────────────────────────────────────────
/// Returns true if the action should proceed.
/// If not entitled, shows the paywall and returns false.
Future<bool> _guardWrite(BuildContext context) async {
  if (SubscriptionService().isEntitled) return true;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const _PaywallScreen()));
  return false;
}

// ── Paywall screen ─────────────────────────────────────────────────────────
class _PaywallScreen extends StatefulWidget {
  const _PaywallScreen();
  @override
  State<_PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<_PaywallScreen> {
  final SubscriptionService _sub = SubscriptionService();
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () {
      if (!mounted) return;
      setState(() {});
      // Auto-dismiss when entitlement is granted.
      if (_sub.isEntitled && mounted) Navigator.of(context).pop();
    };
    _sub.addListener(_listener);
  }

  @override
  void dispose() {
    _sub.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = _sub.product;
    final priceText = product?.price ?? '—';
    final trialDays = _sub.trialDaysRemaining;
    final inTrial = trialDays > 0;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      appBar: AppBar(title: const Text('Cold Bore Pro')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              if (inTrial) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_bottom_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$trialDays ${trialDays == 1 ? 'day' : 'days'} left in your free trial',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (!inTrial) const Icon(Icons.lock_open_outlined, size: 56),
              if (!inTrial) const SizedBox(height: 16),
              Text(
                inTrial
                    ? 'Unlock Cold Bore Pro'
                    : 'Subscribe to keep adding data',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                inTrial
                    ? 'Subscribe now to keep all features after your trial ends. '
                          'Your data is always yours to view and export.'
                    : 'Your existing data is always available to view and export. '
                          'A Cold Bore Pro subscription lets you continue logging sessions, '
                          'shots, gear, and maintenance records.',
                textAlign: TextAlign.center,
              ),
              if (!inTrial && isIos) ...[
                const SizedBox(height: 8),
                Text(
                  'On iPhone/iPad, free-trial eligibility is checked by the App Store using your Apple ID when you tap Subscribe.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              _FeatureRow(
                icon: Icons.event_note_outlined,
                label: 'Add new shooting sessions',
              ),
              _FeatureRow(
                icon: Icons.ac_unit_outlined,
                label: 'Log cold bore shots and strings',
              ),
              _FeatureRow(
                icon: Icons.build_outlined,
                label: 'Track gear and maintenance',
              ),
              _FeatureRow(
                icon: Icons.timer_outlined,
                label: 'Record timer runs',
              ),
              _FeatureRow(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Export PDF reports (always free)',
              ),
              const Spacer(),
              if (_sub.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _sub.lastError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton(
                onPressed: _sub.loading ? null : () => _sub.purchase(),
                child: _sub.loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Subscribe — $priceText / year'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _sub.loading ? null : () => _sub.restorePurchases(),
                child: const Text('Restore purchases'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now — view my data'),
              ),
              const SizedBox(height: 8),
              Text(
                'Subscription auto-renews yearly. Cancel anytime in Settings.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureRow({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  static const String sharedFieldNotes = 'notes';
  static const String sharedFieldTrainingDope = 'trainingDope';
  static const String sharedFieldLocation = 'location';
  static const String sharedFieldPhotos = 'photos';
  static const String sharedFieldShotResults = 'shotResults';
  static const String sharedFieldTimerData = 'timerData';
  static const List<String> _sharedFieldKeys = <String>[
    sharedFieldNotes,
    sharedFieldTrainingDope,
    sharedFieldLocation,
    sharedFieldPhotos,
    sharedFieldShotResults,
    sharedFieldTimerData,
  ];

  final List<UserProfile> _users = [];
  final List<Rifle> _rifles = [];
  final List<AmmoLot> _ammoLots = [];
  final List<TrainingSession> _sessions = [];
  final Map<String, Map<DistanceKey, DopeEntry>> _workingDopeRifleOnly = {};
  final Map<String, Map<DistanceKey, DopeEntry>> _workingDopeRifleAmmo = {};
  final Map<String, Map<String, bool>> _acceptedSharedFieldsBySession = {};
  final List<String> _pendingSharedAcceptancePromptSessionIds = <String>[];
  final List<String> _pendingIncomingSharedJsonTexts = <String>[];
  final List<String> _trustedPartnerIdentifiers = <String>[];
  List<NearbyPeer> _nearbyPeers = const <NearbyPeer>[];
  String _nearbyStatusMessage =
      'Nearby discovery is idle until a unique identifier is set.';
  final Map<String, int> _cloudSessionUpdatedAtMs = {};
  Timer? _persistTimer;
  bool _didHydrate = false;
  bool _isRestoring = false;
  int _durableRevision = 0;

  UserProfile? _activeUser;

  double _shotTimerBeepFrequencyHz = 1750.0;
  double _shotTimerBeepVolume = 1.0;
  bool _shotTimerApplyAudioShotCountToRifle = false;
  String? _shotTimerSelectedRifleId;
  double _audioThresholdDb = 92.0;

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

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    _durableRevision++;
    super.notifyListeners();
    if (_didHydrate && !_isRestoring) {
      _schedulePersist();
    }
  }

  int get durableRevision => _durableRevision;

  void notifyEphemeralListeners() {
    super.notifyListeners();
  }

  Future<void> loadPersistedState() async {
    if (_didHydrate) return;

    _isRestoring = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kLocalStatePrefsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _restoreFromMap(Map<String, dynamic>.from(decoded));
        }
      }
      if (_users.isEmpty) {
        _seedData();
      }
      _didHydrate = true;
    } catch (e, st) {
      debugPrint('loadPersistedState failed: $e\n$st');
      if (_users.isEmpty) {
        _seedData();
      }
      _didHydrate = true;
    } finally {
      _isRestoring = false;
    }

    super.notifyListeners();
    _schedulePersist();
  }

  Future<void> saveNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kLocalStatePrefsKey,
      const JsonEncoder().convert(_toMap()),
    );
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        await saveNow();
      } catch (e, st) {
        debugPrint('saveNow failed during scheduled persist: $e\n$st');
      }
    });
  }

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

  /// Convenience lookups used by exports/session reports.
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

  double get shotTimerBeepFrequencyHz => _shotTimerBeepFrequencyHz;
  double get shotTimerBeepVolume => _shotTimerBeepVolume;
  bool get shotTimerApplyAudioShotCountToRifle =>
      _shotTimerApplyAudioShotCountToRifle;
  String? get shotTimerSelectedRifleId => _shotTimerSelectedRifleId;
  double get audioThresholdDb => _audioThresholdDb;

  Map<String, Map<DistanceKey, DopeEntry>> get workingDopeRifleOnly =>
      _workingDopeRifleOnly;
  Map<String, Map<DistanceKey, DopeEntry>> get workingDopeRifleAmmo =>
      _workingDopeRifleAmmo;
  List<String> get trustedPartnerIdentifiers =>
      List.unmodifiable(_trustedPartnerIdentifiers);
  List<NearbyPeer> get nearbyPeers => List.unmodifiable(_nearbyPeers);
  String get nearbyStatusMessage => _nearbyStatusMessage;

  void setShotTimerBeepFrequencyHz(double value) {
    _shotTimerBeepFrequencyHz = value.clamp(400.0, 3000.0);
    notifyListeners();
  }

  void setShotTimerBeepVolume(double value) {
    _shotTimerBeepVolume = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setShotTimerApplyAudioShotCountToRifle(bool value) {
    _shotTimerApplyAudioShotCountToRifle = value;
    notifyListeners();
  }

  void setShotTimerSelectedRifleId(String? rifleId) {
    _shotTimerSelectedRifleId = rifleId;
    notifyListeners();
  }

  void setAudioThresholdDb(double value) {
    _audioThresholdDb = value.clamp(70.0, 120.0);
    notifyListeners();
  }

  List<TrainingSession> get allSessions => List.unmodifiable(_sessions);

  void ensureSeedData() {
    if (_users.isNotEmpty) return;
    _seedData();
    notifyListeners();
  }

  void _seedData() {
    final u = UserProfile(id: _newId(), name: 'Owner', identifier: 'OWNER');
    _users.add(u);
    _activeUser = u;
  }

  Map<String, dynamic> _toMap() {
    return <String, dynamic>{
      'activeUserId': _activeUser?.id,
      'environment': <String, dynamic>{
        'latitude': _latitude,
        'longitude': _longitude,
        'temperatureF': _temperatureF,
        'windSpeedMph': _windSpeedMph,
        'windDirectionDeg': _windDirectionDeg,
      },
      'shotTimerSettings': <String, dynamic>{
        'beepFrequencyHz': _shotTimerBeepFrequencyHz,
        'beepVolume': _shotTimerBeepVolume,
        'applyAudioShotCountToRifle': _shotTimerApplyAudioShotCountToRifle,
        'selectedRifleId': _shotTimerSelectedRifleId,
        'audioThresholdDb': _audioThresholdDb,
      },
      'users': _users.map(_userToMap).toList(),
      'rifles': _rifles.map(_rifleToMap).toList(),
      'ammoLots': _ammoLots.map(_ammoLotToMap).toList(),
      'sessions': _sessions.map(_trainingSessionToMap).toList(),
      'workingDopeRifleOnly': _workingDopeRifleOnly.map(
        (key, value) =>
            MapEntry(key, value.values.map(_dopeEntryToMap).toList()),
      ),
      'workingDopeRifleAmmo': _workingDopeRifleAmmo.map(
        (key, value) =>
            MapEntry(key, value.values.map(_dopeEntryToMap).toList()),
      ),
      'trustedPartnerIdentifiers': _trustedPartnerIdentifiers,
      'acceptedSharedFieldsBySession': _acceptedSharedFieldsBySession.map(
        (sessionId, acceptedFields) =>
            MapEntry(sessionId, Map<String, dynamic>.from(acceptedFields)),
      ),
    };
  }

  void _restoreFromMap(Map<String, dynamic> map) {
    _users
      ..clear()
      ..addAll(
        ((map['users'] as List?) ?? const []).map(
          (x) => _userFromMap(Map<String, dynamic>.from(x as Map)),
        ),
      );
    _rifles
      ..clear()
      ..addAll(
        ((map['rifles'] as List?) ?? const []).map(
          (x) => _rifleFromMap(Map<String, dynamic>.from(x as Map)),
        ),
      );
    _ammoLots
      ..clear()
      ..addAll(
        ((map['ammoLots'] as List?) ?? const []).map(
          (x) => _ammoLotFromMap(Map<String, dynamic>.from(x as Map)),
        ),
      );
    _sessions
      ..clear()
      ..addAll(
        ((map['sessions'] as List?) ?? const []).map(
          (x) => _trainingSessionFromMap(Map<String, dynamic>.from(x as Map)),
        ),
      );

    _workingDopeRifleOnly
      ..clear()
      ..addAll(_decodeWorkingDopeMap(map['workingDopeRifleOnly']));
    _workingDopeRifleAmmo
      ..clear()
      ..addAll(_decodeWorkingDopeMap(map['workingDopeRifleAmmo']));
    _acceptedSharedFieldsBySession
      ..clear()
      ..addAll(
        _decodeAcceptedSharedFieldsBySession(
          map['acceptedSharedFieldsBySession'],
        ),
      );
    _trustedPartnerIdentifiers
      ..clear()
      ..addAll(
        ((map['trustedPartnerIdentifiers'] as List?) ?? const <Object>[])
            .map((e) => e.toString().trim().toUpperCase())
            .where((e) => e.isNotEmpty),
      );

    final env = map['environment'];
    if (env is Map) {
      final envMap = Map<String, dynamic>.from(env);
      _latitude = _toNullableDouble(envMap['latitude']);
      _longitude = _toNullableDouble(envMap['longitude']);
      _temperatureF = _toNullableDouble(envMap['temperatureF']);
      _windSpeedMph = _toNullableDouble(envMap['windSpeedMph']);
      _windDirectionDeg = _toNullableInt(envMap['windDirectionDeg']);
    }

    final shotTimerSettings = map['shotTimerSettings'];
    if (shotTimerSettings is Map) {
      final stMap = Map<String, dynamic>.from(shotTimerSettings);
      _shotTimerBeepFrequencyHz =
          _toNullableDouble(stMap['beepFrequencyHz']) ??
          _shotTimerBeepFrequencyHz;
      _shotTimerBeepVolume =
          _toNullableDouble(stMap['beepVolume']) ?? _shotTimerBeepVolume;
      _shotTimerApplyAudioShotCountToRifle =
          stMap['applyAudioShotCountToRifle'] == true;
      _shotTimerSelectedRifleId = stMap['selectedRifleId']?.toString();
      _audioThresholdDb =
          _toNullableDouble(stMap['audioThresholdDb']) ?? _audioThresholdDb;
    }

    if (_users.isEmpty) {
      final fallbackUserId = _sessions
          .map((s) => s.userId.trim())
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
      _users.add(
        UserProfile(
          id: fallbackUserId.isNotEmpty ? fallbackUserId : _newId(),
          name: 'Imported User',
          identifier: 'IMPORTED',
        ),
      );
    }

    final activeUserId = map['activeUserId']?.toString();
    UserProfile? active;
    for (final user in _users) {
      if (user.id == activeUserId) {
        active = user;
        break;
      }
    }
    _activeUser = active ?? (_users.isNotEmpty ? _users.first : null);

    // Legacy backups may miss memberUserIds, which hides sessions in current views.
    // Ensure each restored session is visible to at least one valid user.
    final validUserIds = _users.map((u) => u.id).toSet();
    final fallbackMember = _activeUser?.id;
    if (fallbackMember != null) {
      for (var i = 0; i < _sessions.length; i++) {
        final session = _sessions[i];
        var members = session.memberUserIds
            .where((id) => validUserIds.contains(id))
            .toList();
        if (members.isEmpty) {
          final ownerId = session.userId.trim();
          if (ownerId.isNotEmpty && validUserIds.contains(ownerId)) {
            members = [ownerId];
          } else {
            members = [fallbackMember];
          }
        }
        final unchanged =
            members.length == session.memberUserIds.length &&
            members.asMap().entries.every(
              (entry) => session.memberUserIds[entry.key] == entry.value,
            );
        if (!unchanged) {
          _sessions[i] = session.copyWith(memberUserIds: members);
        }
      }
    }

    final validSessionIds = _sessions.map((s) => s.id).toSet();
    _acceptedSharedFieldsBySession.removeWhere(
      (sessionId, _) => !validSessionIds.contains(sessionId),
    );
  }

  Map<String, Map<DistanceKey, DopeEntry>> _decodeWorkingDopeMap(dynamic raw) {
    if (raw is! Map) return <String, Map<DistanceKey, DopeEntry>>{};
    final out = <String, Map<DistanceKey, DopeEntry>>{};
    for (final entry in raw.entries) {
      final items = (entry.value as List?) ?? const [];
      final inner = <DistanceKey, DopeEntry>{};
      for (final item in items) {
        final dope = _dopeEntryFromMap(Map<String, dynamic>.from(item as Map));
        inner[DistanceKey(dope.distance, dope.distanceUnit)] = dope;
      }
      out[entry.key.toString()] = inner;
    }
    return out;
  }

  Map<String, Map<String, bool>> _decodeAcceptedSharedFieldsBySession(
    dynamic raw,
  ) {
    if (raw is! Map) return <String, Map<String, bool>>{};
    final out = <String, Map<String, bool>>{};
    for (final entry in raw.entries) {
      final sessionId = entry.key.toString();
      final fieldsRaw = entry.value;
      if (fieldsRaw is! Map) continue;
      final accepted = <String, bool>{};
      for (final fieldKey in _sharedFieldKeys) {
        accepted[fieldKey] = fieldsRaw[fieldKey] != false;
      }
      out[sessionId] = accepted;
    }
    return out;
  }

  void addUser({required String name, required String identifier}) {
    final normalizedIdentifier = _normalizeUserIdentifier(identifier);
    final u = UserProfile(
      id: _newId(),
      name: name.trim(),
      identifier: normalizedIdentifier,
    );
    _users.add(u);
    _activeUser ??= u;
    notifyListeners();
  }

  void updateUserProfile({
    required String userId,
    required String name,
    required String identifier,
  }) {
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx < 0) return;

    final normalizedIdentifier = _normalizeUserIdentifier(identifier);

    final updated = UserProfile(
      id: _users[idx].id,
      name: name.trim().isEmpty ? null : name.trim(),
      identifier: normalizedIdentifier,
    );
    _users[idx] = updated;
    if (_activeUser?.id == userId) {
      _activeUser = updated;
    }
    notifyListeners();
  }

  void switchUser(UserProfile user) {
    _activeUser = user;
    notifyListeners();
  }

  bool deleteUser({required String userId}) {
    if (_users.length <= 1) return false;
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx < 0) return false;

    final replacement = _users.firstWhere(
      (u) => u.id != userId,
      orElse: () => _users[idx],
    );
    if (replacement.id == userId) return false;

    for (var i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      final nextOwnerId = s.userId == userId ? replacement.id : s.userId;
      final nextMembers = s.memberUserIds.where((id) => id != userId).toList();
      if (nextMembers.isEmpty) {
        nextMembers.add(nextOwnerId);
      } else if (!nextMembers.contains(nextOwnerId)) {
        nextMembers.add(nextOwnerId);
      }

      final membersUnchanged =
          nextMembers.length == s.memberUserIds.length &&
          nextMembers.asMap().entries.every(
            (entry) => s.memberUserIds[entry.key] == entry.value,
          );

      if (nextOwnerId != s.userId || !membersUnchanged) {
        _sessions[i] = s.copyWith(
          userId: nextOwnerId,
          memberUserIds: nextMembers,
        );
      }
    }

    _users.removeAt(idx);
    if (_activeUser?.id == userId) {
      _activeUser = replacement;
    }
    notifyListeners();
    return true;
  }

  void addRifle({
    ScopeUnit? scopeUnit,
    int manualRoundCount = 0,
    int? barrelRoundCount,
    DateTime? barrelInstalledDate,
    String barrelNotes = '',
    List<MaintenanceReminderRule>? maintenanceRules,
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
      Rifle(
        id: _newId(),
        scopeUnit: scopeUnit ?? ScopeUnit.mil,
        manualRoundCount: manualRoundCount,
        barrelRoundCount: barrelRoundCount ?? manualRoundCount,
        barrelInstalledDate: barrelInstalledDate,
        barrelNotes: barrelNotes.trim(),
        maintenanceRules: maintenanceRules ?? _defaultMaintenanceRules(),
        scopeMake: scopeMake?.trim().isEmpty == true ? null : scopeMake?.trim(),
        scopeModel: scopeModel?.trim().isEmpty == true
            ? null
            : scopeModel?.trim(),
        scopeSerial: scopeSerial?.trim().isEmpty == true
            ? null
            : scopeSerial?.trim(),
        scopeMount: scopeMount?.trim().isEmpty == true
            ? null
            : scopeMount?.trim(),
        scopeNotes: scopeNotes?.trim().isEmpty == true
            ? null
            : scopeNotes?.trim(),
        name: name.trim().isEmpty ? null : name.trim(),
        caliber: caliber.trim(),
        notes: notes.trim(),
        dope: dope.trim(),
        manufacturer: manufacturer?.trim().isEmpty == true
            ? null
            : manufacturer?.trim(),
        model: model?.trim().isEmpty == true ? null : model?.trim(),
        serialNumber: serialNumber?.trim().isEmpty == true
            ? null
            : serialNumber?.trim(),
        barrelLength: barrelLength?.trim().isEmpty == true
            ? null
            : barrelLength?.trim(),
        twistRate: twistRate?.trim().isEmpty == true ? null : twistRate?.trim(),
        purchaseDate: purchaseDate,
        purchasePrice: purchasePrice?.trim().isEmpty == true
            ? null
            : purchasePrice?.trim(),
        purchaseLocation: purchaseLocation?.trim().isEmpty == true
            ? null
            : purchaseLocation?.trim(),
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
    int? manualRoundCount,
    int? barrelRoundCount,
    DateTime? barrelInstalledDate,
    String? barrelNotes,
    List<MaintenanceReminderRule>? maintenanceRules,
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
      manualRoundCount: manualRoundCount ?? r.manualRoundCount,
      barrelRoundCount: barrelRoundCount ?? r.barrelRoundCount,
      barrelInstalledDate: barrelInstalledDate ?? r.barrelInstalledDate,
      barrelNotes: barrelNotes ?? r.barrelNotes,
      maintenanceRules: maintenanceRules ?? r.maintenanceRules,
      preferredUnit: preferredUnit ?? r.preferredUnit,
      manufacturer: manufacturer?.trim().isEmpty == true
          ? null
          : manufacturer?.trim(),
      model: model?.trim().isEmpty == true ? null : model?.trim(),
      serialNumber: serialNumber?.trim().isEmpty == true
          ? null
          : serialNumber?.trim(),
      barrelLength: barrelLength?.trim().isEmpty == true
          ? null
          : barrelLength?.trim(),
      twistRate: twistRate?.trim().isEmpty == true ? null : twistRate?.trim(),
      purchaseDate: purchaseDate,
      purchasePrice: purchasePrice?.trim().isEmpty == true
          ? null
          : purchasePrice?.trim(),
      purchaseLocation: purchaseLocation?.trim().isEmpty == true
          ? null
          : purchaseLocation?.trim(),
      scopeUnit: scopeUnit ?? r.scopeUnit,
      scopeMake: scopeMake?.trim().isEmpty == true ? null : scopeMake?.trim(),
      scopeModel: scopeModel?.trim().isEmpty == true
          ? null
          : scopeModel?.trim(),
      scopeSerial: scopeSerial?.trim().isEmpty == true
          ? null
          : scopeSerial?.trim(),
      scopeMount: scopeMount?.trim().isEmpty == true
          ? null
          : scopeMount?.trim(),
      scopeNotes: scopeNotes?.trim().isEmpty == true
          ? null
          : scopeNotes?.trim(),
    );
    notifyListeners();
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
        manufacturer: manufacturer?.trim().isEmpty == true
            ? null
            : manufacturer?.trim(),
        lotNumber: lotNumber?.trim().isEmpty == true ? null : lotNumber?.trim(),
        purchaseDate: purchaseDate,
        purchasePrice: purchasePrice?.trim().isEmpty == true
            ? null
            : purchasePrice?.trim(),
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
      manufacturer: manufacturer?.trim().isEmpty == true
          ? null
          : manufacturer?.trim(),
      lotNumber: lotNumber?.trim().isEmpty == true ? null : lotNumber?.trim(),
      purchaseDate: purchaseDate,
      purchasePrice: purchasePrice?.trim().isEmpty == true
          ? null
          : purchasePrice?.trim(),
      ballisticCoefficient: ballisticCoefficient,
    );
    notifyListeners();
  }

  TrainingSession? addSession({
    required String locationName,
    required DateTime dateTime,
    String folderName = '',
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
      folderName: folderName.trim(),
      archived: false,
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

  String? get activeUserIdentifier => _activeUser?.identifier;

  Map<String, bool> sharedFieldAcceptanceForSession(String sessionId) {
    final accepted = _acceptedSharedFieldsBySession[sessionId];
    return <String, bool>{
      for (final fieldKey in _sharedFieldKeys)
        fieldKey: accepted == null ? true : accepted[fieldKey] != false,
    };
  }

  String? takeNextPendingSharedAcceptancePromptSessionId() {
    if (_pendingSharedAcceptancePromptSessionIds.isEmpty) return null;
    return _pendingSharedAcceptancePromptSessionIds.removeAt(0);
  }

  void enqueueIncomingSharedJson(String jsonText) {
    final trimmed = jsonText.trim();
    if (trimmed.isEmpty) return;
    _pendingIncomingSharedJsonTexts.add(trimmed);
    notifyEphemeralListeners();
  }

  void setNearbyPeers(List<NearbyPeer> peers) {
    final normalized =
        peers
            .where((peer) => peer.identifier.trim().isNotEmpty)
            .map(
              (peer) => NearbyPeer(
                identifier: peer.identifier.trim().toUpperCase(),
                displayName: peer.displayName.trim().isEmpty
                    ? peer.identifier.trim().toUpperCase()
                    : peer.displayName.trim(),
              ),
            )
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

    final isSameLength = normalized.length == _nearbyPeers.length;
    final unchanged =
        isSameLength &&
        normalized.asMap().entries.every((entry) {
          final current = _nearbyPeers[entry.key];
          return current.identifier == entry.value.identifier &&
              current.displayName == entry.value.displayName;
        });
    if (unchanged) return;

    _nearbyPeers = normalized;
    notifyEphemeralListeners();
  }

  void setNearbyStatusMessage(String message) {
    final trimmed = message.trim();
    final next = trimmed.isEmpty
        ? 'Nearby discovery is idle until a unique identifier is set.'
        : trimmed;
    if (_nearbyStatusMessage == next) return;
    _nearbyStatusMessage = next;
    notifyEphemeralListeners();
  }

  void rememberTrustedPartnerIdentifier(String? identifier) {
    final normalized = identifier?.trim().toUpperCase() ?? '';
    if (normalized.isEmpty) return;
    if (activeUserIdentifier?.trim().toUpperCase() == normalized) return;
    if (_trustedPartnerIdentifiers.contains(normalized)) return;
    _trustedPartnerIdentifiers.add(normalized);
    _trustedPartnerIdentifiers.sort();
    notifyListeners();
  }

  String? takeNextPendingIncomingSharedJson() {
    if (_pendingIncomingSharedJsonTexts.isEmpty) return null;
    return _pendingIncomingSharedJsonTexts.removeAt(0);
  }

  void _enqueueSharedAcceptancePrompt(String sessionId) {
    if (_acceptedSharedFieldsBySession.containsKey(sessionId)) return;
    if (_pendingSharedAcceptancePromptSessionIds.contains(sessionId)) return;
    _pendingSharedAcceptancePromptSessionIds.add(sessionId);
  }

  void setSessionAcceptedSharedFields({
    required String sessionId,
    required bool acceptNotes,
    required bool acceptTrainingDope,
    required bool acceptLocation,
    required bool acceptPhotos,
    required bool acceptShotResults,
    required bool acceptTimerData,
  }) {
    _acceptedSharedFieldsBySession[sessionId] = <String, bool>{
      sharedFieldNotes: acceptNotes,
      sharedFieldTrainingDope: acceptTrainingDope,
      sharedFieldLocation: acceptLocation,
      sharedFieldPhotos: acceptPhotos,
      sharedFieldShotResults: acceptShotResults,
      sharedFieldTimerData: acceptTimerData,
    };
    notifyListeners();
  }

  UserProfile _ensureUserByIdentifier(String identifier) {
    final normalized = identifier.trim().toUpperCase();
    for (final u in _users) {
      if (u.identifier.trim().toUpperCase() == normalized) {
        return u;
      }
    }
    final created = UserProfile(
      id: _newId(),
      name: null,
      identifier: normalized,
    );
    _users.add(created);
    return created;
  }

  Map<String, dynamic>? exportSessionMapById(String sessionId) {
    final s = getSessionById(sessionId);
    if (s == null) return null;
    return _trainingSessionToMap(s);
  }

  String exportSharedSessionJson({
    required String sessionId,
    String? ownerIdentifier,
  }) {
    final session = getSessionById(sessionId);
    if (session == null) {
      throw StateError('Session not found.');
    }

    final rifle = session.rifleId == null
        ? null
        : findRifleById(session.rifleId!);
    final ammo = session.ammoLotId == null
        ? null
        : findAmmoLotById(session.ammoLotId!);

    final payload = <String, dynamic>{
      'schema': kBackupSchemaVersion,
      'exportType': 'sharedSession',
      'generatedAt': DateTime.now().toIso8601String(),
      'ownerIdentifier': ownerIdentifier?.trim(),
      'session': _trainingSessionToMap(session),
      'rifles': [if (rifle != null) _rifleToMap(rifle)],
      'ammoLots': [if (ammo != null) _ammoLotToMap(ammo)],
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, Map<String, dynamic>> exportOwnedSessionMapsById() {
    final active = _activeUser;
    if (active == null) return const <String, Map<String, dynamic>>{};
    final out = <String, Map<String, dynamic>>{};
    for (final s in _sessions) {
      if (s.userId != active.id) continue;
      out[s.id] = _trainingSessionToMap(s);
    }
    return out;
  }

  void upsertSessionFromCloud({
    required Map<String, dynamic> sessionMap,
    required String ownerIdentifier,
    required int updatedAtMs,
  }) {
    final incoming = _trainingSessionFromMap(sessionMap);
    final owner = _ensureUserByIdentifier(ownerIdentifier);
    final viewer = _activeUser ?? owner;

    final normalized = incoming.copyWith(
      userId: owner.id,
      memberUserIds: <String>{viewer.id, owner.id}.toList(),
    );
    final shouldPromptRecipientAcceptance = viewer.id != owner.id;

    final idx = _sessions.indexWhere((s) => s.id == normalized.id);
    final knownMs = _cloudSessionUpdatedAtMs[normalized.id] ?? 0;
    if (updatedAtMs <= knownMs) {
      return;
    }

    if (idx < 0) {
      _sessions.add(normalized);
      if (shouldPromptRecipientAcceptance) {
        _enqueueSharedAcceptancePrompt(normalized.id);
      }
      _cloudSessionUpdatedAtMs[normalized.id] = updatedAtMs;
      notifyListeners();
      return;
    }

    final existingMap = _trainingSessionToMap(_sessions[idx]);
    final incomingMap = _trainingSessionToMap(normalized);
    if (jsonEncode(existingMap) == jsonEncode(incomingMap)) {
      _cloudSessionUpdatedAtMs[normalized.id] = updatedAtMs;
      return;
    }

    _sessions[idx] = normalized;
    if (shouldPromptRecipientAcceptance) {
      _enqueueSharedAcceptancePrompt(normalized.id);
    }
    _cloudSessionUpdatedAtMs[normalized.id] = updatedAtMs;
    notifyListeners();
  }

  void shareSessionWithUsers({
    required String sessionId,
    required List<String> userIds,
    List<String>? externalIdentifiers,
    bool? shareNotesWithMembers,
    bool? shareTrainingDopeWithMembers,
    bool? shareLocationWithMembers,
    bool? sharePhotosWithMembers,
    bool? shareShotResultsWithMembers,
    bool? shareTimerDataWithMembers,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;

    final existing = _sessions[idx];
    final merged = <String>{...existing.memberUserIds, ...userIds}.toList();

    _sessions[idx] = existing.copyWith(
      memberUserIds: merged,
      externalMemberIdentifiers:
          externalIdentifiers ?? existing.externalMemberIdentifiers,
      shareNotesWithMembers: shareNotesWithMembers,
      shareTrainingDopeWithMembers: shareTrainingDopeWithMembers,
      shareLocationWithMembers: shareLocationWithMembers,
      sharePhotosWithMembers: sharePhotosWithMembers,
      shareShotResultsWithMembers: shareShotResultsWithMembers,
      shareTimerDataWithMembers: shareTimerDataWithMembers,
    );
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

    final loadoutChanged =
        (nextRifleId != s.rifleId) || (nextAmmoId != s.ammoLotId);
    if (!loadoutChanged) return;

    final now = DateTime.now();
    final currentStrings = [...s.strings];
    final activeIndex = currentStrings.indexWhere(
      (x) => x.id == s.activeStringId,
    );

    SessionStringMeta? activeMeta = activeIndex == -1
        ? null
        : currentStrings[activeIndex];
    final activeHasLoadout =
        (activeMeta?.rifleId != null) && (activeMeta?.ammoLotId != null);
    final activeIsEmpty =
        (activeMeta?.rifleId == null) && (activeMeta?.ammoLotId == null);

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

    // If user is still selecting (missing either rifle or ammo), only keep editing
    // the current session unless they explicitly chose to start a new string.
    if ((nextRifleId == null || nextAmmoId == null) && !startNewString) {
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
      currentStrings[activeIndex] = currentStrings[activeIndex].copyWith(
        endedAt: now,
      );
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
      shotsByString: {...s.shotsByString, newStringId: const <ShotEntry>[]},
    );
    notifyListeners();
  }

  void setActiveString({required String sessionId, required String stringId}) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;
    final s = _sessions[idx];
    final st = s.strings.firstWhere(
      (x) => x.id == stringId,
      orElse: () => s.strings.isNotEmpty
          ? s.strings.last
          : SessionStringMeta(
              id: stringId,
              startedAt: DateTime.now(),
              endedAt: null,
              rifleId: s.rifleId,
              ammoLotId: s.ammoLotId,
            ),
    );
    _sessions[idx] = s.copyWith(
      activeStringId: stringId,
      // Snap loadout display to the string meta (if present)
      rifleId: st.rifleId ?? s.rifleId,
      ammoLotId: st.ammoLotId ?? s.ammoLotId,
    );
    notifyListeners();
  }

  void updateSessionNotes({required String sessionId, required String notes}) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];
    _sessions[idx] = s.copyWith(notes: notes.trim());
    notifyListeners();
  }

  void updateSessionDateTimes({
    required String sessionId,
    required DateTime startedAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;

    if (!clearEndedAt && endedAt != null && endedAt.isBefore(startedAt)) {
      return;
    }

    final s = _sessions[idx];
    _sessions[idx] = s.copyWith(
      dateTime: startedAt,
      endedAt: clearEndedAt ? null : endedAt,
    );
    notifyListeners();
  }

  void updateSessionFolder({
    required String sessionId,
    required String folderName,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];
    _sessions[idx] = s.copyWith(folderName: folderName.trim());
    notifyListeners();
  }

  void setSessionArchived({required String sessionId, required bool archived}) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];
    _sessions[idx] = s.copyWith(archived: archived);
    notifyListeners();
  }

  void deleteSession({required String sessionId}) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    _sessions.removeAt(idx);
    _acceptedSharedFieldsBySession.remove(sessionId);
    _pendingSharedAcceptancePromptSessionIds.removeWhere(
      (id) => id == sessionId,
    );
    notifyListeners();
  }

  void addColdBoreEntry({
    required String sessionId,
    required DateTime time,
    required String distance,
    required String result,
    String notes = '',
    double? offsetX,
    double? offsetY,
    String offsetUnit = 'in',
    Uint8List? photoBytes,
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
      offsetX: offsetX,
      offsetY: offsetY,
      offsetUnit: offsetUnit,
      photos: (photoBytes == null)
          ? const []
          : [
              ColdBorePhoto(
                id: _newId(),
                time: time,
                bytes: photoBytes,
                caption: '',
              ),
            ],
    );

    final sid = (s.activeStringId.isEmpty && s.strings.isNotEmpty)
        ? s.strings.last.id
        : s.activeStringId;
    final currentList = List<ShotEntry>.from(
      s.shotsByString[sid] ?? const <ShotEntry>[],
    );
    final sessionPhoto = (photoBytes == null)
        ? null
        : SessionPhoto(
            id: _newId(),
            time: time,
            bytes: photoBytes,
            caption: 'Cold bore • ${distance.trim()}',
          );

    _sessions[idx] = s.copyWith(
      shots: [...s.shots, entry],
      shotsByString: {
        ...s.shotsByString,
        sid: [...currentList, entry],
      },
      sessionPhotos: sessionPhoto == null
          ? s.sessionPhotos
          : [...s.sessionPhotos, sessionPhoto],
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

    final sid = (s.activeStringId.isEmpty && s.strings.isNotEmpty)
        ? s.strings.last.id
        : s.activeStringId;
    final currentList = List<DopeEntry>.from(
      s.trainingDopeByString[sid] ?? const <DopeEntry>[],
    );
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

  void promoteExistingDope({
    required DopeEntry entry,
    required bool rifleOnly,
  }) {
    final rifleId = entry.rifleId;
    if (rifleId == null) return;

    final String key;
    final Map<String, Map<DistanceKey, DopeEntry>> workingMap;

    if (rifleOnly || entry.ammoLotId == null) {
      key = rifleId;
      workingMap = _workingDopeRifleOnly;
    } else {
      key = '${rifleId}_${entry.ammoLotId}';
      workingMap = _workingDopeRifleAmmo;
    }

    workingMap[key] ??= {};
    final dk = DistanceKey(entry.distance, entry.distanceUnit);
    workingMap[key]![dk] = entry;
    notifyListeners();
  }

  bool deleteTrainingDopeEntry({
    required String sessionId,
    required String dopeEntryId,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return false;
    final s = _sessions[idx];

    final updatedTrainingDope = s.trainingDope
        .where((e) => e.id != dopeEntryId)
        .toList();
    if (updatedTrainingDope.length == s.trainingDope.length) {
      return false;
    }

    final updatedByString = <String, List<DopeEntry>>{
      for (final entry in s.trainingDopeByString.entries)
        entry.key: entry.value.where((e) => e.id != dopeEntryId).toList(),
    };

    _sessions[idx] = s.copyWith(
      trainingDope: updatedTrainingDope,
      trainingDopeByString: updatedByString,
    );
    notifyListeners();
    return true;
  }

  bool deleteWorkingDopeEntry({
    required bool rifleOnly,
    required String bucketKey,
    required DistanceKey distanceKey,
  }) {
    final map = rifleOnly ? _workingDopeRifleOnly : _workingDopeRifleAmmo;
    final bucket = map[bucketKey];
    if (bucket == null) return false;

    final removed = bucket.remove(distanceKey) != null;
    if (!removed) return false;
    if (bucket.isEmpty) {
      map.remove(bucketKey);
    }

    notifyListeners();
    return true;
  }

  bool updateWorkingDopeEntry({
    required bool rifleOnly,
    required String bucketKey,
    required DistanceKey oldDistanceKey,
    required DopeEntry entry,
  }) {
    final map = rifleOnly ? _workingDopeRifleOnly : _workingDopeRifleAmmo;
    final bucket = map[bucketKey];
    if (bucket == null) return false;

    final existing = bucket[oldDistanceKey];
    if (existing == null) return false;

    final updated = DopeEntry(
      id: existing.id,
      time: DateTime.now(),
      rifleId: existing.rifleId,
      ammoLotId: existing.ammoLotId,
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

    bucket.remove(oldDistanceKey);
    final newDistanceKey = DistanceKey(updated.distance, updated.distanceUnit);
    bucket[newDistanceKey] = updated;
    notifyListeners();
    return true;
  }

  bool clearWorkingDopeBucket({
    required bool rifleOnly,
    required String bucketKey,
  }) {
    final map = rifleOnly ? _workingDopeRifleOnly : _workingDopeRifleAmmo;
    if (!map.containsKey(bucketKey)) return false;
    map.remove(bucketKey);
    notifyListeners();
    return true;
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
    final sessionPhoto = SessionPhoto(
      id: _newId(),
      time: photo.time,
      bytes: bytes,
      caption: ((caption ?? '').trim().isEmpty
          ? 'Cold bore photo'
          : (caption ?? '').trim()),
    );

    final updatedShot = shot.copyWith(photos: [...shot.photos, photo]);
    final updatedShots = [...s.shots];
    updatedShots[shotIdx] = updatedShot;
    final updatedShotsByString = <String, List<ShotEntry>>{
      for (final entry in s.shotsByString.entries)
        entry.key: entry.value
            .map((existing) => existing.id == shotId ? updatedShot : existing)
            .toList(),
    };

    _sessions[sIdx] = s.copyWith(
      shots: updatedShots,
      shotsByString: updatedShotsByString,
      sessionPhotos: [...s.sessionPhotos, sessionPhoto],
    );
    notifyListeners();
  }

  /// Sets one cold bore entry as the baseline for the active user for the *current rifle+ammo combo*.
  /// Other combos keep their own baseline.
  void setBaselineColdBore({
    required String sessionId,
    required String shotId,
  }) {
    final user = _activeUser;
    if (user == null) return;

    TrainingSession? targetSession;
    for (final s in _sessions) {
      if (s.id == sessionId && s.userId == user.id) {
        targetSession = s;
        break;
      }
    }
    if (targetSession == null) return;

    final keyRifle = targetSession.rifleId;
    final keyAmmo = targetSession.ammoLotId;

    bool sameCombo(TrainingSession s) {
      // If either id is missing, keep baseline changes within that single session only.
      if (keyRifle == null || keyAmmo == null) return s.id == targetSession!.id;
      return s.rifleId == keyRifle && s.ammoLotId == keyAmmo;
    }

    for (var i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      if (s.userId != user.id) continue;
      if (!sameCombo(s)) continue;

      final updatedShots = <ShotEntry>[];
      for (final sh in s.shots) {
        if (!sh.isColdBore) {
          updatedShots.add(sh);
          continue;
        }
        final shouldBeBaseline = (s.id == sessionId && sh.id == shotId);
        updatedShots.add(sh.copyWith(isBaseline: shouldBeBaseline));
      }

      final updatedShotsByString = <String, List<ShotEntry>>{
        for (final entry in s.shotsByString.entries)
          entry.key: entry.value.map((sh) {
            if (!sh.isColdBore) return sh;
            final shouldBeBaseline = (s.id == sessionId && sh.id == shotId);
            return sh.copyWith(isBaseline: shouldBeBaseline);
          }).toList(),
      };

      _sessions[i] = s.copyWith(
        shots: updatedShots,
        shotsByString: updatedShotsByString,
      );
    }

    notifyListeners();
  }

  /// Returns the current baseline cold bore shot (if any) for the active user, scoped to rifle+ammo when provided.
  ShotEntry? baselineColdBoreShot({String? rifleId, String? ammoLotId}) {
    final user = _activeUser;
    if (user == null) return null;

    final scoped = (rifleId != null && ammoLotId != null);

    for (final s in _sessions.where((x) => x.userId == user.id)) {
      if (scoped) {
        if (s.rifleId != rifleId || s.ammoLotId != ammoLotId) continue;
      }
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

    final p = PhotoNote(id: _newId(), time: time, caption: caption.trim());

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
        String? stringId;
        for (final entry in s.shotsByString.entries) {
          if (entry.value.any((x) => x.id == shot.id)) {
            stringId = entry.key;
            break;
          }
        }

        SessionStringMeta? stringMeta;
        if (stringId != null) {
          for (final meta in s.strings) {
            if (meta.id == stringId) {
              stringMeta = meta;
              break;
            }
          }
        }

        final rifleId = stringMeta?.rifleId ?? s.rifleId;
        final ammoLotId = stringMeta?.ammoLotId ?? s.ammoLotId;
        rows.add(
          _ColdBoreRow(
            session: s,
            shot: shot,
            rifle: rifleById(rifleId),
            ammo: ammoById(ammoLotId),
            stringId: stringId,
          ),
        );
      }
    }

    rows.sort((a, b) => b.shot.time.compareTo(a.shot.time));
    return rows;
  }

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String newChildId() => _newId();

  List<MaintenanceReminderRule> _defaultMaintenanceRules() {
    return MaintenanceTaskType.values
        .where(_isConfigurableMaintenanceTask)
        .map(MaintenanceReminderRule.defaultFor)
        .toList();
  }

  List<MaintenanceReminderRule> _normalizedMaintenanceRules(
    List<MaintenanceReminderRule> rules,
  ) {
    final byType = <MaintenanceTaskType, MaintenanceReminderRule>{
      for (final rule in rules)
        if (_isConfigurableMaintenanceTask(rule.type)) rule.type: rule,
    };
    return MaintenanceTaskType.values
        .where(_isConfigurableMaintenanceTask)
        .map((type) => byType[type] ?? MaintenanceReminderRule.defaultFor(type))
        .toList();
  }

  List<MaintenanceReminderRule> maintenanceRulesForRifle(String rifleId) {
    final rifle = rifleById(rifleId);
    if (rifle == null) return _defaultMaintenanceRules();
    return _normalizedMaintenanceRules(rifle.maintenanceRules);
  }

  void updateRifleMaintenanceRules({
    required String rifleId,
    required List<MaintenanceReminderRule> rules,
  }) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx < 0) return;
    _rifles[idx] = _rifles[idx].copyWith(
      maintenanceRules: _normalizedMaintenanceRules(rules),
    );
    notifyListeners();
  }

  List<RifleServiceEntry> _servicesForMaintenanceType(
    Rifle rifle,
    MaintenanceTaskType type,
  ) {
    final serviceType = type == MaintenanceTaskType.barrelLife
        ? MaintenanceTaskType.barrelChange
        : type;
    final services =
        rifle.services.where((entry) => entry.taskType == serviceType).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return services;
  }

  DateTime? _baselineDateForMaintenanceType(
    Rifle rifle,
    MaintenanceTaskType type,
    RifleServiceEntry? lastService,
  ) {
    if (lastService != null) return lastService.date;
    switch (type) {
      case MaintenanceTaskType.barrelLife:
        return rifle.barrelInstalledDate;
      case MaintenanceTaskType.cleaning:
      case MaintenanceTaskType.deepCleaning:
      case MaintenanceTaskType.torqueCheck:
      case MaintenanceTaskType.zeroConfirm:
        return rifle.barrelInstalledDate ?? rifle.purchaseDate;
      case MaintenanceTaskType.general:
      case MaintenanceTaskType.barrelChange:
        return null;
    }
  }

  int _roundDueSoonBuffer(int intervalRounds) {
    return math.max(25, (intervalRounds * 0.1).round());
  }

  int _dayDueSoonBuffer(int intervalDays) {
    return math.max(3, math.min(7, (intervalDays * 0.2).round()));
  }

  MaintenanceReminderStatus _buildMaintenanceStatus(
    Rifle rifle,
    MaintenanceReminderRule rule,
  ) {
    final services = _servicesForMaintenanceType(rifle, rule.type);
    final lastService = services.isEmpty ? null : services.first;
    final baselineDate = _baselineDateForMaintenanceType(
      rifle,
      rule.type,
      lastService,
    );

    int? roundsSince;
    int? roundsRemaining;
    if (rule.intervalRounds != null) {
      if (rule.type == MaintenanceTaskType.barrelLife) {
        roundsSince = rifle.barrelRoundCount;
      } else {
        roundsSince = math.max(
          0,
          rifle.manualRoundCount - (lastService?.roundsAtService ?? 0),
        );
      }
      roundsRemaining = rule.intervalRounds! - roundsSince;
    }

    int? daysSince;
    int? daysRemaining;
    if (rule.intervalDays != null && baselineDate != null) {
      final baselineOnly = DateTime(
        baselineDate.year,
        baselineDate.month,
        baselineDate.day,
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      daysSince = today.difference(baselineOnly).inDays;
      daysRemaining = rule.intervalDays! - daysSince;
    }

    final overdueRounds =
        rule.intervalRounds != null &&
        roundsRemaining != null &&
        roundsRemaining <= 0;
    final overdueDays =
        rule.intervalDays != null &&
        daysRemaining != null &&
        daysRemaining <= 0;

    final dueSoonRounds =
        !overdueRounds &&
        rule.intervalRounds != null &&
        roundsRemaining != null &&
        roundsRemaining <= _roundDueSoonBuffer(rule.intervalRounds!);
    final dueSoonDays =
        !overdueDays &&
        rule.intervalDays != null &&
        daysRemaining != null &&
        daysRemaining <= _dayDueSoonBuffer(rule.intervalDays!);

    final status = (overdueRounds || overdueDays)
        ? MaintenanceDueStatus.overdue
        : ((dueSoonRounds || dueSoonDays)
              ? MaintenanceDueStatus.dueSoon
              : MaintenanceDueStatus.good);

    return MaintenanceReminderStatus(
      rule: rule,
      status: status,
      roundsSince: roundsSince,
      roundsRemaining: roundsRemaining,
      daysSince: daysSince,
      daysRemaining: daysRemaining,
      lastService: lastService,
    );
  }

  RifleMaintenanceSnapshot maintenanceSnapshotForRifle(String rifleId) {
    final rifle = rifleById(rifleId);
    if (rifle == null) {
      throw StateError('Rifle not found: $rifleId');
    }
    final rules = maintenanceRulesForRifle(
      rifleId,
    ).where((rule) => rule.enabled).toList();
    final statuses = rules
        .map((rule) => _buildMaintenanceStatus(rifle, rule))
        .toList();
    final lastService = [...rifle.services]
      ..sort((a, b) => b.date.compareTo(a.date));
    return RifleMaintenanceSnapshot(
      rifle: rifle,
      totalRounds: rifle.manualRoundCount,
      barrelRounds: rifle.barrelRoundCount,
      statuses: statuses,
      lastService: lastService.isEmpty ? null : lastService.first,
    );
  }

  List<RifleMaintenanceSnapshot> maintenanceSnapshots() {
    return _rifles
        .map((rifle) => maintenanceSnapshotForRifle(rifle.id))
        .toList();
  }

  int totalRoundsForRifle(String rifleId) {
    final r = rifleById(rifleId);
    if (r == null) return 0;
    return r.manualRoundCount;
  }

  int currentBarrelRoundsForRifle(String rifleId) {
    final r = rifleById(rifleId);
    if (r == null) return 0;
    return r.barrelRoundCount;
  }

  void addRifleService({
    required String rifleId,
    required RifleServiceEntry entry,
  }) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx < 0) return;
    final r = _rifles[idx];
    final next = [...r.services, entry]
      ..sort((a, b) => b.date.compareTo(a.date));
    _rifles[idx] = r.copyWith(services: next);
    notifyListeners();
  }

  void logRifleMaintenanceTask({
    required String rifleId,
    required MaintenanceTaskType taskType,
    DateTime? date,
    String notes = '',
    int? roundsAtService,
    String? serviceLabel,
  }) {
    final rifle = rifleById(rifleId);
    if (rifle == null) return;
    addRifleService(
      rifleId: rifleId,
      entry: RifleServiceEntry(
        id: _newId(),
        service: serviceLabel ?? _maintenanceTaskLabel(taskType),
        date: date ?? DateTime.now(),
        roundsAtService: roundsAtService ?? rifle.manualRoundCount,
        notes: notes.trim(),
        taskType: taskType,
      ),
    );
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

  void applySessionShotCountToRifle({
    required String sessionId,
    required int shotCount,
  }) {
    final sessionIdx = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIdx < 0) return;
    final session = _sessions[sessionIdx];
    final rifleId = session.rifleId;
    if (rifleId == null) return;

    final rifleIdx = _rifles.indexWhere((r) => r.id == rifleId);
    if (rifleIdx < 0) return;

    final rifle = _rifles[rifleIdx];
    final nextTotalRoundCount = rifle.manualRoundCount + shotCount;
    final nextBarrelRoundCount = rifle.barrelRoundCount + shotCount;
    _rifles[rifleIdx] = rifle.copyWith(
      manualRoundCount: nextTotalRoundCount,
      barrelRoundCount: nextBarrelRoundCount,
    );
    _sessions[sessionIdx] = session.copyWith(
      confirmedShotCount: shotCount,
      shotCountAppliedToRifle: true,
      endedAt: session.endedAt ?? DateTime.now(),
    );
    notifyListeners();
  }

  void saveSessionShotCount({
    required String sessionId,
    required int shotCount,
    bool appliedToRifle = false,
    bool endSession = false,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final session = _sessions[idx];
    _sessions[idx] = session.copyWith(
      confirmedShotCount: shotCount,
      shotCountAppliedToRifle: appliedToRifle,
      endedAt: endSession
          ? (session.endedAt ?? DateTime.now())
          : session.endedAt,
    );
    notifyListeners();
  }

  void saveSessionTimer({
    required String sessionId,
    int? elapsedMs,
    int? firstShotMs,
    List<int> splitMs = const [],
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final session = _sessions[idx];
    _sessions[idx] = session.copyWith(
      shotTimerElapsedMs: elapsedMs,
      shotTimerFirstShotMs: firstShotMs,
      shotTimerSplitMs: List<int>.from(splitMs),
    );
    notifyListeners();
  }

  void addSessionTimerRun({
    required String sessionId,
    required int elapsedMs,
    int firstShotMs = 0,
    List<int> splitMs = const [],
    int startDelayMs = 0,
    int goalMs = 0,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final session = _sessions[idx];
    final run = SessionTimerRun(
      id: _newId(),
      time: DateTime.now(),
      elapsedMs: elapsedMs,
      firstShotMs: firstShotMs,
      splitMs: List<int>.from(splitMs),
      startDelayMs: startDelayMs,
      goalMs: goalMs,
    );
    _sessions[idx] = session.copyWith(
      shotTimerElapsedMs: elapsedMs,
      shotTimerFirstShotMs: firstShotMs,
      shotTimerSplitMs: List<int>.from(splitMs),
      timerRuns: [...session.timerRuns, run],
    );
    notifyListeners();
  }

  void deleteSessionTimerRun({
    required String sessionId,
    required String runId,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final session = _sessions[idx];
    final updatedRuns = session.timerRuns
        .where((run) => run.id != runId)
        .toList();
    if (updatedRuns.length == session.timerRuns.length) return;
    _sessions[idx] = session.copyWith(timerRuns: updatedRuns);
    notifyListeners();
  }

  void clearSessionTimer({required String sessionId}) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final session = _sessions[idx];
    _sessions[idx] = session.copyWith(
      shotTimerElapsedMs: 0,
      shotTimerFirstShotMs: 0,
      shotTimerSplitMs: const [],
    );
    notifyListeners();
  }

  void endSession({
    required String sessionId,
    int? confirmedShotCount,
    Map<String, int> appliedShotCounts = const {},
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final session = _sessions[idx];
    final now = DateTime.now();
    final updatedStrings = session.strings
        .map(
          (st) => st.id == session.activeStringId && st.endedAt == null
              ? st.copyWith(endedAt: now)
              : st,
        )
        .toList();

    final validAppliedShotCounts = <String, int>{
      for (final entry in appliedShotCounts.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    final shouldApplyShotCount =
        validAppliedShotCounts.isNotEmpty && !session.shotCountAppliedToRifle;

    _sessions[idx] = session.copyWith(
      confirmedShotCount: confirmedShotCount ?? session.confirmedShotCount,
      shotCountAppliedToRifle:
          session.shotCountAppliedToRifle || shouldApplyShotCount,
      endedAt: now,
      strings: updatedStrings,
    );

    if (shouldApplyShotCount) {
      for (final entry in validAppliedShotCounts.entries) {
        final rifleIdx = _rifles.indexWhere((r) => r.id == entry.key);
        if (rifleIdx >= 0) {
          final rifle = _rifles[rifleIdx];
          final nextTotalRoundCount = rifle.manualRoundCount + entry.value;
          final nextBarrelRoundCount = rifle.barrelRoundCount + entry.value;
          _rifles[rifleIdx] = rifle.copyWith(
            manualRoundCount: nextTotalRoundCount,
            barrelRoundCount: nextBarrelRoundCount,
          );
        }
      }
    }
    notifyListeners();
  }

  void addRifleRounds({required String rifleId, required int roundCount}) {
    if (roundCount <= 0) return;
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx < 0) return;
    final rifle = _rifles[idx];
    final nextTotalRoundCount = rifle.manualRoundCount + roundCount;
    final nextBarrelRoundCount = rifle.barrelRoundCount + roundCount;
    _rifles[idx] = rifle.copyWith(
      manualRoundCount: nextTotalRoundCount,
      barrelRoundCount: nextBarrelRoundCount,
    );
    notifyListeners();
  }

  void resetRifleBarrelCount({
    required String rifleId,
    DateTime? installedDate,
    String notes = '',
  }) {
    final idx = _rifles.indexWhere((r) => r.id == rifleId);
    if (idx < 0) return;
    final rifle = _rifles[idx];
    final nextInstalledDate = installedDate ?? DateTime.now();
    final barrelChangeNotes = <String>[
      if (rifle.barrelRoundCount > 0)
        'Previous barrel rounds: ${rifle.barrelRoundCount}',
      if (notes.trim().isNotEmpty) notes.trim(),
    ].join(' • ');
    final nextServices = [
      RifleServiceEntry(
        id: _newId(),
        service: _maintenanceTaskLabel(MaintenanceTaskType.barrelChange),
        date: nextInstalledDate,
        roundsAtService: rifle.manualRoundCount,
        notes: barrelChangeNotes,
        taskType: MaintenanceTaskType.barrelChange,
      ),
      ...rifle.services,
    ]..sort((a, b) => b.date.compareTo(a.date));
    _rifles[idx] = rifle.copyWith(
      barrelRoundCount: 0,
      barrelInstalledDate: nextInstalledDate,
      barrelNotes: notes.trim(),
      services: nextServices,
    );
    notifyListeners();
  }

  String exportBackupJson() {
    final payload = <String, dynamic>{
      'schema': kBackupSchemaVersion,
      'generatedAt': DateTime.now().toIso8601String(),
      ..._toMap(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  void importBackupJson(String jsonText, {required bool replaceExisting}) {
    final decoded = json.decode(jsonText);
    if (decoded is! Map) throw FormatException('Invalid backup JSON');
    final map = Map<String, dynamic>.from(decoded);

    final exportType = (map['exportType'] ?? '').toString().trim();
    if (exportType == 'sharedSession' && map['session'] is Map) {
      importSharedSessionJson(jsonText);
      return;
    }

    final hasFullAppState =
        map.containsKey('users') ||
        map.containsKey('sessions') ||
        map.containsKey('activeUserId') ||
        map.containsKey('shotTimerSettings') ||
        map.containsKey('environment');

    if (replaceExisting && hasFullAppState) {
      _restoreFromMap(map);
      notifyListeners();
      return;
    }

    int toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v.toString().trim()) ?? 0;
    }

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim());
    }

    String toStr(dynamic v) => v == null ? '' : v.toString();

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
        purchaseDate: (m['purchaseDate'] as String?) == null
            ? null
            : DateTime.tryParse(m['purchaseDate'] as String),
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
        id: toStr(m['id']).isEmpty
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : toStr(m['id']),
        caliber: toStr(m['caliber']),
        grain: toInt(m['grain']),
        name: (m['name'] as String?)?.trim(),
        bullet: (() {
          final b = toStr(m['bullet']).trim();
          if (b.isNotEmpty) return b;
          final b2 = toStr(m['bulletName']).trim();
          if (b2.isNotEmpty) return b2;
          return 'Bullet';
        })(),
        ballisticCoefficient: toDouble(m['ballisticCoefficient'] ?? m['bc']),
        manufacturer: (m['manufacturer'] as String?)?.trim(),
        lotNumber: (m['lotNumber'] as String?)?.trim(),
        purchaseDate: (m['purchaseDate'] as String?) == null
            ? null
            : DateTime.tryParse((m['purchaseDate'] as String).trim()),
        purchasePrice: (m['purchasePrice'] as String?)?.trim(),
        notes: toStr(m['notes']),
      );
    }).toList();

    if (replaceExisting) {
      _rifles
        ..clear()
        ..addAll(rifles);
      _ammoLots
        ..clear()
        ..addAll(ammo);
    } else {
      for (final r in rifles) {
        final i = _rifles.indexWhere((e) => e.id == r.id);
        if (i >= 0) {
          _rifles[i] = r;
        } else {
          _rifles.add(r);
        }
      }
      for (final a in ammo) {
        final i = _ammoLots.indexWhere((e) => e.id == a.id);
        if (i >= 0) {
          _ammoLots[i] = a;
        } else {
          _ammoLots.add(a);
        }
      }
    }
    notifyListeners();
  }

  void importSharedSessionJson(
    String jsonText, {
    bool? acceptNotes,
    bool? acceptTrainingDope,
    bool? acceptLocation,
    bool? acceptPhotos,
    bool? acceptShotResults,
    bool? acceptTimerData,
  }) {
    final decoded = json.decode(jsonText);
    if (decoded is! Map) throw FormatException('Invalid shared session JSON');
    final map = Map<String, dynamic>.from(decoded);
    final sessionRaw = map['session'];
    if (sessionRaw is! Map) {
      throw FormatException('Missing session payload');
    }

    mergeBackupJson(jsonText, overwriteScope: false);

    final ownerIdentifier = (map['ownerIdentifier'] ?? '').toString().trim();
    final incoming = _trainingSessionFromMap(
      Map<String, dynamic>.from(sessionRaw),
    );
    rememberTrustedPartnerIdentifier(ownerIdentifier);

    if (_users.isEmpty) {
      _seedData();
    }

    final owner = ownerIdentifier.isNotEmpty
        ? _ensureUserByIdentifier(ownerIdentifier)
        : (_activeUser ?? _users.first);
    final viewer = _activeUser ?? owner;

    final normalized = incoming.copyWith(
      userId: owner.id,
      memberUserIds: <String>{owner.id, viewer.id}.toList(),
    );

    final idx = _sessions.indexWhere((s) => s.id == normalized.id);
    if (idx >= 0) {
      _sessions[idx] = normalized;
    } else {
      _sessions.add(normalized);
    }

    final hasExplicitAcceptance =
        acceptNotes != null &&
        acceptTrainingDope != null &&
        acceptLocation != null &&
        acceptPhotos != null &&
        acceptShotResults != null &&
        acceptTimerData != null;

    if (hasExplicitAcceptance) {
      _acceptedSharedFieldsBySession[normalized.id] = <String, bool>{
        sharedFieldNotes: normalized.shareNotesWithMembers
            ? acceptNotes
            : false,
        sharedFieldTrainingDope: normalized.shareTrainingDopeWithMembers
            ? acceptTrainingDope
            : false,
        sharedFieldLocation: normalized.shareLocationWithMembers
            ? acceptLocation
            : false,
        sharedFieldPhotos: normalized.sharePhotosWithMembers
            ? acceptPhotos
            : false,
        sharedFieldShotResults: normalized.shareShotResultsWithMembers
            ? acceptShotResults
            : false,
        sharedFieldTimerData: normalized.shareTimerDataWithMembers
            ? acceptTimerData
            : false,
      };
    } else if (viewer.id != owner.id) {
      _enqueueSharedAcceptancePrompt(normalized.id);
    } else {
      _acceptedSharedFieldsBySession[normalized.id] = <String, bool>{
        sharedFieldNotes: true,
        sharedFieldTrainingDope: true,
        sharedFieldLocation: true,
        sharedFieldPhotos: true,
        sharedFieldShotResults: true,
        sharedFieldTimerData: true,
      };
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
    final map = Map<String, dynamic>.from(decoded);

    final importedRifles = ((map['rifles'] as List?) ?? const [])
        .map((x) {
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
              (u) =>
                  u.name == (m['scopeUnit'] ?? ScopeUnit.mil.name).toString(),
              orElse: () => ScopeUnit.mil,
            ),
            manualRoundCount: (m['manualRoundCount'] as int?) ?? 0,
            barrelRoundCount:
                (m['barrelRoundCount'] as int?) ??
                ((m['manualRoundCount'] as int?) ?? 0),
            barrelInstalledDate: (m['barrelInstalledDate'] as String?) != null
                ? DateTime.tryParse((m['barrelInstalledDate'] as String))
                : null,
            barrelNotes: (m['barrelNotes'] as String?)?.toString() ?? '',
            dopeEntries:
                (m['dopeEntries'] as List?)
                    ?.map(
                      (e) => RifleDopeEntry.fromMap(
                        Map<String, dynamic>.from(e as Map),
                      ),
                    )
                    .toList() ??
                const [],
          );
        })
        .where((r) => r.caliber.trim().isNotEmpty)
        .toList();

    final importedAmmo = ((map['ammoLots'] as List?) ?? const [])
        .map((x) {
          final m = Map<String, dynamic>.from(x as Map);
          return AmmoLot(
            id: (m['id'] ?? '').toString(),
            caliber: (m['caliber'] ?? '').toString(),
            grain: (m['grain'] as num?)?.round() ?? 0,
            name: (m['name'] as String?)?.toString(),
            bullet: (m['bullet'] as String?) ?? '',
            ballisticCoefficient: (m['ballisticCoefficient'] as num?)
                ?.toDouble(),
            manufacturer: (m['manufacturer'] as String?)?.toString(),
            lotNumber: (m['lotNumber'] as String?)?.toString(),
            purchaseDate: (m['purchaseDate'] as String?) != null
                ? DateTime.tryParse((m['purchaseDate'] as String))
                : null,
            purchasePrice: (m['purchasePrice'] as String?)?.toString(),
            notes: (m['notes'] as String?)?.toString() ?? '',
          );
        })
        .where((a) => a.caliber.trim().isNotEmpty)
        .toList();

    int findRifleMatchIndex(Rifle incoming) {
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
          if (norm(r.name).isNotEmpty && norm(r.name) == norm(incoming.name)) {
            return i;
          }
        }
      }
      return -1;
    }

    int findAmmoMatchIndex(AmmoLot incoming) {
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
        if (norm(a.name).isNotEmpty && norm(a.name) == norm(incoming.name)) {
          return i;
        }
      }
      return -1;
    }

    String? preferExistingNullable(String? existing, String? incoming) {
      final e = (existing ?? '').trim();
      if (e.isNotEmpty) return existing;
      final n = (incoming ?? '').trim();
      return n.isEmpty ? existing : incoming;
    }

    DateTime? preferExistingDateTime(DateTime? existing, DateTime? incoming) {
      return incoming ?? existing;
    }

    String preferExistingRequired(String existing, String incoming) {
      final e = existing.trim();
      if (e.isNotEmpty) return existing;
      final n = incoming.trim();
      return n.isNotEmpty ? incoming : existing;
    }

    int preferExistingInt(int existing, int incoming) =>
        existing != 0 ? existing : incoming;

    double? preferExistingDouble(double? existing, double? incoming) =>
        existing ?? incoming;

    // Merge rifles
    for (final incoming in importedRifles) {
      final idx = findRifleMatchIndex(incoming);
      if (idx < 0) {
        _rifles.add(incoming);
        continue;
      }
      final existing = _rifles[idx];

      final updated = existing.copyWith(
        name: preferExistingNullable(existing.name, incoming.name),
        manufacturer: preferExistingNullable(
          existing.manufacturer,
          incoming.manufacturer,
        ),
        model: preferExistingNullable(existing.model, incoming.model),
        serialNumber: preferExistingNullable(
          existing.serialNumber,
          incoming.serialNumber,
        ),
        barrelLength: preferExistingNullable(
          existing.barrelLength,
          incoming.barrelLength,
        ),
        twistRate: preferExistingNullable(
          existing.twistRate,
          incoming.twistRate,
        ),
        purchaseDate: existing.purchaseDate ?? incoming.purchaseDate,
        purchasePrice: preferExistingNullable(
          existing.purchasePrice,
          incoming.purchasePrice,
        ),
        purchaseLocation: preferExistingNullable(
          existing.purchaseLocation,
          incoming.purchaseLocation,
        ),
        notes: preferExistingRequired(existing.notes, incoming.notes),
        dope: preferExistingRequired(existing.dope, incoming.dope),
        // Never overwrite history fields here (manualRoundCount, dopeEntries).
        scopeUnit: overwriteScope ? incoming.scopeUnit : existing.scopeUnit,
        scopeMake: overwriteScope ? incoming.scopeMake : existing.scopeMake,
        scopeModel: overwriteScope ? incoming.scopeModel : existing.scopeModel,
        scopeSerial: overwriteScope
            ? incoming.scopeSerial
            : existing.scopeSerial,
        scopeMount: overwriteScope ? incoming.scopeMount : existing.scopeMount,
        scopeNotes: overwriteScope ? incoming.scopeNotes : existing.scopeNotes,
      );

      _rifles[idx] = updated;
    }

    // Merge ammo
    for (final incoming in importedAmmo) {
      final idx = findAmmoMatchIndex(incoming);
      if (idx < 0) {
        _ammoLots.add(incoming);
        continue;
      }
      final existing = _ammoLots[idx];
      final updated = AmmoLot(
        id: existing.id,
        caliber: existing.caliber,
        grain: preferExistingInt(existing.grain, incoming.grain),
        name: preferExistingNullable(existing.name, incoming.name),
        bullet: preferExistingRequired(existing.bullet, incoming.bullet),
        ballisticCoefficient: preferExistingDouble(
          existing.ballisticCoefficient,
          incoming.ballisticCoefficient,
        ),
        manufacturer: preferExistingNullable(
          existing.manufacturer,
          incoming.manufacturer,
        ),
        lotNumber: preferExistingNullable(
          existing.lotNumber,
          incoming.lotNumber,
        ),
        purchaseDate: preferExistingDateTime(
          existing.purchaseDate,
          incoming.purchaseDate,
        ),
        purchasePrice: preferExistingNullable(
          existing.purchasePrice,
          incoming.purchasePrice,
        ),
        notes: preferExistingRequired(existing.notes, incoming.notes),
      );
      _ammoLots[idx] = updated;
    }

    // Refresh UI after merge completes.
    notifyListeners();
  }
}

int? _toNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _toNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime _parseDateTime(dynamic value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}

Map<String, dynamic> _userToMap(UserProfile user) => <String, dynamic>{
  'id': user.id,
  'name': user.name,
  'identifier': user.identifier,
};

UserProfile _userFromMap(Map<String, dynamic> map) => UserProfile(
  id: (map['id'] ?? '').toString(),
  name: map['name']?.toString(),
  identifier: (map['identifier'] ?? '').toString(),
);

Map<String, dynamic> _rifleToMap(Rifle rifle) => <String, dynamic>{
  'id': rifle.id,
  'name': rifle.name,
  'caliber': rifle.caliber,
  'notes': rifle.notes,
  'dope': rifle.dope,
  'dopeEntries': rifle.dopeEntries.map((e) => e.toMap()).toList(),
  'preferredUnit': rifle.preferredUnit.name,
  'scopeUnit': rifle.scopeUnit.name,
  'manualRoundCount': rifle.manualRoundCount,
  'barrelRoundCount': rifle.barrelRoundCount,
  'barrelInstalledDate': rifle.barrelInstalledDate?.toIso8601String(),
  'barrelNotes': rifle.barrelNotes,
  'services': rifle.services.map((s) => s.toMap()).toList(),
  'maintenanceRules': rifle.maintenanceRules.map((r) => r.toMap()).toList(),
  'scopeMake': rifle.scopeMake,
  'scopeModel': rifle.scopeModel,
  'scopeSerial': rifle.scopeSerial,
  'scopeMount': rifle.scopeMount,
  'scopeNotes': rifle.scopeNotes,
  'manufacturer': rifle.manufacturer,
  'model': rifle.model,
  'serialNumber': rifle.serialNumber,
  'barrelLength': rifle.barrelLength,
  'twistRate': rifle.twistRate,
  'purchaseDate': rifle.purchaseDate?.toIso8601String(),
  'purchasePrice': rifle.purchasePrice,
  'purchaseLocation': rifle.purchaseLocation,
};

Rifle _rifleFromMap(Map<String, dynamic> map) => Rifle(
  id: (map['id'] ?? '').toString(),
  name: map['name']?.toString(),
  caliber: (map['caliber'] ?? '').toString(),
  notes: (map['notes'] ?? '').toString(),
  dope: (map['dope'] ?? '').toString(),
  dopeEntries: ((map['dopeEntries'] as List?) ?? const [])
      .map((e) => RifleDopeEntry.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList(),
  preferredUnit: ElevationUnit.values.firstWhere(
    (u) =>
        u.name == (map['preferredUnit'] ?? ElevationUnit.mil.name).toString(),
    orElse: () => ElevationUnit.mil,
  ),
  scopeUnit: ScopeUnit.values.firstWhere(
    (u) => u.name == (map['scopeUnit'] ?? ScopeUnit.mil.name).toString(),
    orElse: () => ScopeUnit.mil,
  ),
  manualRoundCount: _toNullableInt(map['manualRoundCount']) ?? 0,
  barrelRoundCount: _toNullableInt(map['barrelRoundCount']) ?? 0,
  barrelInstalledDate: map['barrelInstalledDate'] == null
      ? null
      : _parseDateTime(map['barrelInstalledDate']),
  barrelNotes: (map['barrelNotes'] ?? '').toString(),
  services: ((map['services'] as List?) ?? const [])
      .map(
        (e) => RifleServiceEntry.fromMap(Map<String, dynamic>.from(e as Map)),
      )
      .toList(),
  maintenanceRules: ((map['maintenanceRules'] as List?) ?? const [])
      .map(
        (e) => MaintenanceReminderRule.fromMap(
          Map<String, dynamic>.from(e as Map),
        ),
      )
      .toList(),
  scopeMake: map['scopeMake']?.toString(),
  scopeModel: map['scopeModel']?.toString(),
  scopeSerial: map['scopeSerial']?.toString(),
  scopeMount: map['scopeMount']?.toString(),
  scopeNotes: map['scopeNotes']?.toString(),
  manufacturer: map['manufacturer']?.toString(),
  model: map['model']?.toString(),
  serialNumber: map['serialNumber']?.toString(),
  barrelLength: map['barrelLength']?.toString(),
  twistRate: map['twistRate']?.toString(),
  purchaseDate: map['purchaseDate'] == null
      ? null
      : _parseDateTime(map['purchaseDate']),
  purchasePrice: map['purchasePrice']?.toString(),
  purchaseLocation: map['purchaseLocation']?.toString(),
);

Map<String, dynamic> _ammoLotToMap(AmmoLot ammo) => <String, dynamic>{
  'id': ammo.id,
  'name': ammo.name,
  'caliber': ammo.caliber,
  'grain': ammo.grain,
  'bullet': ammo.bullet,
  'notes': ammo.notes,
  'manufacturer': ammo.manufacturer,
  'lotNumber': ammo.lotNumber,
  'purchaseDate': ammo.purchaseDate?.toIso8601String(),
  'purchasePrice': ammo.purchasePrice,
  'ballisticCoefficient': ammo.ballisticCoefficient,
};

AmmoLot _ammoLotFromMap(Map<String, dynamic> map) => AmmoLot(
  id: (map['id'] ?? '').toString(),
  name: map['name']?.toString(),
  caliber: (map['caliber'] ?? '').toString(),
  grain: _toNullableInt(map['grain']) ?? 0,
  bullet: (map['bullet'] ?? '').toString(),
  notes: (map['notes'] ?? '').toString(),
  manufacturer: map['manufacturer']?.toString(),
  lotNumber: map['lotNumber']?.toString(),
  purchaseDate: map['purchaseDate'] == null
      ? null
      : _parseDateTime(map['purchaseDate']),
  purchasePrice: map['purchasePrice']?.toString(),
  ballisticCoefficient: _toNullableDouble(map['ballisticCoefficient']),
);

Map<String, dynamic> _sessionStringMetaToMap(SessionStringMeta meta) =>
    <String, dynamic>{
      'id': meta.id,
      'startedAt': meta.startedAt.toIso8601String(),
      'endedAt': meta.endedAt?.toIso8601String(),
      'rifleId': meta.rifleId,
      'ammoLotId': meta.ammoLotId,
    };

SessionStringMeta _sessionStringMetaFromMap(Map<String, dynamic> map) =>
    SessionStringMeta(
      id: (map['id'] ?? '').toString(),
      startedAt: _parseDateTime(map['startedAt']),
      endedAt: map['endedAt'] == null ? null : _parseDateTime(map['endedAt']),
      rifleId: map['rifleId']?.toString(),
      ammoLotId: map['ammoLotId']?.toString(),
    );

Map<String, dynamic> _dopeEntryToMap(DopeEntry entry) => <String, dynamic>{
  'id': entry.id,
  'time': entry.time.toIso8601String(),
  'rifleId': entry.rifleId,
  'ammoLotId': entry.ammoLotId,
  'distance': entry.distance,
  'distanceUnit': entry.distanceUnit.name,
  'elevation': entry.elevation,
  'elevationUnit': entry.elevationUnit.name,
  'elevationNotes': entry.elevationNotes,
  'windType': entry.windType.name,
  'windValue': entry.windValue,
  'windNotes': entry.windNotes,
  'windageLeft': entry.windageLeft,
  'windageRight': entry.windageRight,
};

DopeEntry _dopeEntryFromMap(Map<String, dynamic> map) => DopeEntry(
  id: (map['id'] ?? '').toString(),
  time: _parseDateTime(map['time']),
  rifleId: map['rifleId']?.toString(),
  ammoLotId: map['ammoLotId']?.toString(),
  distance: _toNullableDouble(map['distance']) ?? 0,
  distanceUnit: DistanceUnit.values.firstWhere(
    (u) =>
        u.name == (map['distanceUnit'] ?? DistanceUnit.yards.name).toString(),
    orElse: () => DistanceUnit.yards,
  ),
  elevation: _toNullableDouble(map['elevation']) ?? 0,
  elevationUnit: ElevationUnit.values.firstWhere(
    (u) =>
        u.name == (map['elevationUnit'] ?? ElevationUnit.mil.name).toString(),
    orElse: () => ElevationUnit.mil,
  ),
  elevationNotes: (map['elevationNotes'] ?? '').toString(),
  windType: WindType.values.firstWhere(
    (u) => u.name == (map['windType'] ?? WindType.fullValue.name).toString(),
    orElse: () => WindType.fullValue,
  ),
  windValue: (map['windValue'] ?? '').toString(),
  windNotes: (map['windNotes'] ?? '').toString(),
  windageLeft: _toNullableDouble(map['windageLeft']) ?? 0,
  windageRight: _toNullableDouble(map['windageRight']) ?? 0,
);

Map<String, dynamic> _coldBorePhotoToMap(ColdBorePhoto photo) =>
    <String, dynamic>{
      'id': photo.id,
      'time': photo.time.toIso8601String(),
      'bytes': base64Encode(photo.bytes),
      'caption': photo.caption,
    };

ColdBorePhoto _coldBorePhotoFromMap(Map<String, dynamic> map) => ColdBorePhoto(
  id: (map['id'] ?? '').toString(),
  time: _parseDateTime(map['time']),
  bytes: base64Decode((map['bytes'] ?? '').toString()),
  caption: (map['caption'] ?? '').toString(),
);

Map<String, dynamic> _shotEntryToMap(ShotEntry shot) => <String, dynamic>{
  'id': shot.id,
  'time': shot.time.toIso8601String(),
  'isColdBore': shot.isColdBore,
  'isBaseline': shot.isBaseline,
  'distance': shot.distance,
  'result': shot.result,
  'notes': shot.notes,
  'offsetX': shot.offsetX,
  'offsetY': shot.offsetY,
  'offsetUnit': shot.offsetUnit,
  'photos': shot.photos.map(_coldBorePhotoToMap).toList(),
};

ShotEntry _shotEntryFromMap(Map<String, dynamic> map) => ShotEntry(
  id: (map['id'] ?? '').toString(),
  time: _parseDateTime(map['time']),
  isColdBore: map['isColdBore'] == true,
  isBaseline: map['isBaseline'] == true,
  distance: (map['distance'] ?? '').toString(),
  result: (map['result'] ?? '').toString(),
  notes: (map['notes'] ?? '').toString(),
  offsetX: _toNullableDouble(map['offsetX']),
  offsetY: _toNullableDouble(map['offsetY']),
  offsetUnit: (map['offsetUnit'] ?? 'in').toString(),
  photos: ((map['photos'] as List?) ?? const [])
      .map((e) => _coldBorePhotoFromMap(Map<String, dynamic>.from(e as Map)))
      .toList(),
);

Map<String, dynamic> _photoNoteToMap(PhotoNote photo) => <String, dynamic>{
  'id': photo.id,
  'time': photo.time.toIso8601String(),
  'caption': photo.caption,
};

PhotoNote _photoNoteFromMap(Map<String, dynamic> map) => PhotoNote(
  id: (map['id'] ?? '').toString(),
  time: _parseDateTime(map['time']),
  caption: (map['caption'] ?? '').toString(),
);

Map<String, dynamic> _sessionPhotoToMap(SessionPhoto photo) =>
    <String, dynamic>{
      'id': photo.id,
      'time': photo.time.toIso8601String(),
      'bytes': base64Encode(photo.bytes),
      'caption': photo.caption,
    };

SessionPhoto _sessionPhotoFromMap(Map<String, dynamic> map) => SessionPhoto(
  id: (map['id'] ?? '').toString(),
  time: _parseDateTime(map['time']),
  bytes: base64Decode((map['bytes'] ?? '').toString()),
  caption: (map['caption'] ?? '').toString(),
);

Map<String, dynamic> _sessionTimerRunToMap(SessionTimerRun run) =>
    <String, dynamic>{
      'id': run.id,
      'time': run.time.toIso8601String(),
      'elapsedMs': run.elapsedMs,
      'firstShotMs': run.firstShotMs,
      'splitMs': run.splitMs,
      'startDelayMs': run.startDelayMs,
      'goalMs': run.goalMs,
    };

SessionTimerRun _sessionTimerRunFromMap(Map<String, dynamic> map) =>
    SessionTimerRun(
      id: (map['id'] ?? '').toString(),
      time: _parseDateTime(map['time']),
      elapsedMs: _toNullableInt(map['elapsedMs']) ?? 0,
      firstShotMs: _toNullableInt(map['firstShotMs']) ?? 0,
      splitMs: ((map['splitMs'] as List?) ?? const [])
          .map((e) => _toNullableInt(e) ?? 0)
          .toList(),
      startDelayMs: _toNullableInt(map['startDelayMs']) ?? 0,
      goalMs: _toNullableInt(map['goalMs']) ?? 0,
    );

Map<String, dynamic> _trainingSessionToMap(TrainingSession session) =>
    <String, dynamic>{
      'id': session.id,
      'userId': session.userId,
      'memberUserIds': session.memberUserIds,
  'externalMemberIdentifiers': session.externalMemberIdentifiers,
      'dateTime': session.dateTime.toIso8601String(),
      'locationName': session.locationName,
      'folderName': session.folderName,
      'archived': session.archived,
      'notes': session.notes,
      'shareNotesWithMembers': session.shareNotesWithMembers,
      'shareTrainingDopeWithMembers': session.shareTrainingDopeWithMembers,
      'shareLocationWithMembers': session.shareLocationWithMembers,
      'sharePhotosWithMembers': session.sharePhotosWithMembers,
      'shareShotResultsWithMembers': session.shareShotResultsWithMembers,
      'shareTimerDataWithMembers': session.shareTimerDataWithMembers,
      'latitude': session.latitude,
      'longitude': session.longitude,
      'temperatureF': session.temperatureF,
      'windSpeedMph': session.windSpeedMph,
      'windDirectionDeg': session.windDirectionDeg,
      'rifleId': session.rifleId,
      'ammoLotId': session.ammoLotId,
      'strings': session.strings.map(_sessionStringMetaToMap).toList(),
      'activeStringId': session.activeStringId,
      'confirmedShotCount': session.confirmedShotCount,
      'shotCountAppliedToRifle': session.shotCountAppliedToRifle,
      'endedAt': session.endedAt?.toIso8601String(),
      'shotTimerElapsedMs': session.shotTimerElapsedMs,
      'shotTimerFirstShotMs': session.shotTimerFirstShotMs,
      'shotTimerSplitMs': session.shotTimerSplitMs,
      'timerRuns': session.timerRuns.map(_sessionTimerRunToMap).toList(),
      'trainingDopeByString': session.trainingDopeByString.map(
        (key, value) => MapEntry(key, value.map(_dopeEntryToMap).toList()),
      ),
      'shotsByString': session.shotsByString.map(
        (key, value) => MapEntry(key, value.map(_shotEntryToMap).toList()),
      ),
      'shots': session.shots.map(_shotEntryToMap).toList(),
      'photos': session.photos.map(_photoNoteToMap).toList(),
      'sessionPhotos': session.sessionPhotos.map(_sessionPhotoToMap).toList(),
      'trainingDope': session.trainingDope.map(_dopeEntryToMap).toList(),
    };

TrainingSession _trainingSessionFromMap(
  Map<String, dynamic> map,
) => TrainingSession(
  id: (map['id'] ?? '').toString(),
  userId: (map['userId'] ?? '').toString(),
  memberUserIds: (() {
    final members = ((map['memberUserIds'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((id) => id.trim().isNotEmpty)
        .toList();
    if (members.isNotEmpty) return members;
    final ownerId = (map['userId'] ?? '').toString().trim();
    if (ownerId.isNotEmpty) return [ownerId];
    return const <String>[];
  })(),
  externalMemberIdentifiers: ((map['externalMemberIdentifiers'] as List?) ??
          const [])
      .map((e) => e.toString().trim().toUpperCase())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(),
  dateTime: _parseDateTime(map['dateTime']),
  locationName: (map['locationName'] ?? '').toString(),
  folderName: (map['folderName'] ?? '').toString(),
  archived: map['archived'] == true,
  notes: (map['notes'] ?? '').toString(),
  shareNotesWithMembers: map['shareNotesWithMembers'] != false,
  shareTrainingDopeWithMembers: map['shareTrainingDopeWithMembers'] != false,
  shareLocationWithMembers: map['shareLocationWithMembers'] != false,
  sharePhotosWithMembers: map['sharePhotosWithMembers'] != false,
  shareShotResultsWithMembers: map['shareShotResultsWithMembers'] != false,
  shareTimerDataWithMembers: map['shareTimerDataWithMembers'] != false,
  latitude: _toNullableDouble(map['latitude']),
  longitude: _toNullableDouble(map['longitude']),
  temperatureF: _toNullableDouble(map['temperatureF']),
  windSpeedMph: _toNullableDouble(map['windSpeedMph']),
  windDirectionDeg: _toNullableInt(map['windDirectionDeg']),
  rifleId: map['rifleId']?.toString(),
  ammoLotId: map['ammoLotId']?.toString(),
  shots: ((map['shots'] as List?) ?? const [])
      .map((e) => _shotEntryFromMap(Map<String, dynamic>.from(e as Map)))
      .toList(),
  photos: ((map['photos'] as List?) ?? const [])
      .map((e) => _photoNoteFromMap(Map<String, dynamic>.from(e as Map)))
      .toList(),
  sessionPhotos: ((map['sessionPhotos'] as List?) ?? const [])
      .map((e) => _sessionPhotoFromMap(Map<String, dynamic>.from(e as Map)))
      .toList(),
  trainingDope: ((map['trainingDope'] as List?) ?? const [])
      .map((e) => _dopeEntryFromMap(Map<String, dynamic>.from(e as Map)))
      .toList(),
  trainingDopeByString:
      ((map['trainingDopeByString'] as Map?) ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(
          key.toString(),
          ((value as List?) ?? const [])
              .map(
                (e) => _dopeEntryFromMap(Map<String, dynamic>.from(e as Map)),
              )
              .toList(),
        ),
      ),
  shotsByString: ((map['shotsByString'] as Map?) ?? const <String, dynamic>{})
      .map(
        (key, value) => MapEntry(
          key.toString(),
          ((value as List?) ?? const [])
              .map(
                (e) => _shotEntryFromMap(Map<String, dynamic>.from(e as Map)),
              )
              .toList(),
        ),
      ),
  strings: ((map['strings'] as List?) ?? const [])
      .map(
        (e) => _sessionStringMetaFromMap(Map<String, dynamic>.from(e as Map)),
      )
      .toList(),
  activeStringId: (map['activeStringId'] ?? '').toString(),
  confirmedShotCount: _toNullableInt(map['confirmedShotCount']),
  shotCountAppliedToRifle: map['shotCountAppliedToRifle'] == true,
  endedAt: map['endedAt'] == null ? null : _parseDateTime(map['endedAt']),
  shotTimerElapsedMs: _toNullableInt(map['shotTimerElapsedMs']),
  shotTimerFirstShotMs: _toNullableInt(map['shotTimerFirstShotMs']),
  shotTimerSplitMs: ((map['shotTimerSplitMs'] as List?) ?? const [])
      .map((e) => _toNullableInt(e) ?? 0)
      .toList(),
  timerRuns: ((map['timerRuns'] as List?) ?? const [])
      .map((e) => _sessionTimerRunFromMap(Map<String, dynamic>.from(e as Map)))
      .toList(),
);

class UserProfile {
  final String id;
  final String? name;
  final String identifier;

  UserProfile({required this.id, this.name, required this.identifier});
}

enum MaintenanceTaskType {
  general,
  cleaning,
  deepCleaning,
  torqueCheck,
  zeroConfirm,
  barrelLife,
  barrelChange,
}

enum MaintenanceDueStatus { good, dueSoon, overdue }

String _maintenanceTaskLabel(MaintenanceTaskType type) {
  switch (type) {
    case MaintenanceTaskType.general:
      return 'General service';
    case MaintenanceTaskType.cleaning:
      return 'Cleaning';
    case MaintenanceTaskType.deepCleaning:
      return 'Deep clean';
    case MaintenanceTaskType.torqueCheck:
      return 'Torque check';
    case MaintenanceTaskType.zeroConfirm:
      return 'Zero confirm';
    case MaintenanceTaskType.barrelLife:
      return 'Barrel life';
    case MaintenanceTaskType.barrelChange:
      return 'Barrel change';
  }
}

IconData _maintenanceTaskIcon(MaintenanceTaskType type) {
  switch (type) {
    case MaintenanceTaskType.general:
      return Icons.build_outlined;
    case MaintenanceTaskType.cleaning:
      return Icons.cleaning_services_outlined;
    case MaintenanceTaskType.deepCleaning:
      return Icons.auto_fix_high_outlined;
    case MaintenanceTaskType.torqueCheck:
      return Icons.hardware_outlined;
    case MaintenanceTaskType.zeroConfirm:
      return Icons.gps_fixed;
    case MaintenanceTaskType.barrelLife:
      return Icons.timeline_outlined;
    case MaintenanceTaskType.barrelChange:
      return Icons.refresh_outlined;
  }
}

bool _isConfigurableMaintenanceTask(MaintenanceTaskType type) {
  return type != MaintenanceTaskType.general &&
      type != MaintenanceTaskType.barrelChange;
}

bool _maintenanceTaskSupportsRounds(MaintenanceTaskType type) {
  switch (type) {
    case MaintenanceTaskType.cleaning:
    case MaintenanceTaskType.deepCleaning:
    case MaintenanceTaskType.torqueCheck:
    case MaintenanceTaskType.barrelLife:
      return true;
    case MaintenanceTaskType.general:
    case MaintenanceTaskType.zeroConfirm:
    case MaintenanceTaskType.barrelChange:
      return false;
  }
}

bool _maintenanceTaskSupportsDays(MaintenanceTaskType type) {
  switch (type) {
    case MaintenanceTaskType.cleaning:
    case MaintenanceTaskType.deepCleaning:
    case MaintenanceTaskType.torqueCheck:
    case MaintenanceTaskType.zeroConfirm:
      return true;
    case MaintenanceTaskType.general:
    case MaintenanceTaskType.barrelLife:
    case MaintenanceTaskType.barrelChange:
      return false;
  }
}

class MaintenanceReminderRule {
  final MaintenanceTaskType type;
  final bool enabled;
  final int? intervalRounds;
  final int? intervalDays;
  final String notes;

  const MaintenanceReminderRule({
    required this.type,
    required this.enabled,
    this.intervalRounds,
    this.intervalDays,
    this.notes = '',
  });

  factory MaintenanceReminderRule.defaultFor(MaintenanceTaskType type) {
    switch (type) {
      case MaintenanceTaskType.cleaning:
        return const MaintenanceReminderRule(
          type: MaintenanceTaskType.cleaning,
          enabled: true,
          intervalRounds: 150,
        );
      case MaintenanceTaskType.deepCleaning:
        return const MaintenanceReminderRule(
          type: MaintenanceTaskType.deepCleaning,
          enabled: false,
          intervalRounds: 500,
        );
      case MaintenanceTaskType.torqueCheck:
        return const MaintenanceReminderRule(
          type: MaintenanceTaskType.torqueCheck,
          enabled: true,
          intervalRounds: 250,
          intervalDays: 30,
        );
      case MaintenanceTaskType.zeroConfirm:
        return const MaintenanceReminderRule(
          type: MaintenanceTaskType.zeroConfirm,
          enabled: true,
          intervalDays: 30,
        );
      case MaintenanceTaskType.barrelLife:
        return const MaintenanceReminderRule(
          type: MaintenanceTaskType.barrelLife,
          enabled: true,
          intervalRounds: 2000,
        );
      case MaintenanceTaskType.general:
      case MaintenanceTaskType.barrelChange:
        return MaintenanceReminderRule(type: type, enabled: false);
    }
  }

  MaintenanceReminderRule copyWith({
    MaintenanceTaskType? type,
    bool? enabled,
    int? intervalRounds,
    bool clearRounds = false,
    int? intervalDays,
    bool clearDays = false,
    String? notes,
  }) {
    return MaintenanceReminderRule(
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      intervalRounds: clearRounds
          ? null
          : (intervalRounds ?? this.intervalRounds),
      intervalDays: clearDays ? null : (intervalDays ?? this.intervalDays),
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'type': type.name,
    'enabled': enabled,
    'intervalRounds': intervalRounds,
    'intervalDays': intervalDays,
    'notes': notes,
  };

  factory MaintenanceReminderRule.fromMap(Map<String, dynamic> map) {
    final type = MaintenanceTaskType.values.firstWhere(
      (value) => value.name == (map['type'] ?? '').toString(),
      orElse: () => MaintenanceTaskType.general,
    );
    return MaintenanceReminderRule(
      type: type,
      enabled: map['enabled'] == true,
      intervalRounds: _toNullableInt(map['intervalRounds']),
      intervalDays: _toNullableInt(map['intervalDays']),
      notes: (map['notes'] ?? '').toString(),
    );
  }
}

class MaintenanceReminderStatus {
  final MaintenanceReminderRule rule;
  final MaintenanceDueStatus status;
  final int? roundsSince;
  final int? roundsRemaining;
  final int? daysSince;
  final int? daysRemaining;
  final RifleServiceEntry? lastService;

  const MaintenanceReminderStatus({
    required this.rule,
    required this.status,
    this.roundsSince,
    this.roundsRemaining,
    this.daysSince,
    this.daysRemaining,
    this.lastService,
  });
}

class RifleMaintenanceSnapshot {
  final Rifle rifle;
  final int totalRounds;
  final int barrelRounds;
  final List<MaintenanceReminderStatus> statuses;
  final RifleServiceEntry? lastService;

  const RifleMaintenanceSnapshot({
    required this.rifle,
    required this.totalRounds,
    required this.barrelRounds,
    required this.statuses,
    required this.lastService,
  });

  int get overdueCount => statuses
      .where((status) => status.status == MaintenanceDueStatus.overdue)
      .length;

  int get dueSoonCount => statuses
      .where((status) => status.status == MaintenanceDueStatus.dueSoon)
      .length;

  MaintenanceDueStatus get overallStatus {
    if (overdueCount > 0) return MaintenanceDueStatus.overdue;
    if (dueSoonCount > 0) return MaintenanceDueStatus.dueSoon;
    return MaintenanceDueStatus.good;
  }
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
  final int barrelRoundCount;
  final DateTime? barrelInstalledDate;
  final String barrelNotes;

  final List<RifleServiceEntry> services;
  final List<MaintenanceReminderRule> maintenanceRules;

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
    this.barrelRoundCount = 0,
    this.barrelInstalledDate,
    this.barrelNotes = '',
    this.services = const [],
    this.maintenanceRules = const [],
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
    int? barrelRoundCount,
    DateTime? barrelInstalledDate,
    String? barrelNotes,
    List<RifleServiceEntry>? services,
    List<MaintenanceReminderRule>? maintenanceRules,
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
      barrelRoundCount: barrelRoundCount ?? this.barrelRoundCount,
      barrelInstalledDate: barrelInstalledDate ?? this.barrelInstalledDate,
      barrelNotes: barrelNotes ?? this.barrelNotes,
      services: services ?? this.services,
      maintenanceRules: maintenanceRules ?? this.maintenanceRules,
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

class RifleServiceEntry {
  final String id;
  final String service;
  final DateTime date;
  final int roundsAtService;
  final String notes;
  final MaintenanceTaskType taskType;

  const RifleServiceEntry({
    required this.id,
    required this.service,
    required this.date,
    required this.roundsAtService,
    required this.notes,
    this.taskType = MaintenanceTaskType.general,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'service': service,
    'date': date.toIso8601String(),
    'roundsAtService': roundsAtService,
    'notes': notes,
    'taskType': taskType.name,
  };

  factory RifleServiceEntry.fromMap(Map<String, dynamic> map) {
    final rawDate = map['date'];
    DateTime parsedDate;
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else if (rawDate is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
    } else if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else {
      parsedDate = DateTime.now();
    }

    final rawRounds = map['roundsAtService'];
    final rounds = (rawRounds is num)
        ? rawRounds.toInt()
        : int.tryParse('$rawRounds') ?? 0;

    return RifleServiceEntry(
      id: (map['id'] ?? '').toString(),
      service: (map['service'] ?? '').toString(),
      date: parsedDate,
      roundsAtService: rounds,
      notes: (map['notes'] ?? '').toString(),
      taskType: MaintenanceTaskType.values.firstWhere(
        (value) =>
            value.name ==
            (map['taskType'] ?? MaintenanceTaskType.general.name).toString(),
        orElse: () => MaintenanceTaskType.general,
      ),
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
  final List<String> externalMemberIdentifiers;
  final DateTime dateTime;
  final String locationName;
  final String folderName;
  final bool archived;
  final String notes;
  final bool shareNotesWithMembers;
  final bool shareTrainingDopeWithMembers;
  final bool shareLocationWithMembers;
  final bool sharePhotosWithMembers;
  final bool shareShotResultsWithMembers;
  final bool shareTimerDataWithMembers;

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
  final int? confirmedShotCount;
  final bool shotCountAppliedToRifle;
  final DateTime? endedAt;
  final int? shotTimerElapsedMs;
  final int? shotTimerFirstShotMs;
  final List<int> shotTimerSplitMs;
  final List<SessionTimerRun> timerRuns;

  static const Object _unsetDateTime = Object();

  TrainingSession({
    required this.id,
    required this.userId,
    required this.memberUserIds,
    this.externalMemberIdentifiers = const [],
    required this.dateTime,
    required this.locationName,
    this.folderName = '',
    this.archived = false,
    required this.notes,
    this.shareNotesWithMembers = true,
    this.shareTrainingDopeWithMembers = true,
    this.shareLocationWithMembers = true,
    this.sharePhotosWithMembers = true,
    this.shareShotResultsWithMembers = true,
    this.shareTimerDataWithMembers = true,
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
    this.confirmedShotCount,
    this.shotCountAppliedToRifle = false,
    this.endedAt,
    this.shotTimerElapsedMs,
    this.shotTimerFirstShotMs,
    this.shotTimerSplitMs = const [],
    this.timerRuns = const [],
  });

  TrainingSession copyWith({
    String? userId,
    List<String>? memberUserIds,
    List<String>? externalMemberIdentifiers,
    DateTime? dateTime,
    String? locationName,
    String? folderName,
    bool? archived,
    String? notes,
    bool? shareNotesWithMembers,
    bool? shareTrainingDopeWithMembers,
    bool? shareLocationWithMembers,
    bool? sharePhotosWithMembers,
    bool? shareShotResultsWithMembers,
    bool? shareTimerDataWithMembers,
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
    int? confirmedShotCount,
    bool? shotCountAppliedToRifle,
    Object? endedAt = _unsetDateTime,
    int? shotTimerElapsedMs,
    int? shotTimerFirstShotMs,
    List<int>? shotTimerSplitMs,
    List<SessionTimerRun>? timerRuns,
  }) {
    return TrainingSession(
      id: id,
      userId: userId ?? this.userId,
      memberUserIds: memberUserIds ?? this.memberUserIds,
      externalMemberIdentifiers:
          externalMemberIdentifiers ?? this.externalMemberIdentifiers,
      dateTime: dateTime ?? this.dateTime,
      locationName: locationName ?? this.locationName,
      folderName: folderName ?? this.folderName,
      archived: archived ?? this.archived,
      notes: notes ?? this.notes,
      shareNotesWithMembers:
          shareNotesWithMembers ?? this.shareNotesWithMembers,
      shareTrainingDopeWithMembers:
          shareTrainingDopeWithMembers ?? this.shareTrainingDopeWithMembers,
      shareLocationWithMembers:
          shareLocationWithMembers ?? this.shareLocationWithMembers,
      sharePhotosWithMembers:
          sharePhotosWithMembers ?? this.sharePhotosWithMembers,
      shareShotResultsWithMembers:
          shareShotResultsWithMembers ?? this.shareShotResultsWithMembers,
      shareTimerDataWithMembers:
          shareTimerDataWithMembers ?? this.shareTimerDataWithMembers,
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
      confirmedShotCount: confirmedShotCount ?? this.confirmedShotCount,
      shotCountAppliedToRifle:
          shotCountAppliedToRifle ?? this.shotCountAppliedToRifle,
      endedAt: endedAt == _unsetDateTime ? this.endedAt : endedAt as DateTime?,
      shotTimerElapsedMs: shotTimerElapsedMs ?? this.shotTimerElapsedMs,
      shotTimerFirstShotMs: shotTimerFirstShotMs ?? this.shotTimerFirstShotMs,
      shotTimerSplitMs: shotTimerSplitMs ?? this.shotTimerSplitMs,
      timerRuns: timerRuns ?? this.timerRuns,
    );
  }
}

class SessionTimerRun {
  final String id;
  final DateTime time;
  final int elapsedMs;
  final int firstShotMs;
  final List<int> splitMs;
  final int startDelayMs;
  final int goalMs;

  const SessionTimerRun({
    required this.id,
    required this.time,
    required this.elapsedMs,
    required this.firstShotMs,
    required this.splitMs,
    this.startDelayMs = 0,
    this.goalMs = 0,
  });
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

  /// Impact offset (Right + / Left -) in the selected unit.
  final double? offsetX;

  /// Impact offset (Up + / Down -) in the selected unit.
  final double? offsetY;

  /// Unit for offsetX/offsetY: 'in', 'moa', or 'mil'.
  final String offsetUnit;

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
    this.offsetX,
    this.offsetY,
    this.offsetUnit = 'in',
    required this.photos,
  });

  ShotEntry copyWith({
    DateTime? time,
    bool? isColdBore,
    bool? isBaseline,
    String? distance,
    String? result,
    String? notes,
    double? offsetX,
    double? offsetY,
    String? offsetUnit,
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
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      offsetUnit: offsetUnit ?? this.offsetUnit,
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

  PhotoNote({required this.id, required this.time, required this.caption});
}

class _ColdBoreRow {
  final TrainingSession session;
  final ShotEntry shot;
  final Rifle? rifle;
  final AmmoLot? ammo;
  final String? stringId;
  _ColdBoreRow({
    required this.session,
    required this.shot,
    required this.rifle,
    required this.ammo,
    required this.stringId,
  });
}

///
/// Screens
///

class AudioCounterScreen extends StatefulWidget {
  final AppState state;
  const AudioCounterScreen({super.key, required this.state});

  @override
  State<AudioCounterScreen> createState() => _AudioCounterScreenState();
}

class _AudioCounterScreenState extends State<AudioCounterScreen> {
  bool _isListening = false;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  double _latestDb = 0;
  int _totalShotsDetected = 0;
  String? _selectedRifleId;
  double _audioThresholdDb = 92;
  DateTime? _lastShotAt;
  bool _applyToRifleOnDetection = false;
  String? _statusMessage;

  bool get _audioSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    if (widget.state.rifles.isNotEmpty) {
      _selectedRifleId =
          widget.state.shotTimerSelectedRifleId ?? widget.state.rifles.first.id;
    }
    _audioThresholdDb = widget.state.audioThresholdDb;
  }

  @override
  void dispose() {
    _noiseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleAudioListener(bool enable) async {
    if (!_audioSupported) {
      setState(() {
        _isListening = false;
        _statusMessage = 'Audio counter available on iPhone and Android only.';
      });
      return;
    }

    if (!enable) {
      await _noiseSubscription?.cancel();
      _noiseSubscription = null;
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _latestDb = 0;
        _statusMessage = null;
      });
      return;
    }

    try {
      await _noiseSubscription?.cancel();
      _noiseSubscription = NoiseMeter().noise.listen(
        (reading) {
          if (!mounted) return;
          final maxDb = reading.maxDecibel;
          final now = DateTime.now();
          final shouldMark =
              _isListening &&
              maxDb >= _audioThresholdDb &&
              (_lastShotAt == null ||
                  now.difference(_lastShotAt!).inMilliseconds >= 250);

          setState(() {
            _latestDb = maxDb;
            if (shouldMark) {
              _lastShotAt = now;
              _totalShotsDetected += 1;
              if (_applyToRifleOnDetection && _selectedRifleId != null) {
                widget.state.addRifleRounds(
                  rifleId: _selectedRifleId!,
                  roundCount: 1,
                );
              }
            }
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _statusMessage =
                'Microphone unavailable. Check permissions and try again.';
          });
        },
        cancelOnError: true,
      );
      if (!mounted) return;
      setState(() {
        _isListening = true;
        _statusMessage = 'Listening for shots...';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _statusMessage =
            'Microphone unavailable. Check permissions and try again.';
      });
    }
  }

  void _applyDetectedShotsToRifle() {
    if (_totalShotsDetected <= 0 || _selectedRifleId == null) return;
    widget.state.addRifleRounds(
      rifleId: _selectedRifleId!,
      roundCount: _totalShotsDetected,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied $_totalShotsDetected shots to rifle')),
    );
    setState(() => _totalShotsDetected = 0);
  }

  void _resetCounter() {
    setState(() => _totalShotsDetected = 0);
  }

  String _rifleDropdownLabel(Rifle rifle) {
    final name = (rifle.name ?? '').trim();
    if (name.isNotEmpty) return name;
    final modelBits = [
      (rifle.manufacturer ?? '').trim(),
      (rifle.model ?? '').trim(),
    ].where((v) => v.isNotEmpty).toList();
    if (modelBits.isNotEmpty) return modelBits.join(' ');
    return rifle.caliber.trim().isEmpty ? 'Rifle' : rifle.caliber.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Shot Counter')),
      body: AnimatedBuilder(
        animation: widget.state,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Standalone Audio Counter',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (_isListening)
                            const Chip(
                              label: Text('Listening'),
                              avatar: Icon(Icons.mic, size: 18),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Shots detected: $_totalShotsDetected',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Live level: ${_latestDb.toStringAsFixed(1)} dB',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.state.rifles.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedRifleId,
                          decoration: const InputDecoration(
                            labelText: 'Target Rifle',
                          ),
                          items: widget.state.rifles
                              .map(
                                (rifle) => DropdownMenuItem(
                                  value: rifle.id,
                                  child: Text(_rifleDropdownLabel(rifle)),
                                ),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _selectedRifleId = val),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Apply shots immediately'),
                        subtitle: const Text(
                          'Auto-increment rifle round count as shots are detected',
                        ),
                        value: _applyToRifleOnDetection,
                        onChanged: (v) =>
                            setState(() => _applyToRifleOnDetection = v),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Detection threshold',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                      Slider(
                        value: _audioThresholdDb,
                        min: 70,
                        max: 120,
                        divisions: 50,
                        label: '${_audioThresholdDb.toStringAsFixed(0)} dB',
                        onChanged: _isListening
                            ? (value) {
                                setState(() => _audioThresholdDb = value);
                                widget.state.setAudioThresholdDb(value);
                              }
                            : null,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () =>
                                _toggleAudioListener(!_isListening),
                            icon: Icon(
                              _isListening
                                  ? Icons.stop_circle_outlined
                                  : Icons.mic_outlined,
                            ),
                            label: Text(
                              _isListening
                                  ? 'Stop Listening'
                                  : 'Start Listening',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _totalShotsDetected > 0
                                ? _resetCounter
                                : null,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reset'),
                          ),
                          if (_totalShotsDetected > 0 &&
                              _selectedRifleId != null)
                            FilledButton.icon(
                              onPressed: _applyDetectedShotsToRifle,
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text('Apply $_totalShotsDetected shots'),
                            ),
                        ],
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 12),
                        Chip(label: Text(_statusMessage!)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'How to use',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. Select your rifle\n'
                        '2. Adjust threshold for your range noise level\n'
                        '3. Start listening\n'
                        '4. Fire shots - loud impulses above threshold will auto-detect\n'
                        '5. Tap "Apply shots" to add count to rifle round total\n'
                        'Or enable "Apply shots immediately" to auto-increment as detected.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GuidedTourStep {
  final int tabIndex;
  final IconData icon;
  final String title;
  final String description;

  const _GuidedTourStep({
    required this.tabIndex,
    required this.icon,
    required this.title,
    required this.description,
  });
}

class HomeShell extends StatefulWidget {
  final AppState state;
  final CloudSyncService cloud;
  final bool startGuidedTour;
  final bool promptUniqueIdentifierOnLaunch;
  final bool cloudRecoverySupported;
  final Future<DateTime?> Function()? readLastCloudBackupAt;
  final Future<DateTime?> Function()? readLastCloudRestoreAt;
  final Future<void> Function()? backupNow;
  final Future<bool> Function()? restoreFromCloud;
  const HomeShell({
    super.key,
    required this.state,
    required this.cloud,
    this.startGuidedTour = false,
    this.promptUniqueIdentifierOnLaunch = false,
    this.cloudRecoverySupported = false,
    this.readLastCloudBackupAt,
    this.readLastCloudRestoreAt,
    this.backupNow,
    this.restoreFromCloud,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _tourActive = false;
  int _tourStepIndex = 0;
  bool _didAutoStartTour = false;
  bool _firstRunIdentifierPromptInFlight = false;
  bool _sharedAcceptancePromptInFlight = false;
  bool _incomingSharedImportPromptInFlight = false;

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          state: widget.state,
          cloudRecoverySupported: widget.cloudRecoverySupported,
          readLastCloudBackupAt: widget.readLastCloudBackupAt,
          readLastCloudRestoreAt: widget.readLastCloudRestoreAt,
          backupNow: widget.backupNow,
          restoreFromCloud: widget.restoreFromCloud,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  static const List<_GuidedTourStep> _tourSteps = [
    _GuidedTourStep(
      tabIndex: 0,
      icon: Icons.event_note_outlined,
      title: 'Sessions',
      description:
          'Create, organize, and review sessions. You can now edit session start/end date and time from the session screen if you forgot to close one.',
    ),
    _GuidedTourStep(
      tabIndex: 1,
      icon: Icons.ac_unit_outlined,
      title: 'Cold Bore',
      description:
          'Track first-shot performance, baseline cold-bore shots, and attached photos to monitor zero confidence over time.',
    ),
    _GuidedTourStep(
      tabIndex: 2,
      icon: Icons.timer_outlined,
      title: 'Shot Timer',
      description:
          'Run drills with delayed start and timing controls for pacing and consistency.',
    ),
    _GuidedTourStep(
      tabIndex: 3,
      icon: Icons.mic_outlined,
      title: 'Audio Counter',
      description:
          'Detect shots by sound and apply counted rounds to your selected rifle automatically or on demand.',
    ),
    _GuidedTourStep(
      tabIndex: 4,
      icon: Icons.build_outlined,
      title: 'Gear',
      description:
          'Manage rifles, ammo lots, and maintenance reminders so analytics stay accurate.',
    ),
    _GuidedTourStep(
      tabIndex: 5,
      icon: Icons.list_alt_outlined,
      title: 'Data',
      description:
          'Review quick-reference DOPE (rifle-only + rifle+ammo), working DOPE, and maintenance status in one place.',
    ),
    _GuidedTourStep(
      tabIndex: 6,
      icon: Icons.ios_share_outlined,
      title: 'Export',
      description:
          'Create PDF reports and share sessions with per-field privacy controls (notes, DOPE, location, photos, shots, timer). Shared sessions auto-populate to devices with matching user identifiers, and recipients get a first-time prompt to choose which shared fields they accept per session.',
    ),
    _GuidedTourStep(
      tabIndex: 0,
      icon: Icons.settings_outlined,
      title: 'Settings',
      description:
          'Use Settings for Cloud Backup & Restore, manual JSON backup files, appearance mode, purchases/restores, trial and subscription status, and user management.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_maybePromptForNewSharedSession);
    widget.state.addListener(_maybePromptForIncomingSharedImport);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _runFirstLaunchPrompts(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybePromptForNewSharedSession(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybePromptForIncomingSharedImport(),
    );
  }

  @override
  void dispose() {
    widget.state.removeListener(_maybePromptForNewSharedSession);
    widget.state.removeListener(_maybePromptForIncomingSharedImport);
    super.dispose();
  }

  Future<void> _runFirstLaunchPrompts() async {
    await _promptForUniqueIdentifierIfNeeded();
    if (!mounted || !widget.startGuidedTour || _didAutoStartTour) return;
    _didAutoStartTour = true;
    _startGuidedTour();
  }

  Future<void> _promptForUniqueIdentifierIfNeeded() async {
    if (!mounted ||
        _firstRunIdentifierPromptInFlight ||
        !widget.promptUniqueIdentifierOnLaunch) {
      return;
    }

    final activeUser = widget.state.activeUser;
    if (activeUser == null || !_isSeedUserIdentifier(activeUser.identifier)) {
      return;
    }

    _firstRunIdentifierPromptInFlight = true;
    final result = await showDialog<_UniqueIdentifierResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _UniqueIdentifierPromptDialog(),
    );

    if (result != null) {
      widget.state.updateUserProfile(
        userId: activeUser.id,
        name: result.name,
        identifier: result.identifier,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User identifier saved. Partner sharing is now ready.'),
        ),
      );
    }

    _firstRunIdentifierPromptInFlight = false;
  }

  void _maybePromptForIncomingSharedImport() {
    if (!mounted || _incomingSharedImportPromptInFlight) return;

    final jsonText = widget.state.takeNextPendingIncomingSharedJson();
    if (jsonText == null) return;

    final preview = _IncomingSharedSessionPayload.tryParse(jsonText);
    if (preview == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Received file is not a valid shared session.'),
          ),
        );
      });
      return;
    }

    _incomingSharedImportPromptInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _incomingSharedImportPromptInFlight = false;
        return;
      }

      var acceptNotes = preview.session.shareNotesWithMembers;
      var acceptTrainingDope = preview.session.shareTrainingDopeWithMembers;
      var acceptLocation = preview.session.shareLocationWithMembers;
      var acceptPhotos = preview.session.sharePhotosWithMembers;
      var acceptShotResults = preview.session.shareShotResultsWithMembers;
      var acceptTimerData = preview.session.shareTimerDataWithMembers;
      var approved = false;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Accept shared session?'),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          preview.session.locationName.trim().isEmpty
                              ? 'A Cold Bore session was shared with this device.'
                              : 'Session: ${preview.session.locationName.trim()}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Shared by: ${preview.ownerIdentifier.isEmpty ? 'UNKNOWN' : preview.ownerIdentifier}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Choose what you want to receive.'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept notes'),
                        subtitle: preview.session.shareNotesWithMembers
                            ? null
                            : const Text('Sender did not share this field.'),
                        value:
                            preview.session.shareNotesWithMembers &&
                            acceptNotes,
                        onChanged: preview.session.shareNotesWithMembers
                            ? (v) => setState(() => acceptNotes = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept training DOPE'),
                        subtitle: preview.session.shareTrainingDopeWithMembers
                            ? null
                            : const Text('Sender did not share this field.'),
                        value:
                            preview.session.shareTrainingDopeWithMembers &&
                            acceptTrainingDope,
                        onChanged: preview.session.shareTrainingDopeWithMembers
                            ? (v) => setState(() => acceptTrainingDope = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept location and GPS'),
                        subtitle: preview.session.shareLocationWithMembers
                            ? null
                            : const Text('Sender did not share this field.'),
                        value:
                            preview.session.shareLocationWithMembers &&
                            acceptLocation,
                        onChanged: preview.session.shareLocationWithMembers
                            ? (v) => setState(() => acceptLocation = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept photos and photo notes'),
                        subtitle: preview.session.sharePhotosWithMembers
                            ? null
                            : const Text('Sender did not share this field.'),
                        value:
                            preview.session.sharePhotosWithMembers &&
                            acceptPhotos,
                        onChanged: preview.session.sharePhotosWithMembers
                            ? (v) => setState(() => acceptPhotos = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept shot results'),
                        subtitle: preview.session.shareShotResultsWithMembers
                            ? null
                            : const Text('Sender did not share this field.'),
                        value:
                            preview.session.shareShotResultsWithMembers &&
                            acceptShotResults,
                        onChanged: preview.session.shareShotResultsWithMembers
                            ? (v) => setState(() => acceptShotResults = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept timer data'),
                        subtitle: preview.session.shareTimerDataWithMembers
                            ? null
                            : const Text('Sender did not share this field.'),
                        value:
                            preview.session.shareTimerDataWithMembers &&
                            acceptTimerData,
                        onChanged: preview.session.shareTimerDataWithMembers
                            ? (v) => setState(() => acceptTimerData = v)
                            : null,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Decline'),
                  ),
                  FilledButton(
                    onPressed: () {
                      approved = true;
                      Navigator.of(dialogCtx).pop();
                    },
                    child: const Text('Accept'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (approved) {
        widget.state.importSharedSessionJson(
          jsonText,
          acceptNotes: acceptNotes,
          acceptTrainingDope: acceptTrainingDope,
          acceptLocation: acceptLocation,
          acceptPhotos: acceptPhotos,
          acceptShotResults: acceptShotResults,
          acceptTimerData: acceptTimerData,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shared session accepted.')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shared session declined.')),
        );
      }

      _incomingSharedImportPromptInFlight = false;
      if (!mounted) return;
      _maybePromptForIncomingSharedImport();
      _maybePromptForNewSharedSession();
    });
  }

  void _startGuidedTour() {
    setState(() {
      _tourActive = true;
      _tourStepIndex = 0;
      _tab = _tourSteps.first.tabIndex;
    });
  }

  void _stopGuidedTour() {
    setState(() => _tourActive = false);
  }

  void _nextTourStep() {
    if (_tourStepIndex >= _tourSteps.length - 1) {
      _stopGuidedTour();
      return;
    }
    setState(() {
      _tourStepIndex += 1;
      _tab = _tourSteps[_tourStepIndex].tabIndex;
    });
  }

  void _prevTourStep() {
    if (_tourStepIndex == 0) return;
    setState(() {
      _tourStepIndex -= 1;
      _tab = _tourSteps[_tourStepIndex].tabIndex;
    });
  }

  void _maybePromptForNewSharedSession() {
    if (!mounted || _sharedAcceptancePromptInFlight) return;

    final nextSessionId = widget.state
        .takeNextPendingSharedAcceptancePromptSessionId();
    if (nextSessionId == null) return;

    final session = widget.state.getSessionById(nextSessionId);
    final activeUser = widget.state.activeUser;
    if (session == null ||
        activeUser == null ||
        session.userId == activeUser.id) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybePromptForNewSharedSession(),
      );
      return;
    }

    _sharedAcceptancePromptInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _sharedAcceptancePromptInFlight = false;
        return;
      }

      final ownerIdentifier = (() {
        try {
          return widget.state.users
              .firstWhere((u) => u.id == session.userId)
              .identifier;
        } catch (_) {
          return 'UNKNOWN';
        }
      })();

      final accepted = widget.state.sharedFieldAcceptanceForSession(session.id);
      var acceptNotes = accepted[AppState.sharedFieldNotes] == true;
      var acceptTrainingDope =
          accepted[AppState.sharedFieldTrainingDope] == true;
      var acceptLocation = accepted[AppState.sharedFieldLocation] == true;
      var acceptPhotos = accepted[AppState.sharedFieldPhotos] == true;
      var acceptShotResults = accepted[AppState.sharedFieldShotResults] == true;
      var acceptTimerData = accepted[AppState.sharedFieldTimerData] == true;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('New shared session received'),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Choose what you want to accept for this session.',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Shared by: $ownerIdentifier',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept notes'),
                        subtitle: session.shareNotesWithMembers
                            ? null
                            : const Text('Owner did not share this field.'),
                        value: session.shareNotesWithMembers && acceptNotes,
                        onChanged: session.shareNotesWithMembers
                            ? (v) => setState(() => acceptNotes = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept training DOPE'),
                        subtitle: session.shareTrainingDopeWithMembers
                            ? null
                            : const Text('Owner did not share this field.'),
                        value:
                            session.shareTrainingDopeWithMembers &&
                            acceptTrainingDope,
                        onChanged: session.shareTrainingDopeWithMembers
                            ? (v) => setState(() => acceptTrainingDope = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept location and GPS'),
                        subtitle: session.shareLocationWithMembers
                            ? null
                            : const Text('Owner did not share this field.'),
                        value:
                            session.shareLocationWithMembers && acceptLocation,
                        onChanged: session.shareLocationWithMembers
                            ? (v) => setState(() => acceptLocation = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept photos and photo notes'),
                        subtitle: session.sharePhotosWithMembers
                            ? null
                            : const Text('Owner did not share this field.'),
                        value: session.sharePhotosWithMembers && acceptPhotos,
                        onChanged: session.sharePhotosWithMembers
                            ? (v) => setState(() => acceptPhotos = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept shot results'),
                        subtitle: session.shareShotResultsWithMembers
                            ? null
                            : const Text('Owner did not share this field.'),
                        value:
                            session.shareShotResultsWithMembers &&
                            acceptShotResults,
                        onChanged: session.shareShotResultsWithMembers
                            ? (v) => setState(() => acceptShotResults = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept timer data'),
                        subtitle: session.shareTimerDataWithMembers
                            ? null
                            : const Text('Owner did not share this field.'),
                        value:
                            session.shareTimerDataWithMembers &&
                            acceptTimerData,
                        onChanged: session.shareTimerDataWithMembers
                            ? (v) => setState(() => acceptTimerData = v)
                            : null,
                      ),
                    ],
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      widget.state.setSessionAcceptedSharedFields(
                        sessionId: session.id,
                        acceptNotes: session.shareNotesWithMembers
                            ? acceptNotes
                            : false,
                        acceptTrainingDope: session.shareTrainingDopeWithMembers
                            ? acceptTrainingDope
                            : false,
                        acceptLocation: session.shareLocationWithMembers
                            ? acceptLocation
                            : false,
                        acceptPhotos: session.sharePhotosWithMembers
                            ? acceptPhotos
                            : false,
                        acceptShotResults: session.shareShotResultsWithMembers
                            ? acceptShotResults
                            : false,
                        acceptTimerData: session.shareTimerDataWithMembers
                            ? acceptTimerData
                            : false,
                      );
                      Navigator.of(dialogCtx).pop();
                    },
                    child: const Text('Save choices'),
                  ),
                ],
              );
            },
          );
        },
      );

      _sharedAcceptancePromptInFlight = false;
      if (!mounted) return;
      _maybePromptForNewSharedSession();
    });
  }

  Widget _buildTourOverlay(BuildContext context) {
    if (!_tourActive) return const SizedBox.shrink();
    final step = _tourSteps[_tourStepIndex];
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Spacer(),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(step.icon),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Guided Tour: ${step.title}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: _stopGuidedTour,
                              child: const Text('Skip'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(step.description),
                        const SizedBox(height: 12),
                        Text(
                          'Step ${_tourStepIndex + 1} of ${_tourSteps.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: (_tourStepIndex + 1) / _tourSteps.length,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _tourStepIndex == 0
                                    ? null
                                    : _prevTourStep,
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Back'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _nextTourStep,
                                icon: Icon(
                                  _tourStepIndex == _tourSteps.length - 1
                                      ? Icons.check
                                      : Icons.arrow_forward,
                                ),
                                label: Text(
                                  _tourStepIndex == _tourSteps.length - 1
                                      ? 'Finish'
                                      : 'Next',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      SessionsScreen(state: widget.state),
      ColdBoreScreen(state: widget.state),
      ShotTimerToolScreen(state: widget.state),
      AudioCounterScreen(state: widget.state),
      EquipmentScreen(state: widget.state),
      DataScreen(state: widget.state),
      ExportPlaceholderScreen(state: widget.state),
    ];

    return AnimatedBuilder(
      animation: Listenable.merge([widget.state, widget.cloud]),
      builder: (context, _) {
        final user = widget.state.activeUser;
        final cloudReady = widget.cloud.canSync;
        final cloudError = widget.cloud.lastError;

        return Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text('Cold Bore'),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message:
                          cloudError != null && cloudError.trim().isNotEmpty
                          ? 'Sync error: $cloudError'
                          : (cloudReady
                                ? 'Cloud sync connected'
                                : 'Cloud sync not configured'),
                      child: Icon(
                        cloudError != null && cloudError.trim().isNotEmpty
                            ? Icons.cloud_off_outlined
                            : (cloudReady
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_queue_outlined),
                        color:
                            cloudError != null && cloudError.trim().isNotEmpty
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                  if (user != null && !_isSeedUserIdentifier(user.identifier))
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
                    tooltip: 'Tutorial',
                    onPressed: _startGuidedTour,
                    icon: const Icon(Icons.help_outline),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              body: pages[_tab],
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.event_note_outlined),
                    label: 'Session',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.ac_unit_outlined),
                    label: 'Bore',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.timer_outlined),
                    label: 'Timer',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.mic_outlined),
                    label: 'Audio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.build_outlined),
                    label: 'Gear',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.list_alt_outlined),
                    label: 'Data',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.ios_share_outlined),
                    label: 'Export',
                  ),
                ],
              ),
            ),
            _buildTourOverlay(context),
          ],
        );
      },
    );
  }
}

class _IncomingSharedSessionPayload {
  final String jsonText;
  final String ownerIdentifier;
  final TrainingSession session;

  const _IncomingSharedSessionPayload({
    required this.jsonText,
    required this.ownerIdentifier,
    required this.session,
  });

  static _IncomingSharedSessionPayload? tryParse(String jsonText) {
    try {
      final decoded = json.decode(jsonText);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if ((map['exportType'] ?? '').toString().trim() != 'sharedSession') {
        return null;
      }
      final sessionRaw = map['session'];
      if (sessionRaw is! Map) return null;
      return _IncomingSharedSessionPayload(
        jsonText: jsonText,
        ownerIdentifier: (map['ownerIdentifier'] ?? '').toString().trim(),
        session: _trainingSessionFromMap(Map<String, dynamic>.from(sessionRaw)),
      );
    } catch (_) {
      return null;
    }
  }
}

class SettingsScreen extends StatefulWidget {
  final AppState state;
  final bool cloudRecoverySupported;
  final Future<DateTime?> Function()? readLastCloudBackupAt;
  final Future<DateTime?> Function()? readLastCloudRestoreAt;
  final Future<void> Function()? backupNow;
  final Future<bool> Function()? restoreFromCloud;

  const SettingsScreen({
    super.key,
    required this.state,
    this.cloudRecoverySupported = false,
    this.readLastCloudBackupAt,
    this.readLastCloudRestoreAt,
    this.backupNow,
    this.restoreFromCloud,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SubscriptionService _sub = SubscriptionService();
  final AppThemeController _theme = AppThemeController();
  final CloudSyncService _cloud = CloudSyncService();
  String _versionText = '';
  DateTime? _lastCloudBackupAt;
  DateTime? _lastCloudRestoreAt;
  bool _cloudBusy = false;
  late final VoidCallback _subListener;
  late final VoidCallback _themeListener;
  late final VoidCallback _cloudListener;

  bool get _hasMeaningfulLocalData {
    return widget.state.rifles.isNotEmpty ||
        widget.state.ammoLots.isNotEmpty ||
        widget.state.allSessions.isNotEmpty;
  }

  bool get _isBackupOverdue {
    if (_lastCloudBackupAt == null) return _hasMeaningfulLocalData;
    return DateTime.now().difference(_lastCloudBackupAt!) >
        const Duration(days: 7);
  }

  String get _backupHealthText {
    if (_lastCloudBackupAt == null) {
      return _hasMeaningfulLocalData
          ? 'Backup recommended now. No successful cloud backup found yet.'
          : 'No backup needed yet. Create data first, then back up.';
    }
    final age = DateTime.now().difference(_lastCloudBackupAt!);
    if (age > const Duration(days: 7)) {
      return 'Backup overdue. Last backup was ${age.inDays} days ago.';
    }
    return 'Backup healthy. Last backup ${age.inHours}h ago.';
  }

  @override
  void initState() {
    super.initState();
    _subListener = () {
      if (!mounted) return;
      setState(() {});
    };
    _themeListener = () {
      if (!mounted) return;
      setState(() {});
    };
    _cloudListener = () {
      if (!mounted) return;
      setState(() {});
    };
    _sub.addListener(_subListener);
    _theme.addListener(_themeListener);
    _cloud.addListener(_cloudListener);
    unawaited(_loadVersion());
    unawaited(_loadCloudBackupStatus());
  }

  @override
  void dispose() {
    _sub.removeListener(_subListener);
    _theme.removeListener(_themeListener);
    _cloud.removeListener(_cloudListener);
    super.dispose();
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Day';
      case ThemeMode.dark:
        return 'Night';
      case ThemeMode.system:
        return 'Auto';
    }
  }

  Future<void> _pickThemeMode() async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (ctx) {
        final current = _theme.mode;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Theme mode')),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                groupValue: current,
                title: const Text('Day'),
                onChanged: (value) => Navigator.of(ctx).pop(value),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: current,
                title: const Text('Night'),
                onChanged: (value) => Navigator.of(ctx).pop(value),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                groupValue: current,
                title: const Text('Auto (system)'),
                onChanged: (value) => Navigator.of(ctx).pop(value),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null) return;
    await _theme.setMode(selected);
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionText = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionText = 'Unavailable');
    }
  }

  Future<void> _restorePurchases() async {
    await _sub.restorePurchases();
    if (!mounted) return;
    final message = _sub.isEntitled
        ? 'Purchase restored. Full access enabled.'
        : 'No active subscription found for this Apple ID.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCloudBackupStatus() async {
    final reader = widget.readLastCloudBackupAt;
    final restoreReader = widget.readLastCloudRestoreAt;
    if (reader == null && restoreReader == null) return;
    try {
      final value = reader == null ? null : await reader();
      final restoreValue = restoreReader == null ? null : await restoreReader();
      if (!mounted) return;
      setState(() {
        _lastCloudBackupAt = value;
        _lastCloudRestoreAt = restoreValue;
      });
    } catch (_) {}
  }

  Future<void> _backupNow() async {
    final backup = widget.backupNow;
    if (backup == null) return;
    setState(() => _cloudBusy = true);
    try {
      await backup();
      await _loadCloudBackupStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cloud backup completed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cloud backup failed: $e')));
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _restoreFromCloud() async {
    final restore = widget.restoreFromCloud;
    if (restore == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from cloud backup?'),
        content: const Text(
          'This replaces current local data on this device with your latest cloud backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cloudBusy = true);
    try {
      final didRestore = await restore();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            didRestore
                ? 'Cloud restore completed.'
                : 'No cloud backup found yet for this Apple ID. Open the old phone, tap Back up now, then retry Restore on this device after 1-2 minutes.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cloud restore failed: $e')));
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entitlementText = _sub.hasTesterAccess
        ? 'Tester access enabled - full access unlocked.'
        : (_sub.isEntitled
              ? 'Active - full access enabled.'
              : 'Read-only mode - upgrade to add new data.');

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: const Text('Cloud Backup & Restore'),
              subtitle: Text(
                widget.cloudRecoverySupported
                    ? (_lastCloudBackupAt == null
                          ? 'Automatic iCloud backup is enabled. No completed backup yet.'
                          : 'Last backup: ${_fmtDateTime(_lastCloudBackupAt!)}'
                                '${_lastCloudRestoreAt == null ? '' : '\nLast restore: ${_fmtDateTime(_lastCloudRestoreAt!)}'}')
                    : 'Automatic cloud recovery is currently available on iPhone.',
              ),
            ),
          ),
          if (widget.cloudRecoverySupported && _isBackupOverdue)
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: const Text('Backup health warning'),
                subtitle: Text(_backupHealthText),
                trailing: TextButton(
                  onPressed: _cloudBusy ? null : _backupNow,
                  child: const Text('Back up now'),
                ),
              ),
            ),
          if (widget.cloudRecoverySupported && !_isBackupOverdue)
            Card(
              child: ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Backup health'),
                subtitle: Text(_backupHealthText),
              ),
            ),
          if (widget.cloudRecoverySupported)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cloudBusy ? null : _backupNow,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Back up now'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _cloudBusy ? null : _restoreFromCloud,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Restore'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: Icon(
                _cloud.lastError != null && _cloud.lastError!.trim().isNotEmpty
                    ? Icons.cloud_off_outlined
                    : (_cloud.canSync
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_queue_outlined),
              ),
              title: const Text('Session sync status'),
              subtitle: Text(
                _cloud.lastError != null && _cloud.lastError!.trim().isNotEmpty
                    ? 'Error: ${_cloud.lastError}'
                    : (_cloud.canSync
                          ? 'Connected${_cloud.lastSyncAt == null ? '' : ' • Last sync ${_fmtDateTime(_cloud.lastSyncAt!)}'}'
                          : 'Not connected yet. Sync activates when Firebase is configured and user identifier is available.'),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('Backup files (JSON)'),
              subtitle: const Text(
                'Create or restore manual backup files from one place.',
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _BackupScreen(state: widget.state),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Appearance'),
              subtitle: Text('Theme: ${_themeModeLabel(_theme.mode)}'),
              onTap: _pickThemeMode,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Cold Bore Pro'),
              subtitle: Text(entitlementText),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const _PaywallScreen()),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.refresh_outlined),
              title: const Text('Restore purchases'),
              subtitle: const Text(
                'Use this after reinstall or new device setup.',
              ),
              onTap: _sub.loading ? null : _restorePurchases,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Manage users'),
              subtitle: const Text(
                'Switch active user or add another user profile.',
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UsersScreen(state: widget.state),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App version'),
              subtitle: Text(
                _versionText.isEmpty ? 'Loading...' : _versionText,
              ),
            ),
          ),
        ],
      ),
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
  String? _selectedRifleFilterId;
  String? _selectedAmmoFilterId;

  Map<String, Map<DistanceKey, DopeEntry>> _effectiveRifleOnlyMap() {
    final explicit = widget.state.workingDopeRifleOnly;
    final byAmmo = widget.state.workingDopeRifleAmmo;

    final merged = <String, Map<DistanceKey, DopeEntry>>{
      for (final entry in explicit.entries)
        entry.key: {for (final row in entry.value.entries) row.key: row.value},
    };

    for (final entry in byAmmo.entries) {
      final key = entry.key;
      final bucket = entry.value;
      if (bucket.isEmpty) continue;

      final sample = bucket.values.first;
      String? rifleId = sample.rifleId;
      if (rifleId == null || rifleId.isEmpty) {
        final sep = key.indexOf('_');
        if (sep > 0) {
          rifleId = key.substring(0, sep);
        }
      }
      if (rifleId == null || rifleId.isEmpty) continue;

      final target = merged.putIfAbsent(
        rifleId,
        () => <DistanceKey, DopeEntry>{},
      );
      for (final row in bucket.entries) {
        final dk = row.key;
        final incoming = row.value;
        final current = target[dk];

        // Keep explicit rifle-only values intact. If missing, prefer latest
        // derived entry for this rifle+distance from rifle+ammo buckets.
        if (explicit[rifleId]?.containsKey(dk) == true) {
          continue;
        }
        if (current == null || incoming.time.isAfter(current.time)) {
          target[dk] = incoming;
        }
      }
    }

    return merged;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final rifles = widget.state.rifles;
        final withDope = rifles.where((r) => r.dope.trim().isNotEmpty).toList();
        final wmap = _rifleOnly
            ? _effectiveRifleOnlyMap()
            : widget.state.workingDopeRifleAmmo;

        String rifleTitle(String? rifleId) {
          if (rifleId == null) return 'Unknown Rifle';
          final rifle = widget.state.rifleById(rifleId);
          if (rifle == null) return 'Deleted rifle';
          final name = (rifle.name ?? '').trim();
          if (name.isNotEmpty) return name;
          final model = [
            (rifle.manufacturer ?? '').trim(),
            (rifle.model ?? '').trim(),
          ].where((v) => v.isNotEmpty).join(' ');
          if (model.isNotEmpty) return model;
          return rifle.caliber.trim().isEmpty ? 'Rifle' : rifle.caliber.trim();
        }

        String ammoTitle(String? ammoId) {
          if (ammoId == null) return 'Unknown Ammo';
          final ammo = widget.state.ammoById(ammoId);
          if (ammo == null) return 'Deleted ammo';
          final name = (ammo.name ?? '').trim();
          if (name.isNotEmpty) return name;
          final bullet =
              '${ammo.grain > 0 ? '${ammo.grain}gr ' : ''}${ammo.bullet}'
                  .trim();
          if (bullet.isNotEmpty) return bullet;
          return ammo.caliber.trim().isEmpty ? 'Ammo' : ammo.caliber.trim();
        }

        String? bucketRifleId(String key, Map<DistanceKey, DopeEntry> inner) {
          if (_rifleOnly) return key;

          String? rifleId = inner.isNotEmpty
              ? inner.values.first.rifleId
              : null;
          if (rifleId == null || rifleId.isEmpty) {
            final sep = key.indexOf('_');
            if (sep > 0) {
              rifleId = key.substring(0, sep);
            }
          }
          return (rifleId == null || rifleId.isEmpty) ? null : rifleId;
        }

        String? bucketAmmoId(String key, Map<DistanceKey, DopeEntry> inner) {
          if (_rifleOnly) return null;

          String? ammoId = inner.isNotEmpty
              ? inner.values.first.ammoLotId
              : null;
          if (ammoId == null || ammoId.isEmpty) {
            final sep = key.indexOf('_');
            if (sep > 0 && sep < key.length - 1) {
              ammoId = key.substring(sep + 1);
            }
          }
          return (ammoId == null || ammoId.isEmpty) ? null : ammoId;
        }

        final availableRifleIds = <String>{};
        final availableAmmoIds = <String>{};
        final ammoToRifles = <String, Set<String>>{};
        for (final entry in wmap.entries) {
          final key = entry.key;
          final inner = entry.value;
          final rifleId = bucketRifleId(key, inner);
          final ammoId = bucketAmmoId(key, inner);
          if (rifleId != null) {
            availableRifleIds.add(rifleId);
          }
          if (!_rifleOnly && ammoId != null) {
            availableAmmoIds.add(ammoId);
            if (rifleId != null) {
              ammoToRifles.putIfAbsent(ammoId, () => <String>{}).add(rifleId);
            }
          }
        }

        if (_selectedRifleFilterId != null &&
            !availableRifleIds.contains(_selectedRifleFilterId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedRifleFilterId = null;
              _selectedAmmoFilterId = null;
            });
          });
        }

        if (_rifleOnly && _selectedAmmoFilterId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedAmmoFilterId = null);
          });
        } else if (!_rifleOnly && _selectedAmmoFilterId != null) {
          final selectedAmmoRifles =
              ammoToRifles[_selectedAmmoFilterId!] ?? const <String>{};
          final ammoStillValid =
              availableAmmoIds.contains(_selectedAmmoFilterId) &&
              (_selectedRifleFilterId == null ||
                  selectedAmmoRifles.contains(_selectedRifleFilterId));
          if (!ammoStillValid) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _selectedAmmoFilterId = null);
            });
          }
        }

        final rifleFilterOptions = availableRifleIds.toList()
          ..sort(
            (a, b) => rifleTitle(
              a,
            ).toLowerCase().compareTo(rifleTitle(b).toLowerCase()),
          );
        final ammoFilterOptions =
            availableAmmoIds.where((ammoId) {
              if (_selectedRifleFilterId == null) return true;
              final rifles = ammoToRifles[ammoId] ?? const <String>{};
              return rifles.contains(_selectedRifleFilterId);
            }).toList()..sort(
              (a, b) => ammoTitle(
                a,
              ).toLowerCase().compareTo(ammoTitle(b).toLowerCase()),
            );

        final workingSections = <Widget>[];
        if (wmap.isNotEmpty) {
          final sortedKeys = wmap.keys.toList()..sort();
          for (final key in sortedKeys) {
            final inner = wmap[key]!;
            final rifleIdForBucket = bucketRifleId(key, inner);
            final ammoIdForBucket = bucketAmmoId(key, inner);

            if (_selectedRifleFilterId != null &&
                rifleIdForBucket != _selectedRifleFilterId) {
              continue;
            }
            if (!_rifleOnly &&
                _selectedAmmoFilterId != null &&
                ammoIdForBucket != _selectedAmmoFilterId) {
              continue;
            }

            var dks = inner.keys.toList();
            dks.sort((a, b) => a.value.compareTo(b.value));
            if (!_allDistances) {
              dks = dks.where((dk) => (dk.value.round() % 25 == 0)).toList();
            }

            String title;
            if (_rifleOnly) {
              title = rifleTitle(key);
            } else {
              title =
                  '${rifleTitle(rifleIdForBucket)} / ${ammoTitle(ammoIdForBucket)}';
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
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: dks.map((dk) {
                          final e = inner[dk]!;
                          final elevationText = _cleanText(
                            '${e.elevation} ${e.elevationUnit.name}${e.elevationNotes.isNotEmpty ? " • ${e.elevationNotes}" : ""}',
                          );
                          final windText = _cleanText(
                            '${e.windType.name}: ${e.windValue}${e.windNotes.isNotEmpty ? " • ${e.windNotes}" : ""}',
                          );
                          return DataRow(
                            cells: [
                              DataCell(Text('${dk.value} ${dk.unit.name[0]}')),
                              DataCell(
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    elevationText,
                                    softWrap: true,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    windText,
                                    softWrap: true,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text(e.windageLeft.toStringAsFixed(2))),
                              DataCell(Text(e.windageRight.toStringAsFixed(2))),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Edit working DOPE',
                                      onPressed: () async {
                                        var targetRifleOnly = _rifleOnly;
                                        var targetBucketKey = key;

                                        // In rifle-only mode we may be showing a merged
                                        // derived entry from a rifle+ammo bucket.
                                        if (_rifleOnly) {
                                          final explicitBucket = widget
                                              .state
                                              .workingDopeRifleOnly[key];
                                          final isExplicit =
                                              explicitBucket?.containsKey(dk) ??
                                              false;
                                          if (!isExplicit) {
                                            final rid = e.rifleId;
                                            final aid = e.ammoLotId;
                                            if (rid != null && aid != null) {
                                              targetRifleOnly = false;
                                              targetBucketKey = '${rid}_$aid';
                                            } else {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Could not resolve DOPE source for editing.',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                          }
                                        }

                                        final edited =
                                            await showDialog<DopeEntry>(
                                              context: context,
                                              builder: (_) =>
                                                  _WorkingDopeEditDialog(
                                                    initial: e,
                                                  ),
                                            );
                                        if (edited == null) return;

                                        final updated = widget.state
                                            .updateWorkingDopeEntry(
                                              rifleOnly: targetRifleOnly,
                                              bucketKey: targetBucketKey,
                                              oldDistanceKey: dk,
                                              entry: edited,
                                            );
                                        if (context.mounted && !updated) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Could not update that DOPE entry.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: 'Delete working DOPE',
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text(
                                              'Delete working DOPE entry?',
                                            ),
                                            content: const Text(
                                              'This cannot be undone.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok != true) return;

                                        var removed = widget.state
                                            .deleteWorkingDopeEntry(
                                              rifleOnly: _rifleOnly,
                                              bucketKey: key,
                                              distanceKey: dk,
                                            );

                                        // In rifle-only mode we may be showing a merged
                                        // derived entry from a rifle+ammo bucket.
                                        if (!removed && _rifleOnly) {
                                          final rid = e.rifleId;
                                          final aid = e.ammoLotId;
                                          if (rid != null && aid != null) {
                                            removed = widget.state
                                                .deleteWorkingDopeEntry(
                                                  rifleOnly: false,
                                                  bucketKey: '${rid}_$aid',
                                                  distanceKey: dk,
                                                );
                                          }
                                        }

                                        if (context.mounted && !removed) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Could not find that DOPE entry to delete.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
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
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          );
        }

        if (workingSections.isEmpty) {
          workingSections.add(
            Text(
              'No working DOPE entries match the selected filter.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
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
                          Text(
                            'DOPE (Quick Reference)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (withDope.isEmpty)
                        Text(
                          'No DOPE saved yet. Add it under Equipment -> Rifles.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
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
                          Text(
                            'Working DOPE Chart',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Rifle only'),
                              Switch(
                                value: _rifleOnly,
                                onChanged: (v) =>
                                    setState(() => _rifleOnly = v),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('All distances'),
                              Switch(
                                value: _allDistances,
                                onChanged: (v) =>
                                    setState(() => _allDistances = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedRifleFilterId,
                        decoration: const InputDecoration(
                          labelText: 'Rifle filter',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All rifles'),
                          ),
                          ...rifleFilterOptions.map(
                            (rifleId) => DropdownMenuItem<String?>(
                              value: rifleId,
                              child: Text(
                                rifleTitle(rifleId),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedRifleFilterId = value;
                            if (_selectedAmmoFilterId != null) {
                              final ammoRifles =
                                  ammoToRifles[_selectedAmmoFilterId!] ??
                                  const <String>{};
                              if (value != null &&
                                  !ammoRifles.contains(value)) {
                                _selectedAmmoFilterId = null;
                              }
                            }
                          });
                        },
                      ),
                      if (!_rifleOnly) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          initialValue: _selectedAmmoFilterId,
                          decoration: const InputDecoration(
                            labelText: 'Ammo filter',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All ammo'),
                            ),
                            ...ammoFilterOptions.map(
                              (ammoId) => DropdownMenuItem<String?>(
                                value: ammoId,
                                child: Text(
                                  ammoTitle(ammoId),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedAmmoFilterId = value),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ...workingSections,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final snapshots = widget.state.maintenanceSnapshots();
                  final overdue = snapshots
                      .where(
                        (snapshot) =>
                            snapshot.overallStatus ==
                            MaintenanceDueStatus.overdue,
                      )
                      .length;
                  final dueSoon = snapshots
                      .where(
                        (snapshot) =>
                            snapshot.overallStatus ==
                            MaintenanceDueStatus.dueSoon,
                      )
                      .length;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_none),
                      title: const Text('Maintenance reminders'),
                      subtitle: Text(
                        snapshots.isEmpty
                            ? 'Add rifles to start tracking cleaning, torque, zero, and barrel reminders.'
                            : '$overdue overdue • $dueSoon due soon across ${snapshots.length} rifle${snapshots.length == 1 ? '' : 's'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                MaintenanceHubScreen(state: widget.state),
                          ),
                        );
                      },
                    ),
                  );
                },
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
    widget.state.addUser(
      name: (res.name ?? res.identifier),
      identifier: res.identifier,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteUser(UserProfile user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user?'),
        content: const Text(
          'This removes the user profile. Session ownership and shared access will be reassigned so historical data remains available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = widget.state.deleteUser(userId: user.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one user must remain.')),
      );
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('User deleted.')));
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
      body: ListView.separated(
        itemCount: users.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final u = users[index];
          final isActive = active?.id == u.id;
          final canDelete = users.length > 1;
          return ListTile(
            title: Text(_displayUserName(u)),
            subtitle: Text(_displayUserIdentifier(u.identifier)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive) const Icon(Icons.check_circle_outline),
                if (canDelete)
                  IconButton(
                    tooltip: 'Delete user',
                    onPressed: () => _deleteUser(u),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            onTap: () {
              widget.state.switchUser(u);
              Navigator.of(context).pop();
            },
          );
        },
      ),
    );
  }
}

class SessionsScreen extends StatefulWidget {
  final AppState state;
  const SessionsScreen({super.key, required this.state});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  static const String _filtersPanelCollapsedPrefsKey =
      'cold_bore.sessions.filters_panel_collapsed.v1';

  bool _showArchived = false;
  String _groupBy = 'none';
  int? _yearFilter;
  String? _monthFilter;
  String? _folderFilter;
  bool _filtersPanelCollapsed = true;
  final Set<String> _collapsedGroups = <String>{};
  final Set<String> _initializedCollapsedGroups = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadUiPrefs());
  }

  Future<void> _loadUiPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_filtersPanelCollapsedPrefsKey);
      if (saved == null || !mounted) return;
      setState(() => _filtersPanelCollapsed = saved);
    } catch (e, st) {
      debugPrint('Sessions ui prefs load failed: $e\n$st');
    }
  }

  Future<void> _saveFiltersPanelCollapsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _filtersPanelCollapsedPrefsKey,
        _filtersPanelCollapsed,
      );
    } catch (e, st) {
      debugPrint('Sessions ui prefs save failed: $e\n$st');
    }
  }

  void _setFiltersPanelCollapsed(bool value) {
    setState(() => _filtersPanelCollapsed = value);
    unawaited(_saveFiltersPanelCollapsed());
  }

  String _groupStorageKey(String groupBy, String label) => '$groupBy::$label';

  void _toggleGroupCollapsed(String groupBy, String label) {
    final key = _groupStorageKey(groupBy, label);
    setState(() {
      _initializedCollapsedGroups.add(key);
      if (_collapsedGroups.contains(key)) {
        _collapsedGroups.remove(key);
      } else {
        _collapsedGroups.add(key);
      }
    });
  }

  void _collapseFiledFolderGroup(String folderName) {
    final normalized = folderName.trim();
    if (normalized.isEmpty) return;
    _groupBy = 'folder';
    final key = _groupStorageKey('folder', normalized);
    _initializedCollapsedGroups.add(key);
    _collapsedGroups.add(key);
  }

  String _monthKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
  }

  String _monthLabel(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final month = int.tryParse(parts[1]) ?? 1;
    const names = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final name = (month >= 1 && month <= 12) ? names[month - 1] : parts[1];
    return '$name ${parts[0]}';
  }

  String _joinNonEmpty(List<String?> parts) {
    final out = <String>[];
    for (final p in parts) {
      final v = (p ?? '').trim();
      if (v.isNotEmpty) out.add(v);
    }
    return out.join(' • ');
  }

  String _groupByLabel(String value) {
    switch (value) {
      case 'year':
        return 'Year';
      case 'month':
        return 'Month';
      case 'folder':
        return 'Folder';
      case 'none':
      default:
        return 'Newest first';
    }
  }

  String _filtersSummary(int visibleCount) {
    final parts = <String>['Showing $visibleCount'];
    if (_showArchived) parts.add('Archived shown');
    if (_groupBy != 'none') parts.add('Grouped by ${_groupByLabel(_groupBy)}');
    if (_yearFilter != null) parts.add('Year $_yearFilter');
    if (_monthFilter != null) parts.add(_monthLabel(_monthFilter!));
    if (_folderFilter != null) {
      parts.add(
        _folderFilter == '__unfiled__'
            ? 'Unfiled only'
            : 'Folder ${_folderFilter!}',
      );
    }
    return parts.join(' • ');
  }

  Future<void> _newSession(BuildContext context) async {
    if (!await _guardWrite(context)) return;
    final res = await showDialog<_NewSessionResult>(
      context: context,
      builder: (_) => const _NewSessionDialog(),
    );
    if (res == null) return;
    final created = widget.state.addSession(
      locationName: res.locationName,
      folderName: res.folderName,
      dateTime: res.dateTime,
      notes: res.notes,
    );

    if (created == null) return;
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SessionDetailScreen(state: widget.state, sessionId: created.id),
      ),
    );
  }

  Future<void> _editFolder(
    BuildContext context,
    TrainingSession session,
  ) async {
    final existingFolders =
        widget.state.sessions
            .map((s) => s.folderName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final ctrl = TextEditingController(text: session.folderName.trim());
    try {
      final next = await showDialog<String>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: const Text('Session folder'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existingFolders.isNotEmpty) ...[
                  const Text(
                    'Quick pick',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: existingFolders
                        .map(
                          (name) => ActionChip(
                            label: Text(name),
                            onPressed: () {
                              ctrl.text = name;
                              setLocalState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Folder name',
                    helperText: 'Leave empty to remove folder assignment.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (next == null) return;
      widget.state.updateSessionFolder(sessionId: session.id, folderName: next);
      if (!mounted) return;
      if (next.trim().isNotEmpty && _folderFilter == null) {
        setState(() => _collapseFiledFolderGroup(next));
      }
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _bulkArchive(
    BuildContext context,
    List<TrainingSession> sessions,
    bool archived,
  ) async {
    if (sessions.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(archived ? 'Archive sessions?' : 'Unarchive sessions?'),
        content: Text(
          'This will ${archived ? 'archive' : 'unarchive'} ${sessions.length} filtered session${sessions.length == 1 ? '' : 's'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(archived ? 'Archive' : 'Unarchive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final session in sessions) {
      widget.state.setSessionArchived(
        sessionId: session.id,
        archived: archived,
      );
    }
  }

  Future<void> _bulkMoveToFolder(
    BuildContext context,
    List<TrainingSession> sessions,
  ) async {
    if (sessions.isEmpty) return;
    final existingFolders =
        widget.state.sessions
            .map((s) => s.folderName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final ctrl = TextEditingController();
    try {
      final next = await showDialog<String>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: Text(
              'Move ${sessions.length} session${sessions.length == 1 ? '' : 's'}',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existingFolders.isNotEmpty) ...[
                  const Text(
                    'Quick pick',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: existingFolders
                        .map(
                          (name) => ActionChip(
                            label: Text(name),
                            onPressed: () {
                              ctrl.text = name;
                              setLocalState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Folder name',
                    helperText: 'Leave empty to remove folder assignment.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      );
      if (next == null) return;
      for (final session in sessions) {
        widget.state.updateSessionFolder(
          sessionId: session.id,
          folderName: next,
        );
      }
      if (!mounted) return;
      if (next.trim().isNotEmpty && _folderFilter == null) {
        setState(() => _collapseFiledFolderGroup(next));
      }
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _deleteSession(
    BuildContext context,
    TrainingSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete session?'),
        content: const Text(
          'This permanently deletes this session and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.state.deleteSession(sessionId: session.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session deleted.')));
  }

  Widget _sessionTile(BuildContext context, TrainingSession s) {
    final rifle = widget.state.rifleById(s.rifleId);
    final ammo = widget.state.ammoById(s.ammoLotId);
    final subtitleBits = <String?>[
      _fmtDateTime(s.dateTime),
      if (s.folderName.trim().isNotEmpty) 'Folder: ${s.folderName.trim()}',
      if (rifle != null) rifle.name,
      if (ammo != null) ammo.name,
      if (s.archived) 'Archived',
    ];

    return ListTile(
      title: Text(
        s.locationName.trim().isEmpty ? '(No location)' : s.locationName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _cleanText(_joinNonEmpty(subtitleBits)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      leading: s.shots.any((x) => x.isColdBore)
          ? const Icon(Icons.ac_unit_outlined)
          : const Icon(Icons.event_note_outlined),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'folder') {
            await _editFolder(context, s);
            return;
          }
          if (value == 'archive') {
            widget.state.setSessionArchived(sessionId: s.id, archived: true);
            return;
          }
          if (value == 'unarchive') {
            widget.state.setSessionArchived(sessionId: s.id, archived: false);
            return;
          }
          if (value == 'delete') {
            await _deleteSession(context, s);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'folder', child: Text('Set folder')),
          PopupMenuItem(
            value: s.archived ? 'unarchive' : 'archive',
            child: Text(s.archived ? 'Unarchive' : 'Archive'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete session')),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                SessionDetailScreen(state: widget.state, sessionId: s.id),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final user = widget.state.activeUser;
        final sessions = [...widget.state.sessions]
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

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

        final availableYears =
            sessions.map((s) => s.dateTime.year).toSet().toList()
              ..sort((a, b) => b.compareTo(a));
        final availableMonths =
            sessions.map((s) => _monthKey(s.dateTime)).toSet().toList()
              ..sort((a, b) => b.compareTo(a));
        final availableFolders =
            sessions
                .map((s) => s.folderName.trim())
                .where((f) => f.isNotEmpty)
                .toSet()
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        final filtered = sessions.where((s) {
          if (!_showArchived && s.archived) return false;
          if (_yearFilter != null && s.dateTime.year != _yearFilter) {
            return false;
          }
          if (_monthFilter != null && _monthKey(s.dateTime) != _monthFilter) {
            return false;
          }
          if (_folderFilter != null) {
            final folder = s.folderName.trim();
            if (_folderFilter == '__unfiled__') {
              if (folder.isNotEmpty) return false;
            } else if (folder != _folderFilter) {
              return false;
            }
          }
          return true;
        }).toList();

        final grouped = <String, List<TrainingSession>>{};
        for (final s in filtered) {
          String key;
          switch (_groupBy) {
            case 'year':
              key = '${s.dateTime.year}';
              break;
            case 'month':
              key = _monthLabel(_monthKey(s.dateTime));
              break;
            case 'folder':
              key = s.folderName.trim().isEmpty
                  ? 'Unfiled'
                  : s.folderName.trim();
              break;
            default:
              key = 'Sessions';
          }
          grouped.putIfAbsent(key, () => <TrainingSession>[]).add(s);
        }

        if (_groupBy == 'folder') {
          for (final entry in grouped.entries) {
            final key = _groupStorageKey('folder', entry.key);
            if (_initializedCollapsedGroups.add(key) &&
                entry.key != 'Unfiled') {
              _collapsedGroups.add(key);
            }
          }
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _newSession(context),
            icon: const Icon(Icons.add),
            label: const Text('New Session'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.tune),
                        title: const Text(
                          'Organize Sessions',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          _filtersSummary(filtered.length),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          _filtersPanelCollapsed
                              ? Icons.expand_more
                              : Icons.expand_less,
                        ),
                        onTap: () =>
                            _setFiltersPanelCollapsed(!_filtersPanelCollapsed),
                      ),
                      if (!_filtersPanelCollapsed) ...[
                        const SizedBox(height: 8),
                        FilterChip(
                          label: const Text('Show archived'),
                          selected: _showArchived,
                          onSelected: (value) =>
                              setState(() => _showArchived = value),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _groupBy,
                          decoration: const InputDecoration(
                            labelText: 'Group by',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'none',
                              child: Text('Newest first'),
                            ),
                            DropdownMenuItem(
                              value: 'year',
                              child: Text('Year'),
                            ),
                            DropdownMenuItem(
                              value: 'month',
                              child: Text('Month'),
                            ),
                            DropdownMenuItem(
                              value: 'folder',
                              child: Text('Folder'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _groupBy = value ?? 'none'),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          initialValue: _yearFilter,
                          decoration: const InputDecoration(
                            labelText: 'Year filter',
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('All years'),
                            ),
                            ...availableYears.map(
                              (year) => DropdownMenuItem<int?>(
                                value: year,
                                child: Text('$year'),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _yearFilter = value),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          initialValue: _monthFilter,
                          decoration: const InputDecoration(
                            labelText: 'Month filter',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All months'),
                            ),
                            ...availableMonths.map(
                              (month) => DropdownMenuItem<String?>(
                                value: month,
                                child: Text(_monthLabel(month)),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _monthFilter = value),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          initialValue: _folderFilter,
                          decoration: const InputDecoration(
                            labelText: 'Folder filter',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All folders'),
                            ),
                            const DropdownMenuItem<String?>(
                              value: '__unfiled__',
                              child: Text('Unfiled only'),
                            ),
                            ...availableFolders.map(
                              (folder) => DropdownMenuItem<String?>(
                                value: folder,
                                child: Text(folder),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _folderFilter = value),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: filtered.isEmpty
                                  ? null
                                  : () => _bulkMoveToFolder(context, filtered),
                              icon: const Icon(Icons.drive_file_move_outline),
                              label: Text('Move ${filtered.length} to folder'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: filtered.isEmpty
                                  ? null
                                  : () => _bulkArchive(context, filtered, true),
                              icon: const Icon(Icons.archive_outlined),
                              label: Text('Archive ${filtered.length}'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: filtered.isEmpty
                                  ? null
                                  : () =>
                                        _bulkArchive(context, filtered, false),
                              icon: const Icon(Icons.unarchive_outlined),
                              label: Text('Unarchive ${filtered.length}'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                const _HintCard(
                  icon: Icons.folder_open_outlined,
                  title: 'No sessions match current filters',
                  message:
                      'Adjust year/month/folder or include archived sessions.',
                )
              else
                ...grouped.entries.expand((entry) {
                  final children = <Widget>[];
                  final isCollapsible = _groupBy != 'none';
                  final isCollapsed =
                      isCollapsible &&
                      _collapsedGroups.contains(
                        _groupStorageKey(_groupBy, entry.key),
                      );
                  children.add(
                    Card(
                      child: Column(
                        children: [
                          if (isCollapsible)
                            ListTile(
                              leading: Icon(
                                isCollapsed
                                    ? Icons.chevron_right
                                    : Icons.expand_more,
                              ),
                              title: Text(
                                entry.key,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${entry.value.length} session${entry.value.length == 1 ? '' : 's'}',
                              ),
                              onTap: () =>
                                  _toggleGroupCollapsed(_groupBy, entry.key),
                            ),
                          if (!isCollapsible || !isCollapsed) ...[
                            if (isCollapsible) const Divider(height: 1),
                            for (var i = 0; i < entry.value.length; i++) ...[
                              _sessionTile(context, entry.value[i]),
                              if (i < entry.value.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ],
                      ),
                    ),
                  );
                  children.add(const SizedBox(height: 8));
                  return children;
                }),
            ],
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

class _WorkingDopeEditDialog extends StatefulWidget {
  final DopeEntry initial;
  const _WorkingDopeEditDialog({required this.initial});

  @override
  State<_WorkingDopeEditDialog> createState() => _WorkingDopeEditDialogState();
}

class _WorkingDopeEditDialogState extends State<_WorkingDopeEditDialog> {
  late final TextEditingController _distanceCtrl;
  late DistanceUnit _distanceUnit;
  late final TextEditingController _elevationCtrl;
  late ElevationUnit _elevationUnit;
  late final TextEditingController _elevationNotesCtrl;
  late final TextEditingController _windValueCtrl;
  late final TextEditingController _windNotesCtrl;
  late final TextEditingController _windageCtrl;
  late bool _windageIsLeft;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _distanceCtrl = TextEditingController(text: e.distance.toString());
    _distanceUnit = e.distanceUnit;
    _elevationCtrl = TextEditingController(text: e.elevation.toString());
    _elevationUnit = e.elevationUnit;
    _elevationNotesCtrl = TextEditingController(text: e.elevationNotes);
    _windValueCtrl = TextEditingController(text: e.windValue);
    _windNotesCtrl = TextEditingController(text: e.windNotes);
    final startsLeft =
        e.windageLeft > 0 || (e.windageLeft == 0 && e.windageRight == 0);
    _windageIsLeft = startsLeft;
    final windageAmount = startsLeft ? e.windageLeft : e.windageRight;
    _windageCtrl = TextEditingController(text: windageAmount.toString());
  }

  @override
  void dispose() {
    _distanceCtrl.dispose();
    _elevationCtrl.dispose();
    _elevationNotesCtrl.dispose();
    _windValueCtrl.dispose();
    _windNotesCtrl.dispose();
    _windageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Working DOPE'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    controller: _distanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Distance'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<DistanceUnit>(
                  value: _distanceUnit,
                  items: DistanceUnit.values
                      .map(
                        (u) => DropdownMenuItem(value: u, child: Text(u.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _distanceUnit = v!),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    controller: _elevationCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Elevation'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<ElevationUnit>(
                  value: _elevationUnit,
                  items: ElevationUnit.values
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(u.name.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _elevationUnit = v!),
                ),
              ],
            ),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _elevationNotesCtrl,
              decoration: const InputDecoration(
                labelText: 'Elevation notes (optional)',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ToggleButtons(
                  isSelected: [_windageIsLeft, !_windageIsLeft],
                  onPressed: (i) => setState(() => _windageIsLeft = i == 0),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('Left'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('Right'),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    controller: _windageCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Windage'),
                  ),
                ),
              ],
            ),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _windValueCtrl,
              decoration: const InputDecoration(
                labelText: 'Wind value (optional)',
              ),
            ),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _windNotesCtrl,
              decoration: const InputDecoration(
                labelText: 'Wind notes (optional)',
              ),
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
            final distance = double.tryParse(_distanceCtrl.text.trim());
            final elevation = double.tryParse(_elevationCtrl.text.trim());
            final windage = double.tryParse(_windageCtrl.text.trim());
            if (distance == null || elevation == null || windage == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter valid numeric values.')),
              );
              return;
            }

            final updated = DopeEntry(
              id: widget.initial.id,
              time: DateTime.now(),
              rifleId: widget.initial.rifleId,
              ammoLotId: widget.initial.ammoLotId,
              distance: distance,
              distanceUnit: _distanceUnit,
              elevation: elevation,
              elevationUnit: _elevationUnit,
              elevationNotes: _elevationNotesCtrl.text.trim(),
              windType: widget.initial.windType,
              windValue: _windValueCtrl.text.trim(),
              windNotes: _windNotesCtrl.text.trim(),
              windageLeft: _windageIsLeft ? windage : 0.0,
              windageRight: _windageIsLeft ? 0.0 : windage,
            );

            Navigator.pop(context, updated);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

enum _WorkingDopeConflictChoice { replace, addBoth }

class _DopeEntryDialog extends StatefulWidget {
  const _DopeEntryDialog({
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
  final _elevationCtrl = TextEditingController(text: '0.0');
  late ElevationUnit _elevationUnit;
  String? _ammoLotId;
  final _elevationNotesCtrl = TextEditingController();
  final WindType _windType = WindType.fullValue;

  @override
  void initState() {
    super.initState();
    _elevationUnit = widget.lockedUnit;
    _ammoLotId =
        widget.defaultAmmoId ??
        (widget.ammoOptions.isNotEmpty ? widget.ammoOptions.first.id : null);
  }

  final _windValueCtrl = TextEditingController();
  final _windNotesCtrl = TextEditingController();
  final _windageCtrl = TextEditingController(text: '0.0');
  bool _windageIsLeft = true;
  bool _promote = true;
  bool _rifleOnly = false;

  @override
  void dispose() {
    _distanceCtrl.dispose();
    _elevationCtrl.dispose();
    _elevationNotesCtrl.dispose();
    _windValueCtrl.dispose();
    _windNotesCtrl.dispose();
    _windageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ammoById = <String, AmmoLot>{
      for (final a in widget.ammoOptions) a.id: a,
    };
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
              initialValue: safeAmmoLotId,
              decoration: const InputDecoration(
                labelText: 'Ammo (for this entry)',
              ),
              items: uniqueAmmoOptions
                  .map(
                    (a) => DropdownMenuItem<String?>(
                      value: a.id,
                      child: Text('${a.name ?? 'Ammo'} (${a.caliber})'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _ammoLotId = v),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    controller: _distanceCtrl,
                    decoration: const InputDecoration(labelText: 'Distance'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<DistanceUnit>(
                  value: _distanceUnit,
                  items: DistanceUnit.values
                      .map(
                        (u) => DropdownMenuItem(value: u, child: Text(u.name)),
                      )
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
                    Expanded(
                      child: TextField(
                        textCapitalization: TextCapitalization.none,
                        controller: _elevationCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Elevation value',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<ElevationUnit>(
                      value: _elevationUnit,
                      items: ElevationUnit.values
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(u.name.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _elevationUnit = v!),
                    ),
                  ],
                ),
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _elevationNotesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Elevation notes (optional)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Windage (${_elevationUnit.name.toUpperCase()})'),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ToggleButtons(
                          isSelected: [_windageIsLeft, !_windageIsLeft],
                          onPressed: (i) =>
                              setState(() => _windageIsLeft = i == 0),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text('Left'),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text('Right'),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            textCapitalization: TextCapitalization.none,
                            controller: _windageCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Windage value',
                            ),
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      textCapitalization: TextCapitalization.none,
                      controller: _windValueCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Wind value (optional)',
                      ),
                    ),
                    TextField(
                      textCapitalization: TextCapitalization.none,
                      controller: _windNotesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Wind notes (optional)',
                      ),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final dist = double.tryParse(_distanceCtrl.text.trim());
            final elevation = double.tryParse(_elevationCtrl.text.trim());
            final windage = double.tryParse(_windageCtrl.text.trim());
            if (dist == null) return;
            if (elevation == null) return;
            if (windage == null) return;
            if (_ammoLotId == null) return;

            final entry = DopeEntry(
              id: '', // will be set in state
              time: widget.defaultTime ?? DateTime.now(),
              rifleId: widget.rifleId,
              ammoLotId: _ammoLotId,
              distance: dist,
              distanceUnit: _distanceUnit,
              elevation: elevation,
              elevationUnit: _elevationUnit,
              elevationNotes: _elevationNotesCtrl.text.trim(),
              windType: _windType,
              windValue: _windValueCtrl.text.trim(),
              windNotes: _windNotesCtrl.text.trim(),
              windageLeft: _windageIsLeft ? windage : 0.0,
              windageRight: _windageIsLeft ? 0.0 : windage,
            );

            Navigator.pop(context, _DopeResult(entry, _promote, _rifleOnly));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SessionShotTimerCard extends StatefulWidget {
  final AppState state;
  final String sessionId;

  const _SessionShotTimerCard({required this.state, required this.sessionId});

  @override
  State<_SessionShotTimerCard> createState() => _SessionShotTimerCardState();
}

class _SessionShotTimerCardState extends State<_SessionShotTimerCard> {
  final Stopwatch _stopwatch = Stopwatch();
  final TextEditingController _delayCtrl = TextEditingController();
  final TextEditingController _goalCtrl = TextEditingController();
  Timer? _ticker;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  int _baseElapsedMs = 0;
  int _elapsedMs = 0;
  int? _firstShotMs;
  List<int> _splitMs = const [];
  bool _isArmed = false;
  int _countdownRemainingMs = 0;
  int _startDelayMs = 0;
  int _goalMs = 0;
  bool _goalAlertPlayed = false;
  DateTime? _armedUntil;
  bool _audioAssistEnabled = false;
  double _audioThresholdDb = 92;
  double _latestDb = 0;
  DateTime? _lastAudioShotAt;
  String? _audioAssistMessage;
  String? _selectedRifleId;
  int _audioShotCount = 0;

  bool get _isRunning => _stopwatch.isRunning;
  bool get _isActive => _isRunning || _isArmed;
  bool get _audioAssistSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    _loadFromSession();
  }

  @override
  void didUpdateWidget(covariant _SessionShotTimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isRunning &&
        (oldWidget.sessionId != widget.sessionId ||
            oldWidget.state != widget.state)) {
      _loadFromSession();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _noiseSubscription?.cancel();
    _stopwatch.stop();
    _delayCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  void _loadFromSession() {
    final session = widget.state.getSessionById(widget.sessionId);
    _baseElapsedMs = 0;
    _elapsedMs = ((session?.shotTimerElapsedMs ?? 0) > 0)
        ? session!.shotTimerElapsedMs!
        : 0;
    _firstShotMs = ((session?.shotTimerFirstShotMs ?? 0) > 0)
        ? session!.shotTimerFirstShotMs
        : null;
    _splitMs = [
      for (final split in session?.shotTimerSplitMs ?? const <int>[])
        if (split > 0) split,
    ];
    _selectedRifleId ??=
        session?.rifleId ?? widget.state.shotTimerSelectedRifleId;
    _audioThresholdDb = widget.state.audioThresholdDb;
  }

  int _currentElapsedMs() {
    if (!_isRunning) return _elapsedMs;
    return _baseElapsedMs + _stopwatch.elapsedMilliseconds;
  }

  int _lastMarkMs() {
    if (_firstShotMs == null) return 0;
    var total = _firstShotMs!;
    for (final split in _splitMs) {
      total += split;
    }
    return total;
  }

  List<int> _shotMarks(int? firstShotMs, List<int> splitMs) {
    if ((firstShotMs ?? 0) <= 0) return const [];
    final marks = <int>[firstShotMs!];
    var total = firstShotMs;
    for (final split in splitMs) {
      total += split;
      marks.add(total);
    }
    return marks;
  }

  Widget _shotMarkChart(List<int> marks, {int goalMs = 0}) {
    if (marks.isEmpty) {
      return const Text('No shots logged yet.', style: TextStyle(fontSize: 13));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < marks.length; i++)
          Container(
            width: 96,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: goalMs > 0 && marks[i] > goalMs
                  ? Colors.red.withValues(alpha: 0.12)
                  : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: goalMs > 0 && marks[i] > goalMs
                    ? Colors.red.withValues(alpha: 0.55)
                    : Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shot ${i + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: goalMs > 0 && marks[i] > goalMs
                        ? Colors.red.shade700
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtMs(marks[i]),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: goalMs > 0 && marks[i] > goalMs
                        ? Colors.red.shade700
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  int _parseSecondsToMs(String raw) {
    final seconds = double.tryParse(raw.trim()) ?? 0;
    if (seconds <= 0) return 0;
    return (seconds * 1000).round();
  }

  Future<void> _beep() async {
    await _playShotTimerBeep();
  }

  void _beginRun() {
    _stopwatch
      ..reset()
      ..start();
    _baseElapsedMs = _elapsedMs;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) async {
      if (!mounted) return;
      if (_isArmed) {
        final next = math.max(
          0,
          (_armedUntil?.difference(DateTime.now()).inMilliseconds ?? 0),
        );
        if (next <= 0) {
          _beginRun();
          _beep(); // Fire and forget - don't await to avoid blocking timer
          if (!mounted) return;
          setState(() {
            _isArmed = false;
            _countdownRemainingMs = 0;
            _armedUntil = null;
          });
        } else {
          setState(() {
            _countdownRemainingMs = next;
          });
        }
        return;
      }
      if (!_isRunning) return;
      final current = _currentElapsedMs();
      final hitGoal = _goalMs > 0 && !_goalAlertPlayed && current >= _goalMs;
      if (hitGoal) {
        _goalAlertPlayed = true;
        _beep(); // Fire and forget - don't await to avoid blocking timer
        if (!mounted) return;
      }
      setState(() {
        _elapsedMs = current;
      });
    });
  }

  void _recordShotAt(int current) {
    _elapsedMs = current;
    if ((_firstShotMs ?? 0) <= 0) {
      _firstShotMs = current;
    } else {
      final previous = _lastMarkMs();
      final split = current - previous;
      if (split > 0) {
        _splitMs = [..._splitMs, split];
      }
    }
  }

  Future<void> _setAudioAssist(bool enabled) async {
    if (!_audioAssistSupported) {
      setState(() {
        _audioAssistEnabled = false;
        _audioAssistMessage =
            'Audio assist is available on iPhone and Android only.';
      });
      return;
    }
    if (!enabled) {
      await _noiseSubscription?.cancel();
      _noiseSubscription = null;
      if (!mounted) return;
      setState(() {
        _audioAssistEnabled = false;
        _latestDb = 0;
        _audioAssistMessage = null;
      });
      return;
    }

    try {
      await _noiseSubscription?.cancel();
      _noiseSubscription = NoiseMeter().noise.listen(
        (reading) {
          if (!mounted) return;
          final maxDb = reading.maxDecibel;
          final now = DateTime.now();
          final shouldMark =
              _audioAssistEnabled &&
              _isRunning &&
              maxDb >= _audioThresholdDb &&
              (_lastAudioShotAt == null ||
                  now.difference(_lastAudioShotAt!).inMilliseconds >= 250);

          setState(() {
            _latestDb = maxDb;
            if (shouldMark) {
              _lastAudioShotAt = now;
              _recordShotAt(_currentElapsedMs());
              if (widget.state.shotTimerApplyAudioShotCountToRifle &&
                  _selectedRifleId != null) {
                widget.state.addRifleRounds(
                  rifleId: _selectedRifleId!,
                  roundCount: 1,
                );
              } else {
                _audioShotCount += 1;
              }
            }
          });
          if (shouldMark) {
            _persist();
          }
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _audioAssistEnabled = false;
            _audioAssistMessage =
                'Microphone unavailable. Check permissions and try again.';
          });
        },
        cancelOnError: true,
      );
      if (!mounted) return;
      setState(() {
        _audioAssistEnabled = true;
        _audioAssistMessage =
            'Audio assist armed. Loud impulses can auto-mark shots.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _audioAssistEnabled = false;
        _audioAssistMessage =
            'Microphone unavailable. Check permissions and try again.';
      });
    }
  }

  void _persist() {
    widget.state.saveSessionTimer(
      sessionId: widget.sessionId,
      elapsedMs: _elapsedMs > 0 ? _elapsedMs : 0,
      firstShotMs: (_firstShotMs ?? 0) > 0 ? _firstShotMs : 0,
      splitMs: _splitMs,
    );
  }

  void _start() {
    if (_isActive) return;
    _startDelayMs = _parseSecondsToMs(_delayCtrl.text);
    _goalMs = _parseSecondsToMs(_goalCtrl.text);
    _goalAlertPlayed = _goalMs > 0 && _elapsedMs >= _goalMs;
    setState(() {
      _countdownRemainingMs = _startDelayMs;
      _isArmed = _startDelayMs > 0;
      _armedUntil = _startDelayMs > 0
          ? DateTime.now().add(Duration(milliseconds: _startDelayMs))
          : null;
    });
    if (!_isArmed) {
      _beginRun();
    }
    _startTicker();
  }

  Future<void> _stop() async {
    if (_isArmed) {
      _ticker?.cancel();
      setState(() {
        _isArmed = false;
        _countdownRemainingMs = 0;
        _armedUntil = null;
      });
      return;
    }
    if (!_isRunning) return;
    _ticker?.cancel();
    _stopwatch.stop();
    setState(() {
      _elapsedMs = _currentElapsedMs();
    });
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Timer?'),
        content: const Text(
          'Do you want to save this timer run to the session, delete it, or keep it paused for now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Delete'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    switch (action) {
      case 'save':
        widget.state.addSessionTimerRun(
          sessionId: widget.sessionId,
          elapsedMs: _elapsedMs,
          firstShotMs: _firstShotMs ?? 0,
          splitMs: _splitMs,
          startDelayMs: _startDelayMs,
          goalMs: _goalMs,
        );
        break;
      case 'delete':
        _reset();
        break;
      case 'keep':
      default:
        setState(() {});
        break;
    }
  }

  void _markShot() {
    if (!_isRunning) return;
    final current = _currentElapsedMs();
    setState(() {
      _recordShotAt(current);
    });
    _persist();
  }

  void _reset() {
    _ticker?.cancel();
    _stopwatch
      ..stop()
      ..reset();
    setState(() {
      _isArmed = false;
      _countdownRemainingMs = 0;
      _armedUntil = null;
      _baseElapsedMs = 0;
      _elapsedMs = 0;
      _firstShotMs = null;
      _splitMs = const [];
      _goalAlertPlayed = false;
      _audioShotCount = 0;
    });
    widget.state.clearSessionTimer(sessionId: widget.sessionId);
  }

  String _fmtMs(int ms) {
    final totalSeconds = (ms / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hundredths = (ms % 1000) ~/ 10;
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
    }
    return '$seconds.${hundredths.toString().padLeft(2, '0')}';
  }

  String _rifleDropdownLabel(Rifle rifle) {
    final name = (rifle.name ?? '').trim();
    if (name.isNotEmpty) return name;
    final modelBits = [
      (rifle.manufacturer ?? '').trim(),
      (rifle.model ?? '').trim(),
    ].where((v) => v.isNotEmpty).toList();
    if (modelBits.isNotEmpty) return modelBits.join(' ');
    return rifle.caliber.trim().isEmpty ? 'Rifle' : rifle.caliber.trim();
  }

  String _runSummary(SessionTimerRun run) {
    final parts = <String>['total ${_fmtMs(run.elapsedMs)}'];
    if (run.firstShotMs > 0) {
      parts.add('first ${_fmtMs(run.firstShotMs)}');
    }
    if (run.splitMs.isNotEmpty) {
      parts.add(
        '${run.splitMs.length} split${run.splitMs.length == 1 ? '' : 's'}',
      );
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.state.getSessionById(widget.sessionId);
    final isEnded = session?.endedAt != null;
    final totalShotsMarked = (_firstShotMs == null ? 0 : 1) + _splitMs.length;
    final savedRuns =
        session?.timerRuns.reversed.toList() ?? const <SessionTimerRun>[];
    final currentShotMarks = _shotMarks(_firstShotMs, _splitMs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Shot Timer',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_isArmed)
                  const Chip(
                    label: Text('Armed'),
                    avatar: Icon(Icons.hourglass_top_outlined, size: 18),
                  )
                else if (_isRunning)
                  const Chip(
                    label: Text('Running'),
                    avatar: Icon(Icons.timer_outlined, size: 18),
                  )
                else if ((_elapsedMs > 0) || totalShotsMarked > 0)
                  const Chip(
                    label: Text('Saved'),
                    avatar: Icon(Icons.check_circle_outline, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isArmed
                  ? _fmtMs(_countdownRemainingMs)
                  : _fmtMs(_currentElapsedMs()),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'First shot: ${_firstShotMs == null ? '-' : _fmtMs(_firstShotMs!)}',
                  ),
                ),
                Chip(
                  label: Text(
                    'Splits: ${_splitMs.isEmpty ? '-' : _splitMs.map(_fmtMs).join(', ')}',
                  ),
                ),
                Chip(label: Text('Marked shots: $totalShotsMarked')),
                if (_startDelayMs > 0)
                  Chip(
                    avatar: const Icon(Icons.hourglass_top_outlined, size: 18),
                    label: Text(
                      'Delayed start: ${(_startDelayMs / 1000).toStringAsFixed(1)}s',
                    ),
                  ),
                if (_goalMs > 0)
                  Chip(
                    avatar: Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: _goalAlertPlayed ? Colors.red.shade700 : null,
                    ),
                    label: Text(
                      'Goal: ${(_goalMs / 1000).toStringAsFixed(1)}s',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Shot Chart',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            _shotMarkChart(currentShotMarks, goalMs: _goalMs),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    textCapitalization: TextCapitalization.none,
                    controller: _delayCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !isEnded && !_isActive,
                    decoration: const InputDecoration(
                      labelText: 'Delayed Start (sec)',
                      helperText: 'Beep after delay',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    textCapitalization: TextCapitalization.none,
                    controller: _goalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !isEnded && !_isActive,
                    decoration: const InputDecoration(
                      labelText: 'Time Goal (sec)',
                      helperText: 'Beep at limit',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isEnded
                      ? null
                      : () async {
                          if (_isActive) {
                            await _stop();
                          } else {
                            _start();
                          }
                        },
                  icon: Icon(
                    _isActive
                        ? Icons.stop_circle_outlined
                        : Icons.play_arrow_outlined,
                  ),
                  label: Text(
                    _isActive
                        ? 'Stop'
                        : ((_elapsedMs > 0 || totalShotsMarked > 0)
                              ? 'Start / Resume'
                              : 'Start'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isRunning ? _markShot : null,
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('Lap / Shot'),
                ),
                TextButton.icon(
                  onPressed:
                      (!_isRunning && (_elapsedMs > 0 || totalShotsMarked > 0))
                      ? _reset
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Records total elapsed time, first-shot time, and split times for this session.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Audio Assist'),
              subtitle: Text(
                _audioAssistSupported
                    ? (_audioAssistEnabled
                          ? 'Microphone listening for loud shot impulses.'
                          : 'Optional microphone assist for auto-marking shots.')
                    : 'Available only in iPhone and Android app builds.',
              ),
              value: _audioAssistEnabled,
              onChanged: isEnded ? null : (value) => _setAudioAssist(value),
            ),
            if (widget.state.rifles.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _selectedRifleId,
                decoration: const InputDecoration(labelText: 'Apply to Rifle'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No firearm selected'),
                  ),
                  ...widget.state.rifles.map(
                    (rifle) => DropdownMenuItem<String?>(
                      value: rifle.id,
                      child: Text(_rifleDropdownLabel(rifle)),
                    ),
                  ),
                ],
                onChanged: isEnded
                    ? null
                    : (val) {
                        setState(() => _selectedRifleId = val);
                        widget.state.setShotTimerSelectedRifleId(val);
                      },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-apply audio shot count to rifle'),
                subtitle: Text(
                  _selectedRifleId == null
                      ? 'Pick a rifle first, or leave No firearm selected to use timer only.'
                      : 'Increment selected rifle round count for auto-marked audio shots',
                ),
                value: widget.state.shotTimerApplyAudioShotCountToRifle,
                onChanged: isEnded
                    ? null
                    : (_selectedRifleId == null)
                    ? null
                    : (v) => widget.state
                          .setShotTimerApplyAudioShotCountToRifle(v),
              ),
              if (_audioShotCount > 0 && _selectedRifleId != null)
                FilledButton.icon(
                  onPressed: isEnded
                      ? null
                      : () {
                          widget.state.addRifleRounds(
                            rifleId: _selectedRifleId!,
                            roundCount: _audioShotCount,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Applied $_audioShotCount shots to rifle',
                              ),
                            ),
                          );
                          setState(() => _audioShotCount = 0);
                        },
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    'Apply $_audioShotCount audio shots to rifle now',
                  ),
                ),
              Text(
                'Audio-shot detections: $_audioShotCount',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _audioThresholdDb,
                    min: 70,
                    max: 120,
                    divisions: 50,
                    label: '${_audioThresholdDb.toStringAsFixed(0)} dB',
                    onChanged: (_audioAssistEnabled && _audioAssistSupported)
                        ? (value) {
                            setState(() => _audioThresholdDb = value);
                            widget.state.setAudioThresholdDb(value);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${_audioThresholdDb.toStringAsFixed(0)} dB'),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('Live level: ${_latestDb.toStringAsFixed(1)} dB'),
                ),
                if (_audioAssistMessage != null)
                  Chip(label: Text(_audioAssistMessage!)),
                if (!_audioAssistSupported)
                  const Chip(label: Text('Phone app only')),
              ],
            ),
            if (savedRuns.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text('Saved Runs (${savedRuns.length})'),
                children: [
                  for (final run in savedRuns)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(_runSummary(run)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_fmtDateTime(run.time)),
                          if (run.startDelayMs > 0 || run.goalMs > 0)
                            Text(
                              [
                                if (run.startDelayMs > 0)
                                  'Delayed start ${_fmtMs(run.startDelayMs)}',
                                if (run.goalMs > 0)
                                  'Goal ${_fmtMs(run.goalMs)}',
                              ].join(' | '),
                            ),
                          const SizedBox(height: 6),
                          _shotMarkChart(
                            _shotMarks(
                              run.firstShotMs > 0 ? run.firstShotMs : null,
                              run.splitMs,
                            ),
                            goalMs: run.goalMs,
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete run',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete saved run?'),
                              content: const Text(
                                'This removes the saved timer run from this session.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                          widget.state.deleteSessionTimerRun(
                            sessionId: widget.sessionId,
                            runId: run.id,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ShotTimerToolScreen extends StatelessWidget {
  final AppState state;

  const ShotTimerToolScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shot Timer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [_StandaloneShotTimerCard(state: state)],
      ),
    );
  }
}

class _StandaloneShotTimerCard extends StatefulWidget {
  final AppState state;

  const _StandaloneShotTimerCard({required this.state});

  @override
  State<_StandaloneShotTimerCard> createState() =>
      _StandaloneShotTimerCardState();
}

class _StandaloneShotTimerCardState extends State<_StandaloneShotTimerCard> {
  final Stopwatch _stopwatch = Stopwatch();
  final TextEditingController _delayCtrl = TextEditingController();
  final TextEditingController _goalCtrl = TextEditingController();
  Timer? _ticker;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  int _baseElapsedMs = 0;
  int _elapsedMs = 0;
  int? _firstShotMs;
  List<int> _splitMs = const [];
  bool _isArmed = false;
  int _countdownRemainingMs = 0;
  int _startDelayMs = 0;
  int _goalMs = 0;
  bool _goalAlertPlayed = false;
  DateTime? _armedUntil;
  bool _audioAssistEnabled = false;
  double _audioThresholdDb = 92;
  double _latestDb = 0;
  DateTime? _lastAudioShotAt;
  String? _audioAssistMessage;
  String? _selectedRifleId;
  int _audioShotCount = 0;

  bool get _isRunning => _stopwatch.isRunning;
  bool get _isActive => _isRunning || _isArmed;
  bool get _audioAssistSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    _selectedRifleId = widget.state.shotTimerSelectedRifleId;
    widget.state.setShotTimerSelectedRifleId(_selectedRifleId);
    _audioThresholdDb = widget.state.audioThresholdDb;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _noiseSubscription?.cancel();
    _stopwatch.stop();
    _delayCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  int _currentElapsedMs() {
    if (!_isRunning) return _elapsedMs;
    return _baseElapsedMs + _stopwatch.elapsedMilliseconds;
  }

  int _lastMarkMs() {
    if (_firstShotMs == null) return 0;
    var total = _firstShotMs!;
    for (final split in _splitMs) {
      total += split;
    }
    return total;
  }

  List<int> _shotMarks(int? firstShotMs, List<int> splitMs) {
    if ((firstShotMs ?? 0) <= 0) return const [];
    final marks = <int>[firstShotMs!];
    var total = firstShotMs;
    for (final split in splitMs) {
      total += split;
      marks.add(total);
    }
    return marks;
  }

  Widget _shotMarkChart(List<int> marks, {int goalMs = 0}) {
    if (marks.isEmpty) {
      return const Text('No shots logged yet.', style: TextStyle(fontSize: 13));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < marks.length; i++)
          Container(
            width: 96,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: goalMs > 0 && marks[i] > goalMs
                  ? Colors.red.withValues(alpha: 0.12)
                  : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: goalMs > 0 && marks[i] > goalMs
                    ? Colors.red.withValues(alpha: 0.55)
                    : Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shot ${i + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: goalMs > 0 && marks[i] > goalMs
                        ? Colors.red.shade700
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtMs(marks[i]),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: goalMs > 0 && marks[i] > goalMs
                        ? Colors.red.shade700
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  int _parseSecondsToMs(String raw) {
    final seconds = double.tryParse(raw.trim()) ?? 0;
    if (seconds <= 0) return 0;
    return (seconds * 1000).round();
  }

  Future<void> _beep() async {
    await _playShotTimerBeep();
  }

  void _beginRun() {
    _stopwatch
      ..reset()
      ..start();
    _baseElapsedMs = _elapsedMs;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) async {
      if (!mounted) return;
      if (_isArmed) {
        final next = math.max(
          0,
          (_armedUntil?.difference(DateTime.now()).inMilliseconds ?? 0),
        );
        if (next <= 0) {
          _beginRun();
          _beep(); // Fire and forget - don't await to avoid blocking timer
          if (!mounted) return;
          setState(() {
            _isArmed = false;
            _countdownRemainingMs = 0;
            _armedUntil = null;
          });
        } else {
          setState(() {
            _countdownRemainingMs = next;
          });
        }
        return;
      }
      if (!_isRunning) return;
      final current = _currentElapsedMs();
      final hitGoal = _goalMs > 0 && !_goalAlertPlayed && current >= _goalMs;
      if (hitGoal) {
        _goalAlertPlayed = true;
        _beep(); // Fire and forget - don't await to avoid blocking timer
        if (!mounted) return;
      }
      setState(() {
        _elapsedMs = current;
      });
    });
  }

  void _recordShotAt(int current) {
    _elapsedMs = current;
    if ((_firstShotMs ?? 0) <= 0) {
      _firstShotMs = current;
    } else {
      final previous = _lastMarkMs();
      final split = current - previous;
      if (split > 0) {
        _splitMs = [..._splitMs, split];
      }
    }
  }

  Future<void> _setAudioAssist(bool enabled) async {
    if (!_audioAssistSupported) {
      setState(() {
        _audioAssistEnabled = false;
        _audioAssistMessage =
            'Audio assist is available on iPhone and Android only.';
      });
      return;
    }
    if (!enabled) {
      await _noiseSubscription?.cancel();
      _noiseSubscription = null;
      if (!mounted) return;
      setState(() {
        _audioAssistEnabled = false;
        _latestDb = 0;
        _audioAssistMessage = null;
      });
      return;
    }

    try {
      await _noiseSubscription?.cancel();
      _noiseSubscription = NoiseMeter().noise.listen(
        (reading) {
          if (!mounted) return;
          final maxDb = reading.maxDecibel;
          final now = DateTime.now();
          final shouldMark =
              _audioAssistEnabled &&
              _isRunning &&
              maxDb >= _audioThresholdDb &&
              (_lastAudioShotAt == null ||
                  now.difference(_lastAudioShotAt!).inMilliseconds >= 250);

          setState(() {
            _latestDb = maxDb;
            if (shouldMark) {
              _lastAudioShotAt = now;
              _recordShotAt(_currentElapsedMs());
            }
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _audioAssistEnabled = false;
            _audioAssistMessage =
                'Microphone unavailable. Check permissions and try again.';
          });
        },
        cancelOnError: true,
      );
      if (!mounted) return;
      setState(() {
        _audioAssistEnabled = true;
        _audioAssistMessage =
            'Audio assist armed. Loud impulses can auto-mark shots.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _audioAssistEnabled = false;
        _audioAssistMessage =
            'Microphone unavailable. Check permissions and try again.';
      });
    }
  }

  void _start() {
    if (_isActive) return;
    _startDelayMs = _parseSecondsToMs(_delayCtrl.text);
    _goalMs = _parseSecondsToMs(_goalCtrl.text);
    _goalAlertPlayed = _goalMs > 0 && _elapsedMs >= _goalMs;
    setState(() {
      _countdownRemainingMs = _startDelayMs;
      _isArmed = _startDelayMs > 0;
      _armedUntil = _startDelayMs > 0
          ? DateTime.now().add(Duration(milliseconds: _startDelayMs))
          : null;
    });
    if (!_isArmed) {
      _beginRun();
    }
    _startTicker();
  }

  void _stop() {
    if (_isArmed) {
      _ticker?.cancel();
      setState(() {
        _isArmed = false;
        _countdownRemainingMs = 0;
        _armedUntil = null;
      });
      return;
    }
    if (!_isRunning) return;
    _ticker?.cancel();
    _stopwatch.stop();
    setState(() {
      _elapsedMs = _currentElapsedMs();
    });
  }

  void _markShot() {
    if (!_isRunning) return;
    final current = _currentElapsedMs();
    setState(() {
      _recordShotAt(current);
    });
  }

  void _reset() {
    _ticker?.cancel();
    _stopwatch
      ..stop()
      ..reset();
    setState(() {
      _isArmed = false;
      _countdownRemainingMs = 0;
      _armedUntil = null;
      _baseElapsedMs = 0;
      _elapsedMs = 0;
      _firstShotMs = null;
      _splitMs = const [];
      _goalAlertPlayed = false;
      _audioShotCount = 0;
    });
  }

  String _fmtMs(int ms) {
    final totalSeconds = (ms / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hundredths = (ms % 1000) ~/ 10;
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
    }
    return '$seconds.${hundredths.toString().padLeft(2, '0')}';
  }

  String _rifleDropdownLabel(Rifle rifle) {
    final name = (rifle.name ?? '').trim();
    if (name.isNotEmpty) return name;
    final modelBits = [
      (rifle.manufacturer ?? '').trim(),
      (rifle.model ?? '').trim(),
    ].where((v) => v.isNotEmpty).toList();
    if (modelBits.isNotEmpty) return modelBits.join(' ');
    return rifle.caliber.trim().isEmpty ? 'Rifle' : rifle.caliber.trim();
  }

  @override
  Widget build(BuildContext context) {
    final totalShotsMarked = (_firstShotMs == null ? 0 : 1) + _splitMs.length;
    final shotMarks = _shotMarks(_firstShotMs, _splitMs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Standalone Shot Timer',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_isArmed)
                  const Chip(
                    label: Text('Armed'),
                    avatar: Icon(Icons.hourglass_top_outlined, size: 18),
                  )
                else if (_isRunning)
                  const Chip(
                    label: Text('Running'),
                    avatar: Icon(Icons.timer_outlined, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isArmed
                  ? _fmtMs(_countdownRemainingMs)
                  : _fmtMs(_currentElapsedMs()),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'First shot: ${_firstShotMs == null ? '-' : _fmtMs(_firstShotMs!)}',
                  ),
                ),
                Chip(
                  label: Text(
                    'Splits: ${_splitMs.isEmpty ? '-' : _splitMs.map(_fmtMs).join(', ')}',
                  ),
                ),
                Chip(label: Text('Marked shots: $totalShotsMarked')),
                if (_startDelayMs > 0)
                  Chip(
                    avatar: const Icon(Icons.hourglass_top_outlined, size: 18),
                    label: Text(
                      'Delayed start: ${(_startDelayMs / 1000).toStringAsFixed(1)}s',
                    ),
                  ),
                if (_goalMs > 0)
                  Chip(
                    avatar: Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: _goalAlertPlayed ? Colors.red.shade700 : null,
                    ),
                    label: Text(
                      'Goal: ${(_goalMs / 1000).toStringAsFixed(1)}s',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Shot Chart',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            _shotMarkChart(shotMarks, goalMs: _goalMs),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    textCapitalization: TextCapitalization.none,
                    controller: _delayCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_isActive,
                    decoration: const InputDecoration(
                      labelText: 'Delayed Start (sec)',
                      helperText: 'Beep after delay',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    textCapitalization: TextCapitalization.none,
                    controller: _goalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_isActive,
                    decoration: const InputDecoration(
                      labelText: 'Time Goal (sec)',
                      helperText: 'Beep at limit',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    if (_isActive) {
                      _stop();
                    } else {
                      _start();
                    }
                  },
                  icon: Icon(
                    _isActive
                        ? Icons.stop_circle_outlined
                        : Icons.play_arrow_outlined,
                  ),
                  label: Text(
                    _isActive
                        ? 'Stop'
                        : ((_elapsedMs > 0 || totalShotsMarked > 0)
                              ? 'Start / Resume'
                              : 'Start'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isRunning ? _markShot : null,
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('Lap / Shot'),
                ),
                TextButton.icon(
                  onPressed:
                      (!_isRunning && (_elapsedMs > 0 || totalShotsMarked > 0))
                      ? _reset
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Use this outside of a session when you just need the timer by itself.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Audio Assist'),
              subtitle: Text(
                _audioAssistSupported
                    ? (_audioAssistEnabled
                          ? 'Microphone listening for loud shot impulses.'
                          : 'Optional microphone assist for auto-marking shots.')
                    : 'Available only in iPhone and Android app builds.',
              ),
              value: _audioAssistEnabled,
              onChanged: (value) => _setAudioAssist(value),
            ),
            if (widget.state.rifles.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _selectedRifleId,
                decoration: const InputDecoration(labelText: 'Apply to Rifle'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No firearm selected'),
                  ),
                  ...widget.state.rifles.map(
                    (rifle) => DropdownMenuItem<String?>(
                      value: rifle.id,
                      child: Text(_rifleDropdownLabel(rifle)),
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() => _selectedRifleId = val);
                  widget.state.setShotTimerSelectedRifleId(val);
                },
              ),
            ],
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-apply audio shot count to rifle'),
              subtitle: Text(
                _selectedRifleId == null
                    ? 'Pick a rifle first, or leave No firearm selected to use timer only.'
                    : 'Increment selected rifle round count for auto-marked audio shots',
              ),
              value: widget.state.shotTimerApplyAudioShotCountToRifle,
              onChanged: _selectedRifleId == null
                  ? null
                  : (v) =>
                        widget.state.setShotTimerApplyAudioShotCountToRifle(v),
            ),
            if (_audioShotCount > 0 && _selectedRifleId != null)
              FilledButton.icon(
                onPressed: () {
                  widget.state.addRifleRounds(
                    rifleId: _selectedRifleId!,
                    roundCount: _audioShotCount,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Applied $_audioShotCount shots to rifle'),
                    ),
                  );
                  setState(() => _audioShotCount = 0);
                },
                icon: const Icon(Icons.check_circle_outline),
                label: Text('Apply $_audioShotCount audio shots to rifle now'),
              ),
            Text(
              'Audio-shot detections: $_audioShotCount',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Beep volume',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
            Slider(
              value: widget.state.shotTimerBeepVolume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: (widget.state.shotTimerBeepVolume * 100)
                  .round()
                  .toString(),
              onChanged: (v) => widget.state.setShotTimerBeepVolume(v),
            ),
            Text(
              'Beep frequency',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
            Slider(
              value: widget.state.shotTimerBeepFrequencyHz,
              min: 400.0,
              max: 3000.0,
              divisions: 52,
              label: widget.state.shotTimerBeepFrequencyHz.toStringAsFixed(0),
              onChanged: (v) => widget.state.setShotTimerBeepFrequencyHz(v),
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _audioThresholdDb,
                    min: 70,
                    max: 120,
                    divisions: 50,
                    label: '${_audioThresholdDb.toStringAsFixed(0)} dB',
                    onChanged: (_audioAssistEnabled && _audioAssistSupported)
                        ? (value) {
                            setState(() => _audioThresholdDb = value);
                            widget.state.setAudioThresholdDb(value);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${_audioThresholdDb.toStringAsFixed(0)} dB'),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('Live level: ${_latestDb.toStringAsFixed(1)} dB'),
                ),
                if (_audioAssistMessage != null)
                  Chip(label: Text(_audioAssistMessage!)),
                if (!_audioAssistSupported)
                  const Chip(label: Text('Phone app only')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SessionDetailScreen extends StatelessWidget {
  final AppState state;
  final String sessionId;
  const SessionDetailScreen({
    super.key,
    required this.state,
    required this.sessionId,
  });

  Map<String, int> _shotCountsByRifle(TrainingSession session) {
    final counts = <String, int>{};

    int timerShotCount(TrainingSession s) {
      int countFromTimerFields() {
        final hasFirst = (s.shotTimerFirstShotMs ?? 0) > 0;
        return (hasFirst ? 1 : 0) + s.shotTimerSplitMs.length;
      }

      int countFromRuns() {
        var total = 0;
        for (final run in s.timerRuns) {
          final hasFirst = run.firstShotMs > 0;
          total += (hasFirst ? 1 : 0) + run.splitMs.length;
        }
        return total;
      }

      final fieldCount = countFromTimerFields();
      if (s.timerRuns.isEmpty) return fieldCount;

      final runFingerprints = s.timerRuns
          .map(
            (run) =>
                '${run.elapsedMs}|${run.firstShotMs}|${run.splitMs.join(',')}',
          )
          .toSet();
      final fieldFingerprint =
          '${s.shotTimerElapsedMs ?? 0}|${s.shotTimerFirstShotMs ?? 0}|${s.shotTimerSplitMs.join(',')}';
      final includeFieldCount =
          fieldCount > 0 && !runFingerprints.contains(fieldFingerprint);

      return countFromRuns() + (includeFieldCount ? fieldCount : 0);
    }

    for (final string in session.strings) {
      final rifleId = string.rifleId;
      if (rifleId == null) continue;
      final shotCountByString =
          (session.shotsByString[string.id] ?? const <ShotEntry>[]).length;
      final dopeCountByString =
          (session.trainingDopeByString[string.id] ?? const <DopeEntry>[])
              .length;
      counts.update(
        rifleId,
        (value) => value + shotCountByString + dopeCountByString,
        ifAbsent: () => shotCountByString + dopeCountByString,
      );
    }

    final timerCount = timerShotCount(session);
    if (timerCount > 0 && session.rifleId != null) {
      counts.update(
        session.rifleId!,
        (value) => value + timerCount,
        ifAbsent: () => timerCount,
      );
    }

    final fallbackTotal = session.confirmedShotCount ?? session.shots.length;
    final countedTotal = counts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    if (session.rifleId != null && fallbackTotal > countedTotal) {
      final missing = fallbackTotal - countedTotal;
      counts.update(
        session.rifleId!,
        (value) => value + missing,
        ifAbsent: () => missing,
      );
    }
    return counts;
  }

  String _sessionRifleLabel(String rifleId) {
    final rifle = state.rifleById(rifleId);
    if (rifle == null) return 'Deleted rifle ($rifleId)';
    final parts = <String>[
      if (rifle.caliber.trim().isNotEmpty) rifle.caliber.trim(),
      if ((rifle.manufacturer ?? '').trim().isNotEmpty)
        (rifle.manufacturer ?? '').trim(),
      if ((rifle.model ?? '').trim().isNotEmpty) (rifle.model ?? '').trim(),
      if ((rifle.name ?? '').trim().isNotEmpty) (rifle.name ?? '').trim(),
    ];
    return parts.isEmpty ? 'Rifle' : parts.join(' • ');
  }

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

  SessionStringMeta? _findMatchingString(
    TrainingSession session, {
    required String? rifleId,
    required String? ammoLotId,
    required String excludeStringId,
  }) {
    if (rifleId == null || ammoLotId == null) return null;
    for (final st in session.strings) {
      if (st.id == excludeStringId) continue;
      if (st.rifleId == rifleId && st.ammoLotId == ammoLotId) {
        return st;
      }
    }
    return null;
  }

  Future<bool> _promptSwitchToExistingStringDialog(
    BuildContext context,
    SessionStringMeta existing,
  ) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch to existing string?'),
        content: Text(
          'This rifle and ammo already exist in a string started on ${_fmtDateTime(existing.startedAt)}. Switch back to that string?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay here'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Rect _shareOriginRect(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const Rect.fromLTWH(0, 0, 1, 1);
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Future<void> _shareSessionFile(
    BuildContext context,
    TrainingSession s,
  ) async {
    try {
      final ownerIdentifier = state.activeUserIdentifier;
      final json = state.exportSharedSessionJson(
        sessionId: s.id,
        ownerIdentifier: ownerIdentifier,
      );
      final ts = DateTime.now();
      final fname =
          'cold_bore_session_${ts.year.toString().padLeft(4, '0')}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}.json';

      if (kIsWeb) {
        _downloadTextFileWeb(fname, json, mimeType: 'application/json');
      } else {
        final bytes = Uint8List.fromList(utf8.encode(json));
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'application/json', name: fname)],
          text: 'Cold Bore shared session',
          sharePositionOrigin: _shareOriginRect(context),
        );
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Session file shared. On the other phone, import the JSON from Backup & Restore.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Session share failed: $e')));
    }
  }

  Future<void> _shareSessionWithColdBoreUsers(
    BuildContext context,
    TrainingSession s,
  ) async {
    final me = state.activeUser;
    if (me == null) return;
    if (_isSeedUserIdentifier(me.identifier)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set a unique user identifier in Manage users before sharing with partners.',
          ),
        ),
      );
      return;
    }

    final others = state.users.where((u) => u.id != me.id).toList();
    final hasTrustedPartners = state.trustedPartnerIdentifiers.isNotEmpty;
    if (others.isEmpty && !hasTrustedPartners) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No other users or trusted partners found. Add another user, pair nearby once, or enter an identifier.',
          ),
        ),
      );
      return;
    }

    final shareResult = await showDialog<_ShareSessionResult>(
      context: context,
      builder: (_) => _ShareSessionDialog(
        sessionTitle: s.locationName.isEmpty ? 'Session' : s.locationName,
        users: others,
        trustedPartnerIdentifiers: state.trustedPartnerIdentifiers,
        initiallySelected: s.memberUserIds.where((id) => id != me.id).toSet(),
        initialExternalIdentifiers: s.externalMemberIdentifiers.toSet(),
        initialShareNotesWithMembers: s.shareNotesWithMembers,
        initialShareTrainingDopeWithMembers: s.shareTrainingDopeWithMembers,
        initialShareLocationWithMembers: s.shareLocationWithMembers,
        initialSharePhotosWithMembers: s.sharePhotosWithMembers,
        initialShareShotResultsWithMembers: s.shareShotResultsWithMembers,
        initialShareTimerDataWithMembers: s.shareTimerDataWithMembers,
      ),
    );

    if (shareResult == null) return;
    final selectedCount =
        shareResult.userIds.length + shareResult.externalIdentifiers.length;
    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recipients selected.')),
      );
      return;
    }

    state.shareSessionWithUsers(
      sessionId: s.id,
      userIds: shareResult.userIds.toList(),
      externalIdentifiers: shareResult.externalIdentifiers.toList(),
      shareNotesWithMembers: shareResult.shareNotesWithMembers,
      shareTrainingDopeWithMembers: shareResult.shareTrainingDopeWithMembers,
      shareLocationWithMembers: shareResult.shareLocationWithMembers,
      sharePhotosWithMembers: shareResult.sharePhotosWithMembers,
      shareShotResultsWithMembers: shareResult.shareShotResultsWithMembers,
      shareTimerDataWithMembers: shareResult.shareTimerDataWithMembers,
    );

    final ownerIdentifier = state.activeUserIdentifier;
    final sessionMap = state.exportSessionMapById(s.id);
    if (ownerIdentifier == null || ownerIdentifier.trim().isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Share settings saved, but cloud delivery is unavailable until this device has a valid Cold Bore user identifier.',
          ),
        ),
      );
      return;
    }
    if (sessionMap == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Share settings saved, but the session could not be prepared for cloud delivery.',
          ),
        ),
      );
      return;
    }

    {
      final localRecipients = shareResult.userIds
          .map((id) {
            try {
              return state.users.firstWhere((u) => u.id == id).identifier;
            } catch (_) {
              return '';
            }
          })
          .where((e) => e.trim().isNotEmpty)
          .toSet();
      final allRecipients = <String>{
        ...localRecipients,
        ...shareResult.externalIdentifiers,
      }.toList();
      for (final recipient in allRecipients) {
        state.rememberTrustedPartnerIdentifier(recipient);
      }

      final result = await CloudSyncService().shareSession(
        sessionId: s.id,
        ownerIdentifier: ownerIdentifier,
        memberIdentifiers: allRecipients,
        sessionMap: sessionMap,
      );
      if (!context.mounted) return;

      if (result.failureMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Share settings saved, but cloud delivery is unavailable: ${result.failureMessage}',
            ),
          ),
        );
        return;
      }

      final normalizedOwner = ownerIdentifier.trim().toUpperCase();
      final deliveredRecipients = result.resolvedIdentifiers
          .where((id) => id != normalizedOwner)
          .toList();
      final pendingRecipients = result.unresolvedIdentifiers
          .where((id) => id != normalizedOwner)
          .toList();

      if (pendingRecipients.isNotEmpty && deliveredRecipients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Share saved, but cloud delivery is still pending for: ${pendingRecipients.join(', ')}. The other phone must have Cold Bore open with that exact user identifier.',
            ),
          ),
        );
      } else if (pendingRecipients.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Delivered to ${deliveredRecipients.join(', ')}. Still pending for: ${pendingRecipients.join(', ')}.',
            ),
          ),
        );
      } else if (deliveredRecipients.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Session delivered to ${deliveredRecipients.join(', ')}.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _shareSessionNearby(
    BuildContext context,
    TrainingSession s,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nearby in-app sharing is currently available on iPhone.',
          ),
        ),
      );
      return;
    }

    final ownerIdentifier = state.activeUserIdentifier?.trim().toUpperCase();
    if (ownerIdentifier == null || ownerIdentifier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create or select a user identifier first.'),
        ),
      );
      return;
    }
    if (_isSeedUserIdentifier(ownerIdentifier)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set a unique user identifier in Manage users before using nearby partner sharing.',
          ),
        ),
      );
      return;
    }

    final json = state.exportSharedSessionJson(
      sessionId: s.id,
      ownerIdentifier: ownerIdentifier,
    );

    await _refreshNearbyPresenceForShare();
    await _nearbyShareChannel.invokeMethod('setSharePayload', {
      'jsonText': json,
    });

    var selectedPeerIdentifier = '';
    await showDialog<void>(
      context: context,
      builder: (_) => _NearbySessionShareDialog(
        state: state,
        onRefresh: _refreshNearbyPresenceForShare,
        onSelectPeer: (peer) async {
          selectedPeerIdentifier = peer.identifier;
          await _nearbyShareChannel.invokeMethod('invitePeer', {
            'identifier': peer.identifier,
          });
        },
      ),
    );

    if (selectedPeerIdentifier.isEmpty) {
      await _nearbyShareChannel.invokeMethod('clearSharePayload');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nearby sharing cancelled. Both phones need Cold Bore open nearby.',
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sending session nearby to $selectedPeerIdentifier...'),
      ),
    );
  }

  Future<void> _refreshNearbyPresenceForShare() async {
    final identifier = state.activeUserIdentifier?.trim().toUpperCase();
    if (identifier == null || identifier.isEmpty) {
      state.setNearbyStatusMessage(
        'Nearby discovery is unavailable until a user identifier is set.',
      );
      await _stopNearbyPresenceForShare();
      return;
    }
    if (_isSeedUserIdentifier(identifier)) {
      state.setNearbyStatusMessage(
        'Set a unique user identifier to discover nearby Cold Bore users.',
      );
      await _stopNearbyPresenceForShare();
      return;
    }

    final activeUser = state.activeUser;
    final displayName = activeUser == null
        ? _displayUserIdentifier(identifier)
        : _displayUserName(activeUser);
    try {
      await _nearbyShareChannel.invokeMethod('startPresence', {
        'identifier': identifier,
        'displayName': displayName,
      });
      state.setNearbyStatusMessage(
        'Nearby discovery running as $identifier. Waiting for other Cold Bore users...',
      );
    } catch (e, st) {
      debugPrint('Nearby presence start failed from session share: $e\n$st');
      state.setNearbyStatusMessage(
        'Nearby discovery failed to start. Check Local Network permission and try again.',
      );
    }
  }

  Future<void> _stopNearbyPresenceForShare() async {
    state.setNearbyPeers(const <NearbyPeer>[]);
    state.setNearbyStatusMessage('Nearby discovery stopped.');
    try {
      await _nearbyShareChannel.invokeMethod('stopPresence');
    } catch (e, st) {
      debugPrint('Nearby presence stop failed from session share: $e\n$st');
    }
  }

  Future<void> _shareSession(BuildContext context, TrainingSession s) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (defaultTargetPlatform == TargetPlatform.iOS)
              ListTile(
                leading: const Icon(Icons.wifi_tethering_outlined),
                title: const Text('Share nearby in Cold Bore'),
                subtitle: const Text(
                  'Send directly to another nearby iPhone running Cold Bore.',
                ),
                onTap: () => Navigator.of(sheetContext).pop('nearby'),
              ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Share with Cold Bore user'),
              subtitle: const Text(
                'Sync to another identifier or user profile.',
              ),
              onTap: () => Navigator.of(sheetContext).pop('cloud'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_iphone_outlined),
              title: Text(
                defaultTargetPlatform == TargetPlatform.iOS
                    ? 'Send session file by AirDrop'
                    : 'Send session file',
              ),
              subtitle: const Text(
                'Nearby phones can receive a JSON file that Cold Bore can import.',
              ),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
          ],
        ),
      ),
    );

    if (action == 'nearby') {
      await _shareSessionNearby(context, s);
      return;
    }
    if (action == 'file') {
      await _shareSessionFile(context, s);
      return;
    }
    if (action == 'cloud') {
      await _shareSessionWithColdBoreUsers(context, s);
    }
  }

  Future<void> _addColdBore(BuildContext context, TrainingSession s) async {
    if (!await _guardWrite(context)) return;
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
      notes: res.notes,
      offsetX: res.offsetX,
      offsetY: res.offsetY,
      offsetUnit: res.offsetUnit,
      photoBytes: res.photoBytes,
    );
  }

  Future<void> _addPhotoNote(BuildContext context, TrainingSession s) async {
    if (!await _guardWrite(context)) return;
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _PhotoNoteDialog(),
    );
    if (res == null || res.trim().isEmpty) return;

    state.addPhotoNote(sessionId: s.id, time: DateTime.now(), caption: res);
  }

  Future<void> _editTrainingNotes(
    BuildContext context,
    TrainingSession s,
  ) async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _EditNotesDialog(initialNotes: s.notes),
    );
    if (res == null) return;
    state.updateSessionNotes(sessionId: s.id, notes: res);
  }

  Future<DateTime?> _pickSessionDateTime(
    BuildContext context, {
    required DateTime initial,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return null;
    if (!context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      initialEntryMode: TimePickerEntryMode.inputOnly,
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _editSessionDateTimes(
    BuildContext context,
    TrainingSession s,
  ) async {
    var startAt = s.dateTime;
    var hasEnd = s.endedAt != null;
    var endAt = s.endedAt ?? DateTime.now();
    String? errorText;
    var didSave = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit session date & time'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Start: ${_fmtDateTime(startAt)}'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await _pickSessionDateTime(
                              context,
                              initial: startAt,
                            );
                            if (picked == null || !context.mounted) return;
                            setState(() {
                              startAt = picked;
                              if (hasEnd && endAt.isBefore(startAt)) {
                                errorText =
                                    'End time cannot be earlier than start time.';
                              } else {
                                errorText = null;
                              }
                            });
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: const Text('Change'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: hasEnd,
                      onChanged: (value) {
                        setState(() {
                          hasEnd = value;
                          if (!hasEnd) {
                            errorText = null;
                          } else if (endAt.isBefore(startAt)) {
                            endAt = startAt;
                            errorText = null;
                          }
                        });
                      },
                      title: const Text('Session ended'),
                      subtitle: const Text(
                        'Turn off to keep the session active.',
                      ),
                    ),
                    if (hasEnd)
                      Row(
                        children: [
                          Expanded(child: Text('End: ${_fmtDateTime(endAt)}')),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await _pickSessionDateTime(
                                context,
                                initial: endAt,
                              );
                              if (picked == null || !context.mounted) return;
                              setState(() {
                                endAt = picked;
                                if (endAt.isBefore(startAt)) {
                                  errorText =
                                      'End time cannot be earlier than start time.';
                                } else {
                                  errorText = null;
                                }
                              });
                            },
                            icon: const Icon(Icons.schedule_outlined),
                            label: const Text('Change'),
                          ),
                        ],
                      ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (hasEnd && endAt.isBefore(startAt)) {
                      setState(() {
                        errorText =
                            'End time cannot be earlier than start time.';
                      });
                      return;
                    }
                    state.updateSessionDateTimes(
                      sessionId: s.id,
                      startedAt: startAt,
                      endedAt: hasEnd ? endAt : null,
                      clearEndedAt: !hasEnd,
                    );
                    didSave = true;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!context.mounted || !didSave) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session date/time updated.')));
  }

  Future<void> _endSession(BuildContext context, TrainingSession s) async {
    final shotCountsByRifle = _shotCountsByRifle(s);
    final res = await showDialog<_EndSessionResult>(
      context: context,
      builder: (_) => _EndSessionDialog(
        rifleCounts: shotCountsByRifle.entries
            .map(
              (entry) => _EndSessionRifleCount(
                rifleId: entry.key,
                label: _sessionRifleLabel(entry.key),
                initialShotCount: entry.value,
              ),
            )
            .toList(),
      ),
    );
    if (res == null) return;
    state.endSession(
      sessionId: s.id,
      confirmedShotCount: res.totalShotCount,
      appliedShotCounts: res.appliedShotCounts,
    );
    if (!context.mounted) return;
    final appliedTotal = res.appliedShotCounts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          appliedTotal > 0
              ? 'Session ended. ${res.totalShotCount} shots saved, $appliedTotal applied to rifle rounds.'
              : 'Session ended. Shot count saved: ${res.totalShotCount}.',
        ),
      ),
    );
  }

  Future<void> _exportSessionReport(
    BuildContext context,
    TrainingSession s,
  ) async {
    bool redact = true;
    bool includeB64 = false;
    final activeUserId = state.activeUser?.id;
    final isSessionOwner = activeUserId != null && activeUserId == s.userId;
    final accepted = state.sharedFieldAcceptanceForSession(s.id);
    final canShareNotes =
        isSessionOwner ||
        (s.shareNotesWithMembers &&
            accepted[AppState.sharedFieldNotes] == true);
    final canShareTrainingDope =
        isSessionOwner ||
        (s.shareTrainingDopeWithMembers &&
            accepted[AppState.sharedFieldTrainingDope] == true);
    final canShareLocation =
        isSessionOwner ||
        (s.shareLocationWithMembers &&
            accepted[AppState.sharedFieldLocation] == true);
    final canSharePhotos =
        isSessionOwner ||
        (s.sharePhotosWithMembers &&
            accepted[AppState.sharedFieldPhotos] == true);
    final canShareShotResults =
        isSessionOwner ||
        (s.shareShotResultsWithMembers &&
            accepted[AppState.sharedFieldShotResults] == true);
    final canShareTimerData =
        isSessionOwner ||
        (s.shareTimerDataWithMembers &&
            accepted[AppState.sharedFieldTimerData] == true);

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final packet = _buildSessionReportText(
              state,
              s: s,
              redactLocation: redact,
              includePhotoBase64: includeB64,
              includeNotes: canShareNotes,
              includeTrainingDope: canShareTrainingDope,
              includeLocation: canShareLocation,
              includePhotos: canSharePhotos,
              includeShotResults: canShareShotResults,
              includeTimerData: canShareTimerData,
            );

            return AlertDialog(
              title: const Text('Session report'),
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
                      child: SingleChildScrollView(
                        child: SelectableText(packet),
                      ),
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
                      const SnackBar(
                        content: Text('Session report copied to clipboard.'),
                      ),
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

  Future<void> _editAcceptedSharedData(
    BuildContext context,
    TrainingSession s,
  ) async {
    final activeUserId = state.activeUser?.id;
    final isSessionOwner = activeUserId != null && activeUserId == s.userId;
    if (isSessionOwner) return;

    final accepted = state.sharedFieldAcceptanceForSession(s.id);
    var acceptNotes = accepted[AppState.sharedFieldNotes] == true;
    var acceptTrainingDope = accepted[AppState.sharedFieldTrainingDope] == true;
    var acceptLocation = accepted[AppState.sharedFieldLocation] == true;
    var acceptPhotos = accepted[AppState.sharedFieldPhotos] == true;
    var acceptShotResults = accepted[AppState.sharedFieldShotResults] == true;
    var acceptTimerData = accepted[AppState.sharedFieldTimerData] == true;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Accepted shared data'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accept notes'),
                      subtitle: s.shareNotesWithMembers
                          ? null
                          : const Text('Owner did not share this field.'),
                      value: s.shareNotesWithMembers && acceptNotes,
                      onChanged: s.shareNotesWithMembers
                          ? (v) => setState(() => acceptNotes = v)
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accept training DOPE'),
                      subtitle: s.shareTrainingDopeWithMembers
                          ? null
                          : const Text('Owner did not share this field.'),
                      value:
                          s.shareTrainingDopeWithMembers && acceptTrainingDope,
                      onChanged: s.shareTrainingDopeWithMembers
                          ? (v) => setState(() => acceptTrainingDope = v)
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accept location and GPS'),
                      subtitle: s.shareLocationWithMembers
                          ? null
                          : const Text('Owner did not share this field.'),
                      value: s.shareLocationWithMembers && acceptLocation,
                      onChanged: s.shareLocationWithMembers
                          ? (v) => setState(() => acceptLocation = v)
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accept photos and photo notes'),
                      subtitle: s.sharePhotosWithMembers
                          ? null
                          : const Text('Owner did not share this field.'),
                      value: s.sharePhotosWithMembers && acceptPhotos,
                      onChanged: s.sharePhotosWithMembers
                          ? (v) => setState(() => acceptPhotos = v)
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accept shot results'),
                      subtitle: s.shareShotResultsWithMembers
                          ? null
                          : const Text('Owner did not share this field.'),
                      value: s.shareShotResultsWithMembers && acceptShotResults,
                      onChanged: s.shareShotResultsWithMembers
                          ? (v) => setState(() => acceptShotResults = v)
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accept timer data'),
                      subtitle: s.shareTimerDataWithMembers
                          ? null
                          : const Text('Owner did not share this field.'),
                      value: s.shareTimerDataWithMembers && acceptTimerData,
                      onChanged: s.shareTimerDataWithMembers
                          ? (v) => setState(() => acceptTimerData = v)
                          : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    state.setSessionAcceptedSharedFields(
                      sessionId: s.id,
                      acceptNotes: s.shareNotesWithMembers
                          ? acceptNotes
                          : false,
                      acceptTrainingDope: s.shareTrainingDopeWithMembers
                          ? acceptTrainingDope
                          : false,
                      acceptLocation: s.shareLocationWithMembers
                          ? acceptLocation
                          : false,
                      acceptPhotos: s.sharePhotosWithMembers
                          ? acceptPhotos
                          : false,
                      acceptShotResults: s.shareShotResultsWithMembers
                          ? acceptShotResults
                          : false,
                      acceptTimerData: s.shareTimerDataWithMembers
                          ? acceptTimerData
                          : false,
                    );
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shared data preferences updated.')),
    );
  }

  Future<void> _addDope(BuildContext context, TrainingSession s) async {
    if (!await _guardWrite(context)) return;
    if (s.rifleId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a rifle first.')));
      return;
    }
    if (s.ammoLotId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select ammo first.')));
      return;
    }

    final rifle = state.rifleById(s.rifleId);
    final ammoOptions = (rifle == null)
        ? <AmmoLot>[]
        : state.ammoLots.where((a) => a.caliber == rifle.caliber).toList();
    if (ammoOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No compatible ammo lots found for this rifle.'),
        ),
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
          lockedUnit: (rifle?.scopeUnit == ScopeUnit.moa
              ? ElevationUnit.moa
              : ElevationUnit.mil),
        );
      },
    );
    if (res == null) return;

    if (res.promote) {
      if (s.rifleId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a rifle in Loadout to promote DOPE.'),
          ),
        );
        return;
      }
      if (!res.rifleOnly && res.entry.ammoLotId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select ammo to promote to Rifle + Ammo scope.'),
          ),
        );
        return;
      }

      final key = res.rifleOnly
          ? s.rifleId!
          : '${s.rifleId}_${res.entry.ammoLotId}';
      final existingBucket = res.rifleOnly
          ? state.workingDopeRifleOnly[key]
          : state.workingDopeRifleAmmo[key];

      if (existingBucket != null && existingBucket.isNotEmpty) {
        final choice = await showDialog<_WorkingDopeConflictChoice>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Working DOPE already exists'),
            content: Text(
              'This ${res.rifleOnly ? 'rifle' : 'rifle + ammo'} combo already has working DOPE. Replace existing entries or add both?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, _WorkingDopeConflictChoice.addBoth),
                child: const Text('Add Both'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _WorkingDopeConflictChoice.replace),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        if (choice == _WorkingDopeConflictChoice.replace) {
          state.clearWorkingDopeBucket(
            rifleOnly: res.rifleOnly,
            bucketKey: key,
          );
        }
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

  Future<void> _promoteSuggestedDope(
    BuildContext context, {
    required TrainingSession session,
    required DopeEntry entry,
    required bool rifleOnly,
    required bool replacing,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          replacing ? 'Replace working DOPE?' : 'Save to working DOPE?',
        ),
        content: Text(
          '${entry.distance.toStringAsFixed(0)} ${entry.distanceUnit == DistanceUnit.yards ? 'yd' : 'm'}'
          ' will be ${replacing ? 'replaced' : 'saved'} in ${rifleOnly ? 'Rifle only' : 'Rifle + Ammo'} working DOPE.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(replacing ? 'Replace' : 'Save'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    state.promoteExistingDope(entry: entry, rifleOnly: rifleOnly);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Working DOPE ${replacing ? 'updated' : 'saved'} for ${entry.distance.toStringAsFixed(0)} ${entry.distanceUnit == DistanceUnit.yards ? 'yd' : 'm'}.',
          ),
        ),
      );
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

        String joinNonEmptyParts(List<String?> parts) {
          final out = <String>[];
          for (final p in parts) {
            final v = (p ?? '').trim();
            if (v.isNotEmpty) out.add(v);
          }
          return out.join(' • ');
        }

        final rifleDesc = (rifle == null)
            ? (s.rifleId == null ? '-' : 'Deleted (${s.rifleId})')
            : joinNonEmptyParts([
                rifle.caliber,
                rifle.manufacturer,
                rifle.model,
                (rifle.name ?? '').trim().isEmpty ? null : rifle.name,
              ]);

        final ammoDesc = (ammo == null)
            ? (s.ammoLotId == null ? '-' : 'Deleted (${s.ammoLotId})')
            : joinNonEmptyParts([
                ammo.caliber,
                ammo.manufacturer,
                (ammo.bullet.isNotEmpty ? ammo.bullet : (ammo.name ?? 'Ammo')),
                ammo.grain > 0 ? '${ammo.grain}gr' : null,
              ]);
        final compatibleAmmo = (rifle == null)
            ? <AmmoLot>[]
            : state.ammoLots.where((a) => a.caliber == rifle.caliber).toList();
        final activeUserId = state.activeUser?.id;
        final isSessionOwner = activeUserId != null && activeUserId == s.userId;
        final ownerIdentifier = (() {
          try {
            return state.users.firstWhere((u) => u.id == s.userId).identifier;
          } catch (_) {
            return s.userId;
          }
        })();
        final accepted = state.sharedFieldAcceptanceForSession(s.id);
        final canViewNotes =
            isSessionOwner ||
            (s.shareNotesWithMembers &&
                accepted[AppState.sharedFieldNotes] == true);
        final canViewTrainingDope =
            isSessionOwner ||
            (s.shareTrainingDopeWithMembers &&
                accepted[AppState.sharedFieldTrainingDope] == true);
        final canViewLocation =
            isSessionOwner ||
            (s.shareLocationWithMembers &&
                accepted[AppState.sharedFieldLocation] == true);
        final canViewPhotos =
            isSessionOwner ||
            (s.sharePhotosWithMembers &&
                accepted[AppState.sharedFieldPhotos] == true);
        final canViewShotResults =
            isSessionOwner ||
            (s.shareShotResultsWithMembers &&
                accepted[AppState.sharedFieldShotResults] == true);
        final canViewTimerData =
            isSessionOwner ||
            (s.shareTimerDataWithMembers &&
                accepted[AppState.sharedFieldTimerData] == true);

        String rifleLoadoutLabel(Rifle? r, {String? deletedId}) {
          if (r == null) {
            return deletedId == null
                ? '- None -'
                : 'Deleted rifle ($deletedId)';
          }
          final parts = <String>[
            if ((r.manufacturer ?? '').trim().isNotEmpty)
              (r.manufacturer ?? '').trim(),
            if ((r.model ?? '').trim().isNotEmpty) (r.model ?? '').trim(),
            if (r.caliber.trim().isNotEmpty) r.caliber.trim(),
            if ((r.name ?? '').trim().isNotEmpty) (r.name ?? '').trim(),
          ];
          return parts.isEmpty ? 'Rifle' : parts.join(' • ');
        }

        String ammoLoadoutLabel(AmmoLot? a, {String? deletedId}) {
          if (a == null) {
            return deletedId == null ? '- None -' : 'Deleted ammo ($deletedId)';
          }
          final modelOrNickname = [
            a.bullet.trim(),
            (a.name ?? '').trim(),
          ].where((v) => v.isNotEmpty).join(' / ');
          final parts = <String>[
            if ((a.manufacturer ?? '').trim().isNotEmpty)
              (a.manufacturer ?? '').trim(),
            if (modelOrNickname.isNotEmpty) modelOrNickname,
            if (a.caliber.trim().isNotEmpty) a.caliber.trim(),
            if (a.grain > 0) '${a.grain}gr',
          ];
          return parts.isEmpty ? 'Ammo' : parts.join(' • ');
        }

        // Defensive: avoid DropdownButton value mismatch and duplicate IDs.
        final rifleById = <String, Rifle>{
          for (final r in state.rifles) r.id: r,
        };
        final compatibleAmmoById = <String, AmmoLot>{
          for (final a in compatibleAmmo) a.id: a,
        };

        final ammoIsCompatible =
            s.ammoLotId == null || compatibleAmmoById.containsKey(s.ammoLotId);
        final safeAmmoLotId = ammoIsCompatible ? s.ammoLotId : null;

        final currentTrainingDope =
            s.trainingDopeByString[s.activeStringId] ?? const <DopeEntry>[];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Session'),
            actions: [
              IconButton(
                tooltip: 'Share session',
                onPressed: () => _shareSession(context, s),
                icon: const Icon(Icons.share_outlined),
              ),
              if (!isSessionOwner)
                IconButton(
                  tooltip: 'Accepted shared data',
                  onPressed: () => _editAcceptedSharedData(context, s),
                  icon: const Icon(Icons.fact_check_outlined),
                ),
              IconButton(
                tooltip: 'Edit session notes',
                onPressed: () => _editTrainingNotes(context, s),
                icon: const Icon(Icons.edit_note_outlined),
              ),
              IconButton(
                tooltip: 'Edit session date/time',
                onPressed: () => _editSessionDateTimes(context, s),
                icon: const Icon(Icons.event_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                itemBuilder: (context) => [
                  if (s.endedAt == null)
                    const PopupMenuItem(
                      value: 'end_session',
                      child: Text('End session'),
                    ),
                  const PopupMenuItem(
                    value: 'session_report',
                    child: Text('Export session report'),
                  ),
                ],
                onSelected: (v) async {
                  if (v == 'end_session') {
                    await _endSession(context, s);
                    return;
                  }
                  if (v == 'session_report') {
                    await _exportSessionReport(context, s);
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
          bottomNavigationBar: s.endedAt != null
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton.icon(
                    onPressed: () => _endSession(context, s),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('End Session'),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                canViewLocation
                    ? (s.locationName.isEmpty ? 'Session' : s.locationName)
                    : 'Private location',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(_fmtDateTime(s.dateTime)),
              if (!isSessionOwner) ...[
                const SizedBox(height: 4),
                Text(
                  'Shared by: $ownerIdentifier',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (s.endedAt != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text('Ended ${_fmtDateTime(s.endedAt!)}'),
                    ),
                    Chip(
                      avatar: const Icon(Icons.pin_outlined, size: 18),
                      label: Text(
                        'Shot count ${s.confirmedShotCount ?? s.shots.length}${s.shotCountAppliedToRifle ? ' | applied to rifles' : ''}',
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Session information',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText('Session ID: ${s.id}'),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          'Date/Time: ${_fmtDateTime(s.dateTime)}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          'Location: ${canViewLocation ? (s.locationName.isEmpty ? '-' : s.locationName) : '[PRIVATE]'}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          'Status: ${s.endedAt == null ? 'Active' : 'Ended ${_fmtDateTime(s.endedAt!)}'}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          'Confirmed shot count: ${s.confirmedShotCount ?? s.shots.length}${s.shotCountAppliedToRifle ? ' (applied to rifle rounds)' : ''}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          canViewTimerData
                              ? 'Shot timer: ${(s.shotTimerElapsedMs ?? 0) > 0 ? '${(s.shotTimerElapsedMs! / 1000).toStringAsFixed(3)}s total' : '-'}'
                                    '${(s.shotTimerFirstShotMs ?? 0) > 0 ? ' • first ${(s.shotTimerFirstShotMs! / 1000).toStringAsFixed(3)}s' : ''}'
                                    '${s.shotTimerSplitMs.isNotEmpty ? ' • ${s.shotTimerSplitMs.length} split${s.shotTimerSplitMs.length == 1 ? '' : 's'}' : ''}'
                                    '${s.timerRuns.isNotEmpty ? ' • ${s.timerRuns.length} saved run${s.timerRuns.length == 1 ? '' : 's'}' : ''}'
                              : 'Shot timer: [PRIVATE]',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText('Rifle: $rifleDesc'),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText('Ammo: $ammoDesc'),
                      ),
                    ],
                  ),
                ),
              ),
              _SectionTitle('Notes'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        canViewNotes
                            ? (s.notes.isEmpty
                                  ? 'No notes yet. Tap Edit to add session notes.'
                                  : s.notes)
                            : 'Notes are private for this shared session.',
                      ),
                      const SizedBox(height: 8),
                      if (canViewNotes)
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
              _SectionTitle('String'),
              const SizedBox(height: 8),
              _StringSummaryCard(state: state, session: s),
              const SizedBox(height: 16),
              _SectionTitle('Loadout'),
              const SizedBox(height: 8),
              Column(
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: s.rifleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Rifle'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('- None -'),
                      ),
                      if (s.rifleId != null && rifle == null)
                        DropdownMenuItem<String?>(
                          value: s.rifleId,
                          child: Text('Deleted rifle (${s.rifleId})'),
                        ),
                      ...state.rifles.map(
                        (r) => DropdownMenuItem<String?>(
                          value: r.id,
                          child: Text(
                            rifleLoadoutLabel(r),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ),
                    ],
                    selectedItemBuilder: (context) => [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '- None -',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (s.rifleId != null && rifle == null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            rifleLoadoutLabel(null, deletedId: s.rifleId),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ...state.rifles.map(
                        (r) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            rifleLoadoutLabel(r),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == s.rifleId) return;

                      final current = s.strings.firstWhere(
                        (x) => x.id == s.activeStringId,
                        orElse: () => s.strings.isNotEmpty
                            ? s.strings.last
                            : SessionStringMeta(
                                id: s.activeStringId,
                                startedAt: DateTime.now(),
                                endedAt: null,
                              ),
                      );

                      // If we haven't completed a loadout yet, just set it (no prompt).
                      if (current.rifleId == null ||
                          current.ammoLotId == null) {
                        state.updateSessionLoadout(
                          sessionId: s.id,
                          rifleId: v,
                          ammoLotId: s.ammoLotId,
                          startNewString: false,
                        );
                        return;
                      }

                      if (v == null) {
                        state.updateSessionLoadout(
                          sessionId: s.id,
                          rifleId: null,
                          ammoLotId: null,
                          startNewString: false,
                        );
                        return;
                      }

                      final nextAmmo =
                          ((s.ammoLotId != null) &&
                              (state.ammoById(s.ammoLotId)?.caliber ==
                                  state.rifleById(v)?.caliber))
                          ? s.ammoLotId
                          : null;
                      final existing = _findMatchingString(
                        s,
                        rifleId: v,
                        ammoLotId: nextAmmo,
                        excludeStringId: current.id,
                      );
                      if (existing != null) {
                        final shouldSwitch =
                            await _promptSwitchToExistingStringDialog(
                              context,
                              existing,
                            );
                        if (shouldSwitch) {
                          state.setActiveString(
                            sessionId: s.id,
                            stringId: existing.id,
                          );
                          return;
                        }
                      }

                      final startNew = await _promptStartNewStringDialog(
                        context,
                      );
                      if (!startNew) {
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
                        rifleId: v,
                        ammoLotId: s.ammoLotId,
                        startNewString: true,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: safeAmmoLotId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Ammo'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('- None -'),
                      ),
                      if (s.ammoLotId != null && ammo == null)
                        DropdownMenuItem<String?>(
                          value: s.ammoLotId,
                          child: Text('Deleted ammo (${s.ammoLotId})'),
                        ),
                      ...compatibleAmmo.map(
                        (a) => DropdownMenuItem<String?>(
                          value: a.id,
                          child: Text(
                            ammoLoadoutLabel(a),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ),
                    ],
                    selectedItemBuilder: (context) => [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '- None -',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (s.ammoLotId != null && ammo == null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            ammoLoadoutLabel(null, deletedId: s.ammoLotId),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ...compatibleAmmo.map(
                        (a) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            ammoLoadoutLabel(a),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (rifle == null)
                        ? null
                        : (v) async {
                            if (v == s.ammoLotId) return;

                            final current = s.strings.firstWhere(
                              (x) => x.id == s.activeStringId,
                              orElse: () => s.strings.isNotEmpty
                                  ? s.strings.last
                                  : SessionStringMeta(
                                      id: s.activeStringId,
                                      startedAt: DateTime.now(),
                                      endedAt: null,
                                    ),
                            );

                            // If we haven't completed a loadout yet, just set it (no prompt).
                            if (current.rifleId == null ||
                                current.ammoLotId == null) {
                              state.updateSessionLoadout(
                                sessionId: s.id,
                                rifleId: s.rifleId,
                                ammoLotId: v,
                                startNewString: false,
                              );
                              return;
                            }

                            if (v == null) {
                              state.updateSessionLoadout(
                                sessionId: s.id,
                                rifleId: s.rifleId,
                                ammoLotId: null,
                                startNewString: false,
                              );
                              return;
                            }

                            // Only prompt when BOTH rifle + ammo are selected (i.e., loadout is complete).
                            if (s.rifleId != null) {
                              final nextRifle = s.rifleId;
                              final nextAmmo = v;

                              final changed =
                                  (nextRifle != current.rifleId) ||
                                  (nextAmmo != current.ammoLotId);
                              if (!changed) return;

                              final existing = _findMatchingString(
                                s,
                                rifleId: nextRifle,
                                ammoLotId: nextAmmo,
                                excludeStringId: current.id,
                              );
                              if (existing != null) {
                                final shouldSwitch =
                                    await _promptSwitchToExistingStringDialog(
                                      context,
                                      existing,
                                    );
                                if (shouldSwitch) {
                                  state.setActiveString(
                                    sessionId: s.id,
                                    stringId: existing.id,
                                  );
                                  return;
                                }
                              }

                              final startNew =
                                  await _promptStartNewStringDialog(context);
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
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _SectionTitle('Training DOPE')),
                  if (canViewTrainingDope)
                    TextButton.icon(
                      onPressed: () => _addDope(context, s),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!canViewTrainingDope)
                _HintCard(
                  icon: Icons.lock_outline,
                  title: 'Training DOPE is private',
                  message:
                      'The session owner has chosen not to share training DOPE for this session.',
                )
              else if (s.trainingDope.isEmpty)
                _HintCard(
                  icon: Icons.my_location_outlined,
                  title: 'No training DOPE yet',
                  message:
                      'Add dialed elevation/wind for this session. It will stay saved on the session.',
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
                        : (e.windageRight > 0
                              ? 'R ${e.windageRight.toStringAsFixed(2)}'
                              : '-');
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${e.distance} ${e.distanceUnit.name}  •  ${e.elevation.toStringAsFixed(2)} ${e.elevationUnit.name.toUpperCase()}',
                        ),
                        subtitle: Text(
                          'Wind: $wind${e.windNotes.trim().isEmpty ? '' : ' • ${e.windNotes.trim()}'}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete DOPE',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text(
                                  'Delete training DOPE entry?',
                                ),
                                content: const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            state.deleteTrainingDopeEntry(
                              sessionId: s.id,
                              dopeEntryId: e.id,
                            );
                          },
                        ),
                      ),
                    );
                  }).toList();
                })(),
              const SizedBox(height: 16),
              _SectionTitle('Cold Bore Entries'),
              const SizedBox(height: 8),
              if (!canViewShotResults)
                _HintCard(
                  icon: Icons.lock_outline,
                  title: 'Shot results are private',
                  message:
                      'The session owner has chosen not to share shot results for this session.',
                )
              else if (s.shots.where((x) => x.isColdBore).isEmpty)
                _HintCard(
                  icon: Icons.ac_unit_outlined,
                  title: 'No cold bore entries yet',
                  message:
                      'Tap "Add Cold Bore" to log the first shot for this session.',
                )
              else
                ...s.shots
                    .where((x) => x.isColdBore)
                    .map(
                      (shot) => Card(
                        child: ListTile(
                          leading: Icon(
                            shot.isBaseline
                                ? Icons.star
                                : Icons.ac_unit_outlined,
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
                  Expanded(
                    child: _SectionTitle('Working DOPE (quick reference)'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DataScreen(state: state),
                        ),
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
                  if (!canViewTrainingDope) {
                    return _HintCard(
                      icon: Icons.lock_outline,
                      title: 'Working DOPE is private',
                      message:
                          'The session owner has chosen not to share DOPE for this session.',
                    );
                  }

                  if (s.rifleId == null) {
                    return _HintCard(
                      icon: Icons.info_outline,
                      title: 'Select a rifle',
                      message:
                          'Choose a rifle in Loadout to view working DOPE.',
                    );
                  }

                  final rifleKey = s.rifleId!;
                  final ammoKey = (s.ammoLotId == null)
                      ? null
                      : '${s.rifleId}_${s.ammoLotId}';
                  final rifleAmmoMap = (ammoKey == null)
                      ? null
                      : state.workingDopeRifleAmmo[ammoKey];
                  final rifleOnlyMap = state.workingDopeRifleOnly[rifleKey];

                  final ammoScopedMap =
                      rifleAmmoMap ?? <DistanceKey, DopeEntry>{};
                  final rifleScopedMap =
                      rifleOnlyMap ?? <DistanceKey, DopeEntry>{};
                  final useMap = <DistanceKey, DopeEntry>{
                    ...rifleScopedMap,
                    ...ammoScopedMap,
                  };

                  final hasAmmoScoped = ammoScopedMap.isNotEmpty;
                  final hasRifleOnly = rifleScopedMap.isNotEmpty;
                  final scopeLabel = hasAmmoScoped && hasRifleOnly
                      ? 'Rifle + Ammo (with Rifle only fallback)'
                      : (hasAmmoScoped ? 'Rifle + Ammo' : 'Rifle only');

                  if (useMap.isEmpty) {
                    return _HintCard(
                      icon: Icons.my_location_outlined,
                      title: 'No working DOPE yet',
                      message:
                          'Promote DOPE from Training DOPE (when adding an entry) or add it in Data.',
                    );
                  }

                  final dks = useMap.keys.toList()
                    ..sort((a, b) => a.value.compareTo(b.value));

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          scopeLabel,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      ...dks.map((dk) {
                        final e = useMap[dk]!;
                        final wind = (e.windageLeft > 0)
                            ? 'L ${e.windageLeft.toStringAsFixed(2)}'
                            : (e.windageRight > 0
                                  ? 'R ${e.windageRight.toStringAsFixed(2)}'
                                  : '-');
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
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete working DOPE',
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text(
                                      'Delete working DOPE entry?',
                                    ),
                                    content: const Text(
                                      'This cannot be undone.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;

                                final fromAmmoScoped =
                                    ammoKey != null &&
                                    (rifleAmmoMap?.containsKey(dk) ?? false);
                                final fromRifleOnly =
                                    rifleOnlyMap?.containsKey(dk) ?? false;

                                final deleteRifleOnly = fromAmmoScoped
                                    ? false
                                    : (fromRifleOnly
                                          ? true
                                          : e.ammoLotId == null);
                                final deleteBucketKey = deleteRifleOnly
                                    ? rifleKey
                                    : (ammoKey ?? '${rifleKey}_${e.ammoLotId}');
                                state.deleteWorkingDopeEntry(
                                  rifleOnly: deleteRifleOnly,
                                  bucketKey: deleteBucketKey,
                                  distanceKey: dk,
                                );
                              },
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
              if (!canViewPhotos)
                _HintCard(
                  icon: Icons.lock_outline,
                  title: 'Photos are private',
                  message:
                      'The session owner has chosen not to share photos for this session.',
                )
              else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        try {
                          final x = await picker.pickImage(
                            source: ImageSource.camera,
                            imageQuality: 85,
                          );
                          if (x == null) return;
                          final bytes = await x.readAsBytes();

                          String caption = '';
                          final cap = await showDialog<String>(
                            context: context,
                            builder: (_) => _PhotoNoteDialog(),
                          );
                          if (cap != null) caption = cap;

                          state.addSessionPhoto(
                            sessionId: s.id,
                            bytes: bytes,
                            caption: caption,
                          );
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
                          child: Image.memory(
                            p.bytes,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          p.caption.trim().isEmpty ? 'Photo' : p.caption.trim(),
                        ),
                        subtitle: Text(
                          '${_fmtDateTime(p.time)} • ${p.bytes.lengthInBytes} bytes',
                        ),
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
                                    child: Text(
                                      p.caption.trim().isEmpty
                                          ? 'Photo'
                                          : p.caption.trim(),
                                    ),
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
              ],
              const SizedBox(height: 16),
              _SectionTitle('Shot Timer'),
              const SizedBox(height: 8),
              if (!canViewTimerData)
                _HintCard(
                  icon: Icons.lock_outline,
                  title: 'Timer data is private',
                  message:
                      'The session owner has chosen not to share timer data for this session.',
                )
              else
                _SessionShotTimerCard(state: state, sessionId: s.id),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Loadout: ${rifle?.name ?? '-'} / ${ammo?.name ?? '-'}',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ColdBoreScreen extends StatefulWidget {
  final AppState state;
  const ColdBoreScreen({super.key, required this.state});

  @override
  State<ColdBoreScreen> createState() => _ColdBoreScreenState();
}

class _ColdBoreScreenState extends State<ColdBoreScreen> {
  String? _selectedRifleId;
  String? _selectedAmmoId;
  int _selectedDateWindowDays = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final state = widget.state;
        final user = state.activeUser;
        if (user == null) {
          return const _EmptyState(
            icon: Icons.person_outline,
            title: 'No active user',
            message: 'Create or select a user to view cold bore history.',
          );
        }

        final rows = state.coldBoreRowsForActiveUser();
        final rifleOptions = <String, Rifle>{};
        final ammoOptions = <String, AmmoLot>{};
        for (final row in rows) {
          final rifle = row.rifle;
          if (rifle != null) {
            rifleOptions[rifle.id] = rifle;
          }
          final ammo = row.ammo;
          if (ammo != null) {
            ammoOptions[ammo.id] = ammo;
          }
        }

        if (_selectedRifleId != null &&
            !rifleOptions.containsKey(_selectedRifleId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedRifleId = null;
                _selectedAmmoId = null;
              });
            }
          });
        }
        if (_selectedAmmoId != null &&
            !ammoOptions.containsKey(_selectedAmmoId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedAmmoId = null);
            }
          });
        }

        final filteredRows = rows.where((row) {
          if (_selectedRifleId != null && row.rifle?.id != _selectedRifleId) {
            return false;
          }
          if (_selectedAmmoId != null && row.ammo?.id != _selectedAmmoId) {
            return false;
          }
          if (_selectedDateWindowDays > 0) {
            final cutoff = DateTime.now().subtract(
              Duration(days: _selectedDateWindowDays),
            );
            if (row.shot.time.isBefore(cutoff)) return false;
          }
          return true;
        }).toList();

        if (rows.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: const [
              _ColdBoreTargetCard(state: null, rows: []),
              SizedBox(height: 12),
              _EmptyState(
                icon: Icons.ac_unit_outlined,
                title: 'No cold bore entries yet',
                message:
                    'Open a session, tap "Add Cold Bore", then save the entry.',
              ),
            ],
          );
        }

        final rifleList = rifleOptions.values.toList()
          ..sort((a, b) {
            final an = [
              if (a.caliber.trim().isNotEmpty) a.caliber.trim(),
              if ((a.manufacturer ?? '').trim().isNotEmpty)
                (a.manufacturer ?? '').trim(),
              if ((a.model ?? '').trim().isNotEmpty) (a.model ?? '').trim(),
              if ((a.name ?? '').trim().isNotEmpty) (a.name ?? '').trim(),
            ].join(' ');
            final bn = [
              if (b.caliber.trim().isNotEmpty) b.caliber.trim(),
              if ((b.manufacturer ?? '').trim().isNotEmpty)
                (b.manufacturer ?? '').trim(),
              if ((b.model ?? '').trim().isNotEmpty) (b.model ?? '').trim(),
              if ((b.name ?? '').trim().isNotEmpty) (b.name ?? '').trim(),
            ].join(' ');
            return an.compareTo(bn);
          });

        final filteredAmmoOptions =
            ammoOptions.values
                .where(
                  (ammo) =>
                      _selectedRifleId == null ||
                      rows.any(
                        (row) =>
                            row.rifle?.id == _selectedRifleId &&
                            row.ammo?.id == ammo.id,
                      ),
                )
                .toList()
              ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

        return ListView.builder(
          itemCount: filteredRows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              // Build a simple drift summary from existing rows + baseline per rifle+ammo
              final Map<String, List<_ColdBoreRow>> groups = {};
              for (final r in filteredRows) {
                final rid = r.rifle?.id;
                final aid = r.ammo?.id;
                if (rid == null || aid == null) continue;
                final key = '$rid|$aid';
                (groups[key] ??= []).add(r);
              }

              String dir(double v, String pos, String neg) => v == 0
                  ? '0'
                  : (v > 0
                        ? '$pos ${v.abs().toStringAsFixed(2)}'
                        : '$neg ${v.abs().toStringAsFixed(2)}');

              final items = <Map<String, dynamic>>[];
              groups.forEach((key, list) {
                final first = list.first;
                final rifleId = first.rifle?.id;
                final ammoLotId = first.ammo?.id;
                if (rifleId == null || ammoLotId == null) return;
                final baseline = state.baselineColdBoreShot(
                  rifleId: rifleId,
                  ammoLotId: ammoLotId,
                );
                if (baseline == null) return;
                if (baseline.offsetX == null || baseline.offsetY == null) {
                  return;
                }

                final bdx = _shotOffsetToMoa(baseline, baseline.offsetX!);
                final bdy = _shotOffsetToMoa(baseline, baseline.offsetY!);

                double? latestDx, latestDy;
                final radials = <double>[];
                final sorted = [...list]
                  ..sort((a, b) => b.shot.time.compareTo(a.shot.time));

                for (final r in sorted) {
                  final sh = r.shot;
                  if (sh.isBaseline) continue;
                  if (sh.offsetX == null || sh.offsetY == null) continue;

                  final dx = _shotOffsetToMoa(sh, sh.offsetX!) - bdx;
                  final dy = _shotOffsetToMoa(sh, sh.offsetY!) - bdy;
                  radials.add(math.sqrt(dx * dx + dy * dy));

                  latestDx ??= dx;
                  latestDy ??= dy;

                  if (radials.length >= 10) break;
                }

                if (radials.isEmpty) return;
                final avg = radials.reduce((a, b) => a + b) / radials.length;

                items.add({
                  'rifle': first.rifle?.name ?? 'Rifle',
                  'ammo': first.ammo?.name ?? 'Ammo',
                  'avg': avg,
                  'dx': latestDx ?? 0.0,
                  'dy': latestDy ?? 0.0,
                });
              });

              items.sort(
                (a, b) => (b['avg'] as double).compareTo(a['avg'] as double),
              );
              final top = items.take(3).toList();

              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Filter Cold Bore History',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              initialValue: _selectedRifleId,
                              decoration: const InputDecoration(
                                labelText: 'Rifle filter',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All rifles'),
                                ),
                                ...rifleList.map(
                                  (rifle) => DropdownMenuItem<String?>(
                                    value: rifle.id,
                                    child: Text(
                                      [
                                        if (rifle.caliber.trim().isNotEmpty)
                                          rifle.caliber.trim(),
                                        if ((rifle.manufacturer ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          (rifle.manufacturer ?? '').trim(),
                                        if ((rifle.model ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          (rifle.model ?? '').trim(),
                                        if ((rifle.name ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          (rifle.name ?? '').trim(),
                                      ].join(' • '),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedRifleId = value;
                                  if (_selectedAmmoId != null &&
                                      !rows.any(
                                        (row) =>
                                            row.rifle?.id == value &&
                                            row.ammo?.id == _selectedAmmoId,
                                      )) {
                                    _selectedAmmoId = null;
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String?>(
                              initialValue: _selectedAmmoId,
                              decoration: const InputDecoration(
                                labelText: 'Ammo filter',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All ammo'),
                                ),
                                ...filteredAmmoOptions.map(
                                  (ammo) => DropdownMenuItem<String?>(
                                    value: ammo.id,
                                    child: Text(
                                      [
                                        if (ammo.caliber.trim().isNotEmpty)
                                          ammo.caliber.trim(),
                                        if ((ammo.manufacturer ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          (ammo.manufacturer ?? '').trim(),
                                        if (ammo.bullet.trim().isNotEmpty)
                                          ammo.bullet.trim(),
                                        if (ammo.grain > 0) '${ammo.grain}gr',
                                        if ((ammo.name ?? '').trim().isNotEmpty)
                                          (ammo.name ?? '').trim(),
                                      ].join(' • '),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedAmmoId = value),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _selectedDateWindowDays,
                              decoration: const InputDecoration(
                                labelText: 'Date filter',
                              ),
                              items: const [
                                DropdownMenuItem<int>(
                                  value: 0,
                                  child: Text('All time'),
                                ),
                                DropdownMenuItem<int>(
                                  value: 30,
                                  child: Text('Last 30 days'),
                                ),
                                DropdownMenuItem<int>(
                                  value: 90,
                                  child: Text('Last 90 days'),
                                ),
                                DropdownMenuItem<int>(
                                  value: 365,
                                  child: Text('Last year'),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => _selectedDateWindowDays = value ?? 0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              filteredRows.isEmpty
                                  ? 'No cold bore entries match the current filter.'
                                  : 'Showing ${filteredRows.length} cold bore entr${filteredRows.length == 1 ? 'y' : 'ies'} on the target below.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ColdBoreTargetCard(state: state, rows: filteredRows),
                    const SizedBox(height: 12),
                    _ColdBoreTargetGalleryCard(
                      state: state,
                      rows: filteredRows,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Baseline drift summary',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            if (top.isEmpty) ...[
                              Text(
                                'No baseline drift data yet.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tip: Mark a cold bore entry as Baseline for a specific Rifle + Ammo, and enter an Impact Offset (or use Impact OK).',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ] else ...[
                              for (final s in top) ...[
                                Text('${s['rifle']} • ${s['ammo']}'),
                                Text(
                                  'Avg drift: ${(s['avg'] as double).toStringAsFixed(2)} MOA • Latest: ${dir(s['dx'] as double, 'Right', 'Left')} • ${dir(s['dy'] as double, 'Up', 'Down')}',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            final r = filteredRows[i - 1];
            final rifle = r.rifle;
            final ammo = r.ammo;
            final stringIndex = r.stringId == null
                ? -1
                : r.session.strings.indexWhere((x) => x.id == r.stringId);
            return Column(
              children: [
                ListTile(
                  leading: Icon(
                    r.shot.isBaseline ? Icons.star : Icons.ac_unit_outlined,
                  ),
                  title: Text(
                    '${r.shot.distance} • ${r.shot.result}${r.shot.photos.isEmpty ? '' : ' • ${r.shot.photos.length} photo(s)'}',
                  ),
                  subtitle: Text(
                    [
                      _fmtDateTime(r.shot.time),
                      r.session.locationName,
                      if (rifle != null) rifle.name ?? '',
                      if (ammo != null) ammo.name ?? '',
                      if (stringIndex >= 0) 'String ${stringIndex + 1}',
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
                ),
                const Divider(height: 1),
              ],
            );
          },
        );
      },
    );
  }
}

class _ColdBoreTargetCard extends StatelessWidget {
  final AppState? state;
  final List<_ColdBoreRow> rows;

  const _ColdBoreTargetCard({required this.state, required this.rows});

  @override
  Widget build(BuildContext context) {
    final plottedRows =
        rows
            .where(
              (row) => row.shot.offsetX != null && row.shot.offsetY != null,
            )
            .toList()
          ..sort((a, b) => a.shot.time.compareTo(b.shot.time));
    final hiddenCount = rows.length - plottedRows.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cold bore target',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              hiddenCount > 0
                  ? '${plottedRows.length} plotted • $hiddenCount entries need impact offsets before they can be shown.'
                  : '${plottedRows.length} plotted',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            if (plottedRows.isEmpty)
              const _HintCard(
                icon: Icons.gps_not_fixed_outlined,
                title: 'No plotted cold bore impacts yet',
                message:
                    'Add an Impact Offset on cold bore entries to place them on the zero target.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(constraints.maxWidth, 420.0);
                  const spanInches = 6.0;
                  const pointSize = 16.0;

                  Offset pointOffset(_ColdBoreRow row) {
                    final dx = _shotOffsetToInches(
                      row.shot,
                      row.shot.offsetX!,
                    ).clamp(-spanInches, spanInches);
                    final dy = _shotOffsetToInches(
                      row.shot,
                      row.shot.offsetY!,
                    ).clamp(-spanInches, spanInches);
                    final nx = (dx + spanInches) / (spanInches * 2);
                    final ny = (spanInches - dy) / (spanInches * 2);
                    return Offset(nx * size, ny * size);
                  }

                  return Center(
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ColdBoreTargetPainter(
                                colorScheme: Theme.of(context).colorScheme,
                              ),
                            ),
                          ),
                          ...plottedRows.map((row) {
                            final offset = pointOffset(row);
                            final isBaseline = row.shot.isBaseline;
                            return Positioned(
                              left: offset.dx - pointSize / 2,
                              top: offset.dy - pointSize / 2,
                              width: pointSize,
                              height: pointSize,
                              child: Tooltip(
                                message:
                                    '${_fmtDateTime(row.shot.time)}\n${row.shot.distance} • ${row.shot.result}',
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: state == null
                                        ? null
                                        : () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ColdBoreEntryScreen(
                                                      state: state!,
                                                      sessionId: row.session.id,
                                                      shotId: row.shot.id,
                                                    ),
                                              ),
                                            );
                                          },
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        color: isBaseline
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.tertiary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: isBaseline
                                          ? const Icon(
                                              Icons.star,
                                              size: 11,
                                              color: Colors.white,
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Text(
              'Grid spacing is 1 inch. Tap any plotted point to open that cold bore entry.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColdBoreTargetGalleryCard extends StatelessWidget {
  final AppState? state;
  final List<_ColdBoreRow> rows;

  const _ColdBoreTargetGalleryCard({required this.state, required this.rows});

  @override
  Widget build(BuildContext context) {
    final photoRows = rows.where((row) => row.shot.photos.isNotEmpty).toList()
      ..sort((a, b) => b.shot.time.compareTo(a.shot.time));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cold bore target gallery',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              photoRows.isEmpty
                  ? 'No cold bore target photos found for the current filter.'
                  : 'Showing ${photoRows.length} cold bore target photo${photoRows.length == 1 ? '' : 's'}.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 10),
            if (photoRows.isEmpty)
              const _HintCard(
                icon: Icons.photo_outlined,
                title: 'No target photos yet',
                message:
                    'Attach a photo when adding or editing a cold bore entry to see it here.',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final row in photoRows.take(60))
                    Builder(
                      builder: (context) {
                        final photo = row.shot.photos.last;
                        return InkWell(
                          onTap: state == null
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ColdBoreEntryScreen(
                                        state: state!,
                                        sessionId: row.session.id,
                                        shotId: row.shot.id,
                                      ),
                                    ),
                                  );
                                },
                          child: SizedBox(
                            width: 118,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    photo.bytes,
                                    width: 118,
                                    height: 92,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _fmtDateTime(row.shot.time),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                Text(
                                  row.shot.distance,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ColdBoreLegendDot extends StatelessWidget {
  final String label;
  final bool isBaseline;

  const _ColdBoreLegendDot({required this.label, this.isBaseline = false});

  @override
  Widget build(BuildContext context) {
    final color = isBaseline
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: isBaseline
              ? const Icon(Icons.star, size: 9, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _ColdBoreTargetPainter extends CustomPainter {
  final ColorScheme colorScheme;

  const _ColdBoreTargetPainter({required this.colorScheme});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final fillPaint = Paint()
      ..color = colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = colorScheme.onSurface.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final gridPaint = Paint()
      ..color = colorScheme.outline.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = colorScheme.onSurface.withValues(alpha: 0.82)
      ..strokeWidth = 1.7;

    canvas.drawRect(Offset.zero & size, fillPaint);
    canvas.drawRect(Offset.zero & size, borderPaint);

    const halfSpanInches = 6.0;
    const fullSpanInches = halfSpanInches * 2;
    final step = size.width / fullSpanInches;
    for (var i = 1; i < fullSpanInches; i++) {
      final offset = step * i;
      if ((offset - center.dx).abs() < 0.01 ||
          (offset - center.dy).abs() < 0.01) {
        continue;
      }
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset, size.height),
        gridPaint,
      );
      canvas.drawLine(Offset(0, offset), Offset(size.width, offset), gridPaint);
    }

    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      axisPaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      axisPaint,
    );

    final centerPaint = Paint()..color = colorScheme.error;
    canvas.drawCircle(center, 4, centerPaint);
    canvas.drawLine(
      Offset(center.dx - 10, center.dy),
      Offset(center.dx + 10, center.dy),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 10),
      Offset(center.dx, center.dy + 10),
      axisPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ColdBoreTargetPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Photo failed: $e')));
    }
  }

  void _setBaseline() {
    widget.state.setBaselineColdBore(
      sessionId: widget.sessionId,
      shotId: widget.shotId,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked as baseline (first shot).')),
    );
  }

  void _compare() {
    final s = widget.state.getSessionById(widget.sessionId);
    if (s == null) return;

    final current = widget.state.shotById(
      sessionId: widget.sessionId,
      shotId: widget.shotId,
    );
    if (current == null) return;

    final baseline = widget.state.baselineColdBoreShot(
      rifleId: s.rifleId,
      ammoLotId: s.ammoLotId,
    );
    if (baseline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No baseline set for this rifle + ammo yet. Tap "Mark as Baseline" first.',
          ),
        ),
      );
      return;
    }

    if (baseline.id == current.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This entry is already the baseline.')),
      );
      return;
    }

    if (baseline.offsetX == null ||
        baseline.offsetY == null ||
        current.offsetX == null ||
        current.offsetY == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Both entries need impact offsets before you can compare them.',
          ),
        ),
      );
      return;
    }

    final dx =
        _shotOffsetToMoa(current, current.offsetX!) -
        _shotOffsetToMoa(baseline, baseline.offsetX!);
    final dy =
        _shotOffsetToMoa(current, current.offsetY!) -
        _shotOffsetToMoa(baseline, baseline.offsetY!);

    String unitLabel(String u) {
      switch (u) {
        case 'moa':
          return 'MOA';
        case 'mil':
          return 'mil';
        default:
          return 'in';
      }
    }

    String driftLabel(double value, String positive, String negative) {
      if (value == 0) return '0';
      return value > 0
          ? '$positive ${value.abs().toStringAsFixed(2)}'
          : '$negative ${value.abs().toStringAsFixed(2)}';
    }

    showDialog<void>(
      context: context,
      builder: (_) {
        final baseImg = baseline.photos.isNotEmpty
            ? baseline.photos.last.bytes
            : null;
        final curImg = current.photos.isNotEmpty
            ? current.photos.last.bytes
            : null;
        return AlertDialog(
          title: const Text('Compare to Baseline'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Baseline: ${baseline.distance} • ${baseline.result}'),
                  if (baseline.offsetX != null || baseline.offsetY != null)
                    Text(
                      'Offset: X ${baseline.offsetX ?? 0}  Y ${baseline.offsetY ?? 0} (${unitLabel(baseline.offsetUnit)})',
                    ),
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
                  if (current.offsetX != null || current.offsetY != null)
                    Text(
                      'Offset: X ${current.offsetX ?? 0}  Y ${current.offsetY ?? 0} (${unitLabel(current.offsetUnit)})',
                    ),
                  const SizedBox(height: 8),
                  if (curImg != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(curImg, fit: BoxFit.cover),
                    )
                  else
                    const Text('No photo on this entry yet.'),
                  const SizedBox(height: 16),
                  Text(
                    '${driftLabel(dx, 'Right', 'Left')}  •  ${driftLabel(dy, 'Up', 'Down')} (MOA)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
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
        final shot = widget.state.shotById(
          sessionId: widget.sessionId,
          shotId: widget.shotId,
        );
        if (s == null || shot == null) {
          return const Scaffold(body: Center(child: Text('Entry not found')));
        }

        String? stringId;
        for (final entry in s.shotsByString.entries) {
          if (entry.value.any((x) => x.id == shot.id)) {
            stringId = entry.key;
            break;
          }
        }
        final stringIndex = stringId == null
            ? -1
            : s.strings.indexWhere((x) => x.id == stringId);
        final stringMeta = stringIndex >= 0 ? s.strings[stringIndex] : null;
        final rifle = widget.state.rifleById(stringMeta?.rifleId ?? s.rifleId);
        final ammo = widget.state.ammoById(
          stringMeta?.ammoLotId ?? s.ammoLotId,
        );

        String weatherLine() {
          final parts = <String>[];
          if (s.temperatureF != null) {
            parts.add('${s.temperatureF!.toStringAsFixed(0)} F');
          }
          if (s.windSpeedMph != null) {
            parts.add('${s.windSpeedMph!.toStringAsFixed(0)} mph wind');
          }
          if (s.windDirectionDeg != null) {
            parts.add('${s.windDirectionDeg} deg');
          }
          return parts.isEmpty ? 'No weather saved' : parts.join(' • ');
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
                  Expanded(
                    child: Text(
                      '${shot.distance} • ${shot.result}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (shot.isBaseline)
                    const Chip(
                      label: Text('Baseline'),
                      avatar: Icon(Icons.star, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('${_fmtDateTime(shot.time)} • ${s.locationName}'),
              if (shot.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(shot.notes),
              ],
              const SizedBox(height: 16),
              _SectionTitle('Session Data'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Session started: ${_fmtDateTime(s.dateTime)}'),
                      const SizedBox(height: 6),
                      Text('Cold bore time: ${_fmtDateTime(shot.time)}'),
                      const SizedBox(height: 6),
                      Text(
                        'Location: ${s.locationName.isEmpty ? '-' : s.locationName}',
                      ),
                      const SizedBox(height: 6),
                      Text('Weather: ${weatherLine()}'),
                      const SizedBox(height: 6),
                      Text(
                        'Rifle: ${rifle == null ? '-' : ((rifle.name ?? '').trim().isNotEmpty ? (rifle.name ?? '').trim() : [if (rifle.caliber.trim().isNotEmpty) rifle.caliber.trim(), if ((rifle.manufacturer ?? '').trim().isNotEmpty) (rifle.manufacturer ?? '').trim(), if ((rifle.model ?? '').trim().isNotEmpty) (rifle.model ?? '').trim()].join(' '))}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ammo: ${ammo == null ? '-' : (((ammo.name ?? '').trim().isNotEmpty) ? (ammo.name ?? '').trim() : [if (ammo.caliber.trim().isNotEmpty) ammo.caliber.trim(), if ((ammo.manufacturer ?? '').trim().isNotEmpty) (ammo.manufacturer ?? '').trim(), if (ammo.bullet.trim().isNotEmpty) ammo.bullet.trim(), if (ammo.grain > 0) '${ammo.grain}gr'].join(' '))}',
                      ),
                      if (stringIndex >= 0) ...[
                        const SizedBox(height: 6),
                        Text('String: ${stringIndex + 1}'),
                      ],
                      if (s.latitude != null && s.longitude != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'GPS: ${s.latitude!.toStringAsFixed(6)}, ${s.longitude!.toStringAsFixed(6)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (shot.offsetX != null || shot.offsetY != null) ...[
                _SectionTitle('Impact Offset'),
                const SizedBox(height: 8),
                Builder(
                  builder: (_) {
                    final x = shot.offsetX ?? 0.0;
                    final y = shot.offsetY ?? 0.0;
                    final horiz = x == 0
                        ? '0'
                        : x > 0
                        ? 'Right ${x.abs().toStringAsFixed(2)}'
                        : 'Left ${x.abs().toStringAsFixed(2)}';
                    final vert = y == 0
                        ? '0'
                        : y > 0
                        ? 'Up ${y.abs().toStringAsFixed(2)}'
                        : 'Down ${y.abs().toStringAsFixed(2)}';
                    return Text('$horiz  •  $vert (${shot.offsetUnit})');
                  },
                ),
                const SizedBox(height: 16),
              ],
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
                  message:
                      'Add a photo here. These photos stay attached to this cold bore entry only.',
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
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EndSessionResult {
  final int totalShotCount;
  final Map<String, int> appliedShotCounts;

  const _EndSessionResult({
    required this.totalShotCount,
    required this.appliedShotCounts,
  });
}

class _EndSessionRifleCount {
  final String rifleId;
  final String label;
  final int initialShotCount;

  const _EndSessionRifleCount({
    required this.rifleId,
    required this.label,
    required this.initialShotCount,
  });
}

class _EndSessionDialog extends StatefulWidget {
  final List<_EndSessionRifleCount> rifleCounts;

  const _EndSessionDialog({required this.rifleCounts});

  @override
  State<_EndSessionDialog> createState() => _EndSessionDialogState();
}

class _EndSessionDialogState extends State<_EndSessionDialog> {
  late final List<TextEditingController> _shotCountCtrls;
  late final List<bool> _applyToRifle;

  @override
  void initState() {
    super.initState();
    _shotCountCtrls = [
      for (final rifle in widget.rifleCounts)
        TextEditingController(text: rifle.initialShotCount.toString()),
    ];
    _applyToRifle = [for (final _ in widget.rifleCounts) true];
  }

  @override
  void dispose() {
    for (final ctrl in _shotCountCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('End session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save the confirmed shot count and close the current session.',
            ),
            const SizedBox(height: 12),
            if (widget.rifleCounts.isEmpty)
              const Text(
                'No rifles with logged shots were detected in this session yet.',
              )
            else
              ...List.generate(widget.rifleCounts.length, (index) {
                final rifle = widget.rifleCounts[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == widget.rifleCounts.length - 1 ? 0 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rifle.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        textCapitalization: TextCapitalization.none,
                        controller: _shotCountCtrls[index],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Shots for this rifle',
                          helperText:
                              'Edit if the detected count needs correction.',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _applyToRifle[index],
                        onChanged: (value) =>
                            setState(() => _applyToRifle[index] = value),
                        title: const Text('Apply to rifle rounds'),
                        subtitle: const Text(
                          'This updates the rifle round count when the session ends.',
                        ),
                      ),
                    ],
                  ),
                );
              }),
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
            final appliedShotCounts = <String, int>{};
            var totalShotCount = 0;
            for (var i = 0; i < widget.rifleCounts.length; i++) {
              final shotCount = int.tryParse(_shotCountCtrls[i].text.trim());
              if (shotCount == null) return;
              totalShotCount += shotCount;
              if (_applyToRifle[i] && shotCount > 0) {
                appliedShotCounts[widget.rifleCounts[i].rifleId] = shotCount;
              }
            }
            Navigator.pop(
              context,
              _EndSessionResult(
                totalShotCount: totalShotCount,
                appliedShotCounts: appliedShotCounts,
              ),
            );
          },
          child: const Text('End session'),
        ),
      ],
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
    if (!await _guardWrite(context)) return;
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
      barrelRoundCount: res.barrelRoundCount,
      barrelInstalledDate: res.barrelInstalledDate,
      barrelNotes: res.barrelNotes,
      scopeMake: res.scopeMake,
      scopeModel: res.scopeModel,
      scopeSerial: res.scopeSerial,
      scopeMount: res.scopeMount,
      scopeNotes: res.scopeNotes,
      purchaseLocation: res.purchaseLocation,
    );
  }

  Future<void> _addAmmo() async {
    if (!await _guardWrite(context)) return;
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
      manualRoundCount: res.manualRoundCount,
      barrelRoundCount: res.barrelRoundCount,
      barrelInstalledDate: res.barrelInstalledDate,
      barrelNotes: res.barrelNotes,
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
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
                    ButtonSegment(
                      value: 0,
                      label: Text('Rifles'),
                      icon: Icon(Icons.sports_martial_arts_outlined),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Ammo'),
                      icon: Icon(Icons.inventory_2_outlined),
                    ),
                  ],
                  selected: {_seg},
                  onSelectionChanged: (s) => setState(() => _seg = s.first),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _seg == 0
                      ? _EquipmentList(
                          emptyTitle: 'No rifles yet',
                          emptyMessage:
                              'Tap "Add Rifle" to create your first rifle.',
                          items: rifles
                              .map(
                                (r) => ListTile(
                                  leading: const Icon(
                                    Icons.sports_martial_arts_outlined,
                                  ),
                                  title: Text(
                                    (('${(r.manufacturer ?? '').trim()} ${(r.model ?? '').trim()}')
                                            .trim()
                                            .isNotEmpty)
                                        ? ('${(r.manufacturer ?? '').trim()} ${(r.model ?? '').trim()}')
                                              .trim()
                                        : (((r.name ?? '').trim().isNotEmpty)
                                              ? (r.name ?? '').trim()
                                              : 'Rifle'),
                                  ),
                                  subtitle: Text(
                                    r.caliber +
                                        (((r.name ?? '').trim().isEmpty)
                                            ? ''
                                            : ' • Nickname: ${(r.name ?? '').trim()}') +
                                        (((r.manufacturer ?? '').trim().isEmpty)
                                            ? ''
                                            : ' • ${(r.manufacturer ?? '').trim()}') +
                                        (((r.model ?? '').trim().isEmpty)
                                            ? ''
                                            : ' • ${(r.model ?? '').trim()}') +
                                        ((r.serialNumber == null ||
                                                r.serialNumber!.isEmpty)
                                            ? ''
                                            : ' • SN ${r.serialNumber!}') +
                                        (r.purchaseDate == null
                                            ? ''
                                            : ' • ${_fmtDate(r.purchaseDate!)}') +
                                        (r.notes.isEmpty
                                            ? ''
                                            : ' • ${r.notes}') +
                                        (r.dope.trim().isEmpty
                                            ? ''
                                            : ' • DOPE saved'),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'edit') {
                                        await _editRifle(r);
                                        return;
                                      }
                                      if (v == 'dope') {
                                        final updated =
                                            await showDialog<String>(
                                              context: context,
                                              builder: (_) => _EditDopeDialog(
                                                initialValue: r.dope,
                                              ),
                                            );
                                        if (updated == null) return;
                                        widget.state.updateRifleDope(
                                          rifleId: r.id,
                                          dope: updated,
                                        );
                                        return;
                                      }
                                      if (v == 'service') {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                RifleServiceLogScreen(
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
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit rifle'),
                                      ),
                                      PopupMenuItem(
                                        value: 'dope',
                                        child: Text('Edit DOPE'),
                                      ),
                                      PopupMenuItem(
                                        value: 'service',
                                        child: Text('Service log'),
                                      ),
                                      PopupMenuDivider(),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      : _EquipmentList(
                          emptyTitle: 'No ammo lots yet',
                          emptyMessage:
                              'Tap "Add Ammo" to create your first ammo lot.',
                          items: ammo
                              .map(
                                (a) => ListTile(
                                  leading: const Icon(
                                    Icons.inventory_2_outlined,
                                  ),
                                  title: Text(
                                    '${a.caliber} - ${a.grain}gr - ${a.bullet}${((a.name ?? '').trim().isEmpty) ? '' : ' (${(a.name ?? '').trim()})'}'
                                        .trim(),
                                  ),
                                  subtitle: Text(
                                    ((a.manufacturer == null ||
                                                a.manufacturer!.isEmpty)
                                            ? ''
                                            : '${a.manufacturer!} • ') +
                                        ((a.lotNumber == null ||
                                                a.lotNumber!.isEmpty)
                                            ? ''
                                            : 'Lot ${a.lotNumber!} • ') +
                                        (a.purchaseDate == null
                                            ? ''
                                            : '${_fmtDate(a.purchaseDate!)} • ') +
                                        (a.ballisticCoefficient == null
                                            ? ''
                                            : 'BC ${a.ballisticCoefficient} • ') +
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
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit ammo'),
                                      ),
                                      PopupMenuDivider(),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
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
  State<ExportPlaceholderScreen> createState() =>
      _ExportPlaceholderScreenState();
}

enum _PdfSessionFilterMode { all, selected, dateRange }

class _PdfExportOptions {
  final bool includeSummary;
  final bool includeCharts;
  final bool includeRecentSessions;
  final bool includeUsedRifles;
  final bool includeUsedAmmo;
  final bool includeMaintenance;
  final bool includeEverything;
  final bool includeSessionDetails;
  final _PdfSessionFilterMode sessionFilterMode;
  final List<String> selectedSessionIds;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? folderFilter;
  final int? yearFilter;
  final String? monthFilter;

  const _PdfExportOptions({
    required this.includeSummary,
    required this.includeCharts,
    required this.includeRecentSessions,
    required this.includeUsedRifles,
    required this.includeUsedAmmo,
    required this.includeMaintenance,
    required this.includeEverything,
    required this.includeSessionDetails,
    required this.sessionFilterMode,
    this.selectedSessionIds = const [],
    this.startDate,
    this.endDate,
    this.folderFilter,
    this.yearFilter,
    this.monthFilter,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
    'includeSummary': includeSummary,
    'includeCharts': includeCharts,
    'includeRecentSessions': includeRecentSessions,
    'includeUsedRifles': includeUsedRifles,
    'includeUsedAmmo': includeUsedAmmo,
    'includeMaintenance': includeMaintenance,
    'includeEverything': includeEverything,
    'includeSessionDetails': includeSessionDetails,
    'sessionFilterMode': sessionFilterMode.name,
    'selectedSessionIds': selectedSessionIds,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'folderFilter': folderFilter,
    'yearFilter': yearFilter,
    'monthFilter': monthFilter,
  };

  factory _PdfExportOptions.fromMap(Map<String, dynamic> map) {
    return _PdfExportOptions(
      includeSummary: map['includeSummary'] != false,
      includeCharts: map['includeCharts'] != false,
      includeRecentSessions: map['includeRecentSessions'] != false,
      includeUsedRifles: map['includeUsedRifles'] != false,
      includeUsedAmmo: map['includeUsedAmmo'] != false,
      includeMaintenance: map['includeMaintenance'] != false,
      includeEverything: map['includeEverything'] == true,
      includeSessionDetails: map['includeSessionDetails'] != false,
      sessionFilterMode: _PdfSessionFilterMode.values.firstWhere(
        (mode) => mode.name == (map['sessionFilterMode'] ?? 'all').toString(),
        orElse: () => _PdfSessionFilterMode.all,
      ),
      selectedSessionIds: ((map['selectedSessionIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      startDate: map['startDate'] == null
          ? null
          : DateTime.tryParse(map['startDate'].toString()),
      endDate: map['endDate'] == null
          ? null
          : DateTime.tryParse(map['endDate'].toString()),
      folderFilter: map['folderFilter']?.toString(),
      yearFilter: _toNullableInt(map['yearFilter']),
      monthFilter: map['monthFilter']?.toString(),
    );
  }
}

class _PdfExportPreset {
  final String name;
  final _PdfExportOptions options;

  const _PdfExportPreset({required this.name, required this.options});

  Map<String, dynamic> toMap() => <String, dynamic>{
    'name': name,
    'options': options.toMap(),
  };

  factory _PdfExportPreset.fromMap(Map<String, dynamic> map) {
    return _PdfExportPreset(
      name: (map['name'] ?? 'Preset').toString(),
      options: _PdfExportOptions.fromMap(
        Map<String, dynamic>.from(
          (map['options'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}

class _ExportPlaceholderScreenState extends State<ExportPlaceholderScreen> {
  List<_PdfExportPreset> _savedPdfPresets = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPdfPresets());
  }

  List<_PdfExportPreset> get _builtinPdfPresets => const [
    _PdfExportPreset(
      name: 'Professional',
      options: _PdfExportOptions(
        includeSummary: true,
        includeCharts: false,
        includeRecentSessions: true,
        includeUsedRifles: true,
        includeUsedAmmo: true,
        includeMaintenance: true,
        includeEverything: false,
        includeSessionDetails: false,
        sessionFilterMode: _PdfSessionFilterMode.all,
      ),
    ),
    _PdfExportPreset(
      name: 'Personal Log',
      options: _PdfExportOptions(
        includeSummary: true,
        includeCharts: true,
        includeRecentSessions: true,
        includeUsedRifles: true,
        includeUsedAmmo: true,
        includeMaintenance: false,
        includeEverything: false,
        includeSessionDetails: false,
        sessionFilterMode: _PdfSessionFilterMode.all,
      ),
    ),
    _PdfExportPreset(
      name: 'Maintenance',
      options: _PdfExportOptions(
        includeSummary: true,
        includeCharts: false,
        includeRecentSessions: false,
        includeUsedRifles: true,
        includeUsedAmmo: false,
        includeMaintenance: true,
        includeEverything: false,
        includeSessionDetails: false,
        sessionFilterMode: _PdfSessionFilterMode.all,
      ),
    ),
    _PdfExportPreset(
      name: 'Complete',
      options: _PdfExportOptions(
        includeSummary: true,
        includeCharts: true,
        includeRecentSessions: true,
        includeUsedRifles: true,
        includeUsedAmmo: true,
        includeMaintenance: true,
        includeEverything: true,
        includeSessionDetails: true,
        sessionFilterMode: _PdfSessionFilterMode.all,
      ),
    ),
  ];

  Future<void> _loadPdfPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kPdfExportPresetsPrefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final presets = decoded
          .map(
            (e) =>
                _PdfExportPreset.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      if (!mounted) return;
      setState(() => _savedPdfPresets = presets);
    } catch (e, st) {
      debugPrint('Failed to load PDF export presets: $e\n$st');
    }
  }

  Future<void> _savePdfPresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kPdfExportPresetsPrefsKey,
      jsonEncode(_savedPdfPresets.map((p) => p.toMap()).toList()),
    );
  }

  Future<void> _saveCurrentOptionsAsPreset(
    BuildContext context,
    _PdfExportOptions options,
  ) async {
    final controller = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Save PDF preset'),
          content: TextField(
            textCapitalization: TextCapitalization.none,
            controller: controller,
            decoration: const InputDecoration(labelText: 'Preset name'),
            textInputAction: TextInputAction.done,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name == null || name.trim().isEmpty) return;

      final preset = _PdfExportPreset(name: name.trim(), options: options);
      final next = [
        ..._savedPdfPresets.where(
          (p) => p.name.toLowerCase() != preset.name.toLowerCase(),
        ),
        preset,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() => _savedPdfPresets = next);
      await _savePdfPresets();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved PDF preset: ${preset.name}')),
      );
    } finally {
      controller.dispose();
    }
  }

  String _pdfAmmoLabel(String? ammoId) {
    if (ammoId == null) return '-';
    final ammo = widget.state.findAmmoLotById(ammoId);
    if (ammo == null) return 'Deleted ($ammoId)';
    final parts = <String>[];
    if ((ammo.name ?? '').trim().isNotEmpty) {
      parts.add((ammo.name ?? '').trim());
    }
    if ((ammo.manufacturer ?? '').trim().isNotEmpty) {
      parts.add((ammo.manufacturer ?? '').trim());
    }
    if (ammo.caliber.trim().isNotEmpty) parts.add(ammo.caliber.trim());
    if (ammo.grain > 0) parts.add('${ammo.grain}gr');
    if (ammo.bullet.trim().isNotEmpty) parts.add(ammo.bullet.trim());
    return parts.isEmpty ? 'Ammo' : parts.join(' ');
  }

  String _pdfSessionLabel(TrainingSession s) {
    final location = s.locationName.trim().isEmpty
        ? 'No location'
        : s.locationName.trim();
    final rifle = _pdfRifleLabel(s.rifleId);
    final ammo = _pdfAmmoLabel(s.ammoLotId);
    return '${_pdfDateTime(s.dateTime)} | $location | $rifle | $ammo';
  }

  Future<DateTime?> _pickPdfFilterDate(
    BuildContext context, {
    required DateTime initialDate,
  }) async {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  Future<_PdfExportOptions?> _pickPdfOptions(BuildContext context) async {
    var includeSummary = true;
    var includeCharts = true;
    var includeRecentSessions = true;
    var includeUsedRifles = true;
    var includeUsedAmmo = true;
    var includeMaintenance = true;
    var includeEverything = false;
    var includeSessionDetails = true;
    var sessionFilterMode = _PdfSessionFilterMode.all;
    final selectedSessionIds = <String>{};
    DateTime? startDate;
    DateTime? endDate;
    final availableSessions = [...widget.state.allSessions]
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    String? folderFilter;
    int? yearFilter;
    String? monthFilter;
    final availableFolders =
        availableSessions
            .map((s) => s.folderName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final availableYears =
        availableSessions.map((s) => s.dateTime.year).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    final availableMonths =
        availableSessions
            .map(
              (s) =>
                  '${s.dateTime.year}-${s.dateTime.month.toString().padLeft(2, '0')}',
            )
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

    String monthLabel(String monthKey) {
      final parts = monthKey.split('-');
      if (parts.length != 2) return monthKey;
      final month = int.tryParse(parts[1]) ?? 1;
      const names = <String>[
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final name = (month >= 1 && month <= 12) ? names[month - 1] : parts[1];
      return '$name ${parts[0]}';
    }

    void applyPreset(
      _PdfExportOptions options,
      void Function(void Function()) setLocalState,
    ) {
      setLocalState(() {
        includeSummary = options.includeSummary;
        includeCharts = options.includeCharts;
        includeRecentSessions = options.includeRecentSessions;
        includeUsedRifles = options.includeUsedRifles;
        includeUsedAmmo = options.includeUsedAmmo;
        includeMaintenance = options.includeMaintenance;
        includeEverything = options.includeEverything;
        includeSessionDetails = options.includeSessionDetails;
        sessionFilterMode = options.sessionFilterMode;
        selectedSessionIds
          ..clear()
          ..addAll(options.selectedSessionIds);
        startDate = options.startDate;
        endDate = options.endDate;
        folderFilter = options.folderFilter;
        yearFilter = options.yearFilter;
        monthFilter = options.monthFilter;
      });
    }

    return showModalBottomSheet<_PdfExportOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PDF Export Options',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                if (_builtinPdfPresets.isNotEmpty ||
                    _savedPdfPresets.isNotEmpty) ...[
                  const Text(
                    'Presets',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in _builtinPdfPresets)
                        ActionChip(
                          label: Text(preset.name),
                          onPressed: () =>
                              applyPreset(preset.options, setLocalState),
                        ),
                      for (final preset in _savedPdfPresets)
                        ActionChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 18),
                          label: Text(preset.name),
                          onPressed: () =>
                              applyPreset(preset.options, setLocalState),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                CheckboxListTile(
                  value: includeSummary,
                  onChanged: (v) =>
                      setLocalState(() => includeSummary = v ?? false),
                  title: const Text('Summary cards (sessions, shots, average)'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: includeCharts,
                  onChanged: (v) =>
                      setLocalState(() => includeCharts = v ?? false),
                  title: const Text('Charts (top rifles and monthly shots)'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: includeRecentSessions,
                  onChanged: (v) =>
                      setLocalState(() => includeRecentSessions = v ?? false),
                  title: const Text('Recent sessions table (with location)'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: includeUsedRifles,
                  onChanged: (v) =>
                      setLocalState(() => includeUsedRifles = v ?? false),
                  title: const Text('Rifles used in sessions'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: includeUsedAmmo,
                  onChanged: (v) =>
                      setLocalState(() => includeUsedAmmo = v ?? false),
                  title: const Text('Ammo lots used in sessions'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: includeMaintenance,
                  onChanged: (v) =>
                      setLocalState(() => includeMaintenance = v ?? false),
                  title: const Text('Maintenance / service history'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: includeEverything,
                  onChanged: (v) =>
                      setLocalState(() => includeEverything = v ?? false),
                  title: const Text(
                    'Complete app-data appendix (all sessions, strings, DOPE, rifles, ammo)',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: includeSessionDetails,
                  onChanged: (v) =>
                      setLocalState(() => includeSessionDetails = v ?? false),
                  title: const Text(
                    'Session detail pages (notes, photos, cold-bore targets)',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Session Filter',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All sessions'),
                      selected: sessionFilterMode == _PdfSessionFilterMode.all,
                      onSelected: (_) => setLocalState(
                        () => sessionFilterMode = _PdfSessionFilterMode.all,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Selected sessions'),
                      selected:
                          sessionFilterMode == _PdfSessionFilterMode.selected,
                      onSelected: (_) => setLocalState(
                        () =>
                            sessionFilterMode = _PdfSessionFilterMode.selected,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Date range'),
                      selected:
                          sessionFilterMode == _PdfSessionFilterMode.dateRange,
                      onSelected: (_) => setLocalState(
                        () =>
                            sessionFilterMode = _PdfSessionFilterMode.dateRange,
                      ),
                    ),
                  ],
                ),
                if (sessionFilterMode == _PdfSessionFilterMode.selected) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setLocalState(() {
                          selectedSessionIds
                            ..clear()
                            ..addAll(availableSessions.map((s) => s.id));
                        }),
                        child: const Text('Select all'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setLocalState(selectedSessionIds.clear),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView(
                      shrinkWrap: true,
                      children: availableSessions.map((s) {
                        final checked = selectedSessionIds.contains(s.id);
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: checked,
                          title: Text(
                            _pdfSessionLabel(s),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (value) => setLocalState(() {
                            if (value == true) {
                              selectedSessionIds.add(s.id);
                            } else {
                              selectedSessionIds.remove(s.id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                if (sessionFilterMode == _PdfSessionFilterMode.dateRange) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start date'),
                    subtitle: Text(
                      startDate == null ? 'Not set' : _pdfDate(startDate!),
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final picked = await _pickPdfFilterDate(
                        context,
                        initialDate:
                            startDate ??
                            (availableSessions.isNotEmpty
                                ? availableSessions.last.dateTime
                                : DateTime.now()),
                      );
                      if (picked != null) {
                        setLocalState(() => startDate = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End date'),
                    subtitle: Text(
                      endDate == null ? 'Not set' : _pdfDate(endDate!),
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final picked = await _pickPdfFilterDate(
                        context,
                        initialDate:
                            endDate ??
                            (availableSessions.isNotEmpty
                                ? availableSessions.first.dateTime
                                : DateTime.now()),
                      );
                      if (picked != null) {
                        setLocalState(() => endDate = picked);
                      }
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setLocalState(() {
                        startDate = null;
                        endDate = null;
                      }),
                      child: const Text('Clear date range'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Additional Session Filters',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: folderFilter,
                  decoration: const InputDecoration(labelText: 'Folder'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All folders'),
                    ),
                    const DropdownMenuItem<String?>(
                      value: '__unfiled__',
                      child: Text('Unfiled only'),
                    ),
                    ...availableFolders.map(
                      (folder) => DropdownMenuItem<String?>(
                        value: folder,
                        child: Text(folder),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setLocalState(() => folderFilter = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: yearFilter,
                  decoration: const InputDecoration(labelText: 'Year'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All years'),
                    ),
                    ...availableYears.map(
                      (year) => DropdownMenuItem<int?>(
                        value: year,
                        child: Text('$year'),
                      ),
                    ),
                  ],
                  onChanged: (value) => setLocalState(() => yearFilter = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: monthFilter,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All months'),
                    ),
                    ...availableMonths.map(
                      (monthKey) => DropdownMenuItem<String?>(
                        value: monthKey,
                        child: Text(monthLabel(monthKey)),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setLocalState(() => monthFilter = value),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await _saveCurrentOptionsAsPreset(
                          context,
                          _PdfExportOptions(
                            includeSummary: includeSummary,
                            includeCharts: includeCharts,
                            includeRecentSessions: includeRecentSessions,
                            includeUsedRifles: includeUsedRifles,
                            includeUsedAmmo: includeUsedAmmo,
                            includeMaintenance: includeMaintenance,
                            includeEverything: includeEverything,
                            includeSessionDetails: includeSessionDetails,
                            sessionFilterMode: sessionFilterMode,
                            selectedSessionIds:
                                sessionFilterMode ==
                                    _PdfSessionFilterMode.selected
                                ? selectedSessionIds.toList()
                                : const [],
                            startDate:
                                sessionFilterMode ==
                                    _PdfSessionFilterMode.dateRange
                                ? startDate
                                : null,
                            endDate:
                                sessionFilterMode ==
                                    _PdfSessionFilterMode.dateRange
                                ? endDate
                                : null,
                            folderFilter: folderFilter,
                            yearFilter: yearFilter,
                            monthFilter: monthFilter,
                          ),
                        );
                        if (!context.mounted) return;
                      },
                      child: const Text('Save as preset'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(
                          _PdfExportOptions(
                            includeSummary: includeSummary,
                            includeCharts: includeCharts,
                            includeRecentSessions: includeRecentSessions,
                            includeUsedRifles: includeUsedRifles,
                            includeUsedAmmo: includeUsedAmmo,
                            includeMaintenance: includeMaintenance,
                            includeEverything: includeEverything,
                            includeSessionDetails: includeSessionDetails,
                            sessionFilterMode: sessionFilterMode,
                            selectedSessionIds:
                                sessionFilterMode ==
                                    _PdfSessionFilterMode.selected
                                ? selectedSessionIds.toList()
                                : const [],
                            startDate:
                                sessionFilterMode ==
                                    _PdfSessionFilterMode.dateRange
                                ? startDate
                                : null,
                            endDate:
                                sessionFilterMode ==
                                    _PdfSessionFilterMode.dateRange
                                ? endDate
                                : null,
                            folderFilter: folderFilter,
                            yearFilter: yearFilter,
                            monthFilter: monthFilter,
                          ),
                        );
                      },
                      child: const Text('Generate PDF'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _pdfDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final y = d.year.toString().padLeft(4, '0');
    return '$m/$day/$y';
  }

  String _pdfFileDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _distanceUnitLabel(DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.yards:
        return 'y';
      case DistanceUnit.meters:
        return 'm';
    }
  }

  String _elevationUnitLabel(ElevationUnit unit) {
    switch (unit) {
      case ElevationUnit.mil:
        return 'mil';
      case ElevationUnit.moa:
        return 'moa';
      case ElevationUnit.inches:
        return 'in';
    }
  }

  String _windTypeLabel(WindType type) {
    switch (type) {
      case WindType.fullValue:
        return 'full';
      case WindType.clock:
        return 'clock';
    }
  }

  String _pdfDateTime(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final y = d.year.toString().padLeft(4, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$m/$day/$y $hh:$mm';
  }

  String _pdfRifleLabel(String? rifleId) {
    if (rifleId == null) return '-';
    final rifle = widget.state.findRifleById(rifleId);
    if (rifle == null) return 'Deleted ($rifleId)';
    final name = (rifle.name ?? '').trim();
    if (name.isNotEmpty) return name;
    final model = [
      (rifle.manufacturer ?? '').trim(),
      (rifle.model ?? '').trim(),
    ].where((v) => v.isNotEmpty).join(' ');
    if (model.isNotEmpty) return model;
    return rifle.caliber.trim().isEmpty ? 'Rifle' : rifle.caliber.trim();
  }

  pw.Widget _pdfBarChart({
    required String title,
    required List<MapEntry<String, int>> entries,
    PdfColor color = PdfColors.blueGrey700,
  }) {
    if (entries.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text('$title: no data yet'),
      );
    }

    var maxValue = 1;
    for (final e in entries) {
      if (e.value > maxValue) maxValue = e.value;
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
        pw.SizedBox(height: 8),
        ...entries.map((e) {
          final width = 220 * (e.value / maxValue);
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 7),
            child: pw.Row(
              children: [
                pw.SizedBox(width: 125, child: pw.Text(e.key, maxLines: 1)),
                pw.Container(
                  width: width,
                  height: 10,
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text('${e.value}'),
              ],
            ),
          );
        }),
      ],
    );
  }

  pw.Widget _pdfDoubleBarChart({
    required String title,
    required List<MapEntry<String, double>> entries,
    PdfColor color = PdfColors.orange700,
  }) {
    if (entries.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text('$title: no data yet'),
      );
    }

    var maxValue = 0.0;
    for (final e in entries) {
      if (e.value > maxValue) maxValue = e.value;
    }
    if (maxValue <= 0) maxValue = 1;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
        pw.SizedBox(height: 8),
        ...entries.map((e) {
          final width = 220 * (e.value / maxValue);
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 7),
            child: pw.Row(
              children: [
                pw.SizedBox(width: 125, child: pw.Text(e.key, maxLines: 1)),
                pw.Container(
                  width: width,
                  height: 10,
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text('${e.value.toStringAsFixed(2)} in'),
              ],
            ),
          );
        }),
      ],
    );
  }

  List<_ColdBoreRow> _coldBoreRowsForSessions(List<TrainingSession> sessions) {
    final out = <_ColdBoreRow>[];
    for (final session in sessions) {
      final sessionRifle = session.rifleId == null
          ? null
          : widget.state.findRifleById(session.rifleId!);
      final sessionAmmo = session.ammoLotId == null
          ? null
          : widget.state.findAmmoLotById(session.ammoLotId!);
      for (final shot in session.shots.where((s) => s.isColdBore)) {
        out.add(
          _ColdBoreRow(
            session: session,
            shot: shot,
            rifle: sessionRifle,
            ammo: sessionAmmo,
            stringId: null,
          ),
        );
      }
    }
    out.sort((a, b) => a.shot.time.compareTo(b.shot.time));
    return out;
  }

  pw.Widget _pdfColdBoreTargetPlot(List<_ColdBoreRow> rows) {
    const size = 240.0;
    const halfSpanInches = 6.0;
    const fullSpanInches = halfSpanInches * 2;

    final plottedRows = rows
        .where((row) => row.shot.offsetX != null && row.shot.offsetY != null)
        .toList();
    final hiddenCount = rows.length - plottedRows.length;

    if (plottedRows.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text('No plotted cold bore impacts yet.'),
      );
    }

    final step = size / fullSpanInches;
    final center = size / 2;

    pw.Positioned point(_ColdBoreRow row) {
      final xInches = _shotOffsetToInches(
        row.shot,
        row.shot.offsetX!,
      ).clamp(-halfSpanInches, halfSpanInches);
      final yInches = _shotOffsetToInches(
        row.shot,
        row.shot.offsetY!,
      ).clamp(-halfSpanInches, halfSpanInches);
      final nx = (xInches + halfSpanInches) / fullSpanInches;
      final ny = (halfSpanInches - yInches) / fullSpanInches;
      final x = nx * size;
      final y = ny * size;
      return pw.Positioned(
        left: x - 3.5,
        top: y - 3.5,
        child: pw.Container(
          width: 7,
          height: 7,
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            color: row.shot.isBaseline ? PdfColors.amber700 : PdfColors.blue900,
            border: pw.Border.all(color: PdfColors.white, width: 0.8),
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(
              'Cold-bore target (${plottedRows.length} plotted)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            if (hiddenCount > 0)
              pw.Text(
                '  •  $hiddenCount missing offsets',
                style: const pw.TextStyle(fontSize: 9),
              ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.SizedBox(
            width: size,
            height: size,
            child: pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      border: pw.Border.all(color: PdfColors.grey700, width: 1),
                    ),
                  ),
                ),
                for (var i = 1; i < fullSpanInches; i++) ...[
                  if ((i * step - center).abs() > 0.01)
                    pw.Positioned(
                      left: i * step,
                      top: 0,
                      bottom: 0,
                      child: pw.Container(width: 0.7, color: PdfColors.grey400),
                    ),
                  if ((i * step - center).abs() > 0.01)
                    pw.Positioned(
                      top: i * step,
                      left: 0,
                      right: 0,
                      child: pw.Container(
                        height: 0.7,
                        color: PdfColors.grey400,
                      ),
                    ),
                ],
                pw.Positioned(
                  left: center,
                  top: 0,
                  bottom: 0,
                  child: pw.Container(width: 1.2, color: PdfColors.grey800),
                ),
                pw.Positioned(
                  top: center,
                  left: 0,
                  right: 0,
                  child: pw.Container(height: 1.2, color: PdfColors.grey800),
                ),
                pw.Positioned(
                  left: center - 2,
                  top: center - 2,
                  child: pw.Container(
                    width: 4,
                    height: 4,
                    decoration: const pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      color: PdfColors.red700,
                    ),
                  ),
                ),
                ...plottedRows.map(point),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Grid spacing is 1 inch. Baseline points are gold.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    );
  }

  pw.Widget _pdfColdBoreAdjustmentChart(List<_ColdBoreRow> rows) {
    final plottedRows =
        rows
            .where(
              (row) => row.shot.offsetX != null && row.shot.offsetY != null,
            )
            .toList()
          ..sort((a, b) => a.shot.time.compareTo(b.shot.time));

    if (plottedRows.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text('No plotted cold bore impacts yet.'),
      );
    }

    final byDate = <String, List<double>>{};
    for (final row in plottedRows) {
      final dx = _shotOffsetToInches(row.shot, row.shot.offsetX!);
      final dy = _shotOffsetToInches(row.shot, row.shot.offsetY!);
      final radialInches = math.sqrt((dx * dx) + (dy * dy));
      final dateKey = _pdfDate(row.shot.time);
      byDate.putIfAbsent(dateKey, () => <double>[]).add(radialInches);
    }

    final avgByDate = byDate.entries.map((entry) {
      final vals = entry.value;
      final avg = vals.fold<double>(0, (sum, v) => sum + v) / vals.length;
      return MapEntry(entry.key, avg);
    }).toList();

    final recent = avgByDate.length > 10
        ? avgByDate.sublist(avgByDate.length - 10)
        : avgByDate;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pdfDoubleBarChart(
          title: 'Cold-bore adjustment trend by date',
          entries: recent,
          color: PdfColors.orange700,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Average radial offset from point of aim for each date.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    );
  }

  Future<void> _exportPdfReport(BuildContext context) async {
    try {
      final options = await _pickPdfOptions(context);
      if (options == null) return;

      await _exportPdfReportWithOptions(context, options);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
  }

  Future<void> _exportPdfReportWithOptions(
    BuildContext context,
    _PdfExportOptions options,
  ) async {
    try {
      final allSessions = [...widget.state.allSessions]
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

      final modeFilteredSessions = switch (options.sessionFilterMode) {
        _PdfSessionFilterMode.all => allSessions,
        _PdfSessionFilterMode.selected =>
          allSessions
              .where(
                (session) => options.selectedSessionIds.contains(session.id),
              )
              .toList(),
        _PdfSessionFilterMode.dateRange => allSessions.where((session) {
          final sessionDate = DateTime(
            session.dateTime.year,
            session.dateTime.month,
            session.dateTime.day,
          );
          final startDate = options.startDate == null
              ? null
              : DateTime(
                  options.startDate!.year,
                  options.startDate!.month,
                  options.startDate!.day,
                );
          final endDate = options.endDate == null
              ? null
              : DateTime(
                  options.endDate!.year,
                  options.endDate!.month,
                  options.endDate!.day,
                );
          final afterStart =
              startDate == null || !sessionDate.isBefore(startDate);
          final beforeEnd = endDate == null || !sessionDate.isAfter(endDate);
          return afterStart && beforeEnd;
        }).toList(),
      };

      final scopedSessions = modeFilteredSessions.where((session) {
        if (options.folderFilter != null) {
          final folder = session.folderName.trim();
          if (options.folderFilter == '__unfiled__') {
            if (folder.isNotEmpty) return false;
          } else if (folder != options.folderFilter) {
            return false;
          }
        }
        if (options.yearFilter != null &&
            session.dateTime.year != options.yearFilter) {
          return false;
        }
        if (options.monthFilter != null) {
          final monthKey =
              '${session.dateTime.year}-${session.dateTime.month.toString().padLeft(2, '0')}';
          if (monthKey != options.monthFilter) {
            return false;
          }
        }
        return true;
      }).toList();

      if (scopedSessions.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No sessions matched the selected export filter.'),
          ),
        );
        return;
      }

      int sessionShotCount(TrainingSession s) {
        final byStrings = s.shotsByString.values.fold<int>(
          0,
          (sum, list) => sum + list.length,
        );
        final fallback = s.shots.length >= byStrings
            ? s.shots.length
            : byStrings;
        return s.confirmedShotCount ?? fallback;
      }

      List<pw.Widget> buildSessionDetailSection(TrainingSession session) {
        final coldBoreShots = session.shots
            .where((shot) => shot.isColdBore)
            .toList();
        final widgets = <pw.Widget>[
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfSessionLabel(session),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Rounds: ${sessionShotCount(session)}   Strings: ${session.strings.length}   Cold bore: ${coldBoreShots.length}',
                ),
              ],
            ),
          ),
        ];

        if (session.notes.trim().isNotEmpty) {
          widgets.addAll([
            pw.Text(
              'Session Notes',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(session.notes.trim()),
            pw.SizedBox(height: 8),
          ]);
        }

        if (session.photos.isNotEmpty) {
          widgets.addAll([
            pw.Text(
              'Photo Notes',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            ...session.photos.map(
              (photoNote) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                  '${_pdfDateTime(photoNote.time)} - ${photoNote.caption.trim().isEmpty ? 'No note' : photoNote.caption.trim()}',
                ),
              ),
            ),
            pw.SizedBox(height: 8),
          ]);
        }

        if (session.sessionPhotos.isNotEmpty) {
          widgets.addAll([
            pw.Text(
              'Session Photos',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final photo in session.sessionPhotos)
                  pw.Container(
                    width: 145,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 145,
                          height: 100,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                              color: PdfColors.grey500,
                              width: 0.5,
                            ),
                          ),
                          child: pw.Image(
                            pw.MemoryImage(photo.bytes),
                            fit: pw.BoxFit.cover,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          photo.caption.trim().isEmpty
                              ? _pdfDateTime(photo.time)
                              : '${_pdfDateTime(photo.time)} - ${photo.caption.trim()}',
                          style: const pw.TextStyle(fontSize: 8),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 8),
          ]);
        }

        if (coldBoreShots.isNotEmpty) {
          widgets.addAll([
            pw.Text(
              'Cold-Bore Shots',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'See Charts for the combined impact plot and adjustment trend.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            for (final shot in coldBoreShots)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${_pdfDateTime(shot.time)} | ${shot.result.trim().isEmpty ? '-' : shot.result.trim()} | ${shot.distance.trim().isEmpty ? '-' : shot.distance.trim()}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    if (shot.notes.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(shot.notes.trim()),
                    ],
                    if (shot.photos.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      pw.Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final photo in shot.photos)
                            pw.Container(
                              width: 140,
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Container(
                                    width: 140,
                                    height: 95,
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border.all(
                                        color: PdfColors.grey500,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: pw.Image(
                                      pw.MemoryImage(photo.bytes),
                                      fit: pw.BoxFit.cover,
                                    ),
                                  ),
                                  pw.SizedBox(height: 3),
                                  pw.Text(
                                    photo.caption.trim().isEmpty
                                        ? _pdfDateTime(photo.time)
                                        : '${_pdfDateTime(photo.time)} - ${photo.caption.trim()}',
                                    style: const pw.TextStyle(fontSize: 8),
                                    maxLines: 3,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            pw.SizedBox(height: 4),
          ]);
        }

        widgets.add(pw.Divider());
        return widgets;
      }

      final sessions = scopedSessions;
      final totalSessions = sessions.length;
      final totalShots = sessions.fold<int>(
        0,
        (total, s) => total + sessionShotCount(s),
      );
      final avgShots = totalSessions == 0 ? 0.0 : totalShots / totalSessions;

      final byRifle = <String, int>{};
      for (final s in sessions) {
        final rifleId = s.rifleId;
        if (rifleId == null) continue;
        final count = sessionShotCount(s);
        byRifle.update(rifleId, (v) => v + count, ifAbsent: () => count);
      }

      final topRifles =
          byRifle.entries
              .map((e) => MapEntry(_pdfRifleLabel(e.key), e.value))
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));

      final monthShots = <String, int>{};
      for (final s in sessions) {
        final key =
            '${s.dateTime.year}-${s.dateTime.month.toString().padLeft(2, '0')}';
        final count = sessionShotCount(s);
        monthShots.update(key, (v) => v + count, ifAbsent: () => count);
      }
      final monthSeries = monthShots.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final recentMonths = monthSeries.length > 6
          ? monthSeries.sublist(monthSeries.length - 6)
          : monthSeries;
      final allColdBoreRows = _coldBoreRowsForSessions(sessions);

      final usedRifleIds = <String>{};
      final usedAmmoIds = <String>{};
      for (final s in sessions) {
        if (s.rifleId != null) usedRifleIds.add(s.rifleId!);
        if (s.ammoLotId != null) usedAmmoIds.add(s.ammoLotId!);
        for (final st in s.strings) {
          if (st.rifleId != null) usedRifleIds.add(st.rifleId!);
          if (st.ammoLotId != null) usedAmmoIds.add(st.ammoLotId!);
        }
      }
      final usedRifles = widget.state.rifles
          .where((r) => usedRifleIds.contains(r.id))
          .toList();
      final usedAmmo = widget.state.ammoLots
          .where((a) => usedAmmoIds.contains(a.id))
          .toList();
      final allRifles = [...widget.state.rifles]
        ..sort((a, b) => _pdfRifleLabel(a.id).compareTo(_pdfRifleLabel(b.id)));
      final allAmmo = [...widget.state.ammoLots]
        ..sort((a, b) => _pdfAmmoLabel(a.id).compareTo(_pdfAmmoLabel(b.id)));

      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => [
            pw.Text(
              'Cold Bore - Range Report',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Generated ${_pdfDateTime(DateTime.now())}'),
            if (options.includeSummary) ...[
              pw.SizedBox(height: 14),
              pw.Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  pw.Container(
                    width: 165,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Sessions',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          '$totalSessions',
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: 165,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Total shots',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          '$totalShots',
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: 165,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Average shots/session',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          avgShots.toStringAsFixed(1),
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (options.includeCharts) ...[
              pw.SizedBox(height: 16),
              _pdfBarChart(
                title: 'Top Rifles by Shots',
                entries: topRifles.take(6).toList(),
              ),
              pw.SizedBox(height: 14),
              _pdfBarChart(
                title: 'Shots per Month',
                entries: recentMonths,
                color: PdfColors.teal700,
              ),
              pw.SizedBox(height: 14),
              _pdfColdBoreTargetPlot(allColdBoreRows),
              pw.SizedBox(height: 12),
              _pdfColdBoreAdjustmentChart(allColdBoreRows),
            ],
            if (options.includeRecentSessions) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Recent Sessions',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const ['Date', 'Location', 'Rifle', 'Ammo', 'Shots'],
                data: sessions.take(30).map((s) {
                  final location = s.locationName.isEmpty
                      ? '-'
                      : s.locationName;
                  return [
                    _pdfDate(s.dateTime),
                    location,
                    _pdfRifleLabel(s.rifleId),
                    _pdfAmmoLabel(s.ammoLotId),
                    '${sessionShotCount(s)}',
                  ];
                }).toList(),
              ),
            ],
            if (options.includeUsedRifles) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Rifles Used',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const [
                  'Name',
                  'Caliber',
                  'Rounds',
                  'Barrel Rounds',
                  'Serial',
                ],
                data: usedRifles.map((r) {
                  final display = (r.name ?? '').trim().isNotEmpty
                      ? (r.name ?? '').trim()
                      : [
                          (r.manufacturer ?? '').trim(),
                          (r.model ?? '').trim(),
                        ].where((v) => v.isNotEmpty).join(' ');
                  return [
                    display.isEmpty ? 'Rifle' : display,
                    r.caliber,
                    '${r.manualRoundCount}',
                    '${r.barrelRoundCount}',
                    (r.serialNumber ?? '').trim().isEmpty
                        ? '-'
                        : (r.serialNumber ?? '').trim(),
                  ];
                }).toList(),
              ),
            ],
            if (options.includeUsedAmmo) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Ammo Used',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const ['Name', 'Caliber', 'Bullet', 'Lot', 'BC'],
                data: usedAmmo.map((a) {
                  final display = (a.name ?? '').trim().isEmpty
                      ? 'Ammo lot'
                      : (a.name ?? '').trim();
                  return [
                    display,
                    a.caliber,
                    '${a.grain}gr ${a.bullet}',
                    ((a.lotNumber ?? '').trim().isEmpty)
                        ? '-'
                        : (a.lotNumber ?? '').trim(),
                    a.ballisticCoefficient?.toStringAsFixed(3) ?? '-',
                  ];
                }).toList(),
              ),
            ],
            if (options.includeMaintenance) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Maintenance / Service History',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              for (final r in usedRifles) ...[
                pw.Text(
                  _pdfRifleLabel(r.id),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                if (r.services.isEmpty)
                  pw.Text('No service entries logged.')
                else
                  pw.Table.fromTextArray(
                    border: pw.TableBorder.all(
                      color: PdfColors.grey400,
                      width: 0.5,
                    ),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    cellStyle: const pw.TextStyle(fontSize: 9),
                    headers: const ['Date', 'Service', 'Rounds', 'Notes'],
                    data: r.services
                        .map(
                          (svc) => [
                            _pdfDate(svc.date),
                            svc.service,
                            '${svc.roundsAtService}',
                            svc.notes.isEmpty ? '-' : svc.notes,
                          ],
                        )
                        .toList(),
                  ),
                pw.SizedBox(height: 8),
              ],
            ],
            if (options.includeSessionDetails) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Session Detail Pages',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              ...sessions.expand(buildSessionDetailSection),
            ],
            if (options.includeEverything) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                'Complete App Data Appendix',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'All Rifles',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const [
                  'Name',
                  'Caliber',
                  'Round Count',
                  'Barrel Rounds',
                  'Serial',
                ],
                data: allRifles
                    .map(
                      (r) => [
                        _pdfRifleLabel(r.id),
                        r.caliber,
                        '${r.manualRoundCount}',
                        '${r.barrelRoundCount}',
                        (r.serialNumber ?? '').trim().isEmpty
                            ? '-'
                            : (r.serialNumber ?? '').trim(),
                      ],
                    )
                    .toList(),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'All Ammo Lots',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const ['Name', 'Caliber', 'Bullet', 'Lot', 'BC'],
                data: allAmmo
                    .map(
                      (a) => [
                        _pdfAmmoLabel(a.id),
                        a.caliber,
                        '${a.grain}gr ${a.bullet}'.trim(),
                        ((a.lotNumber ?? '').trim().isEmpty)
                            ? '-'
                            : (a.lotNumber ?? '').trim(),
                        a.ballisticCoefficient?.toStringAsFixed(3) ?? '-',
                      ],
                    )
                    .toList(),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'All Sessions',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const [
                  'Date',
                  'Location',
                  'Rifle',
                  'Ammo',
                  'Shots',
                  'Strings',
                  'DOPE',
                ],
                data: sessions
                    .map(
                      (s) => [
                        _pdfDate(s.dateTime),
                        s.locationName.isEmpty ? '-' : s.locationName,
                        _pdfRifleLabel(s.rifleId),
                        _pdfAmmoLabel(s.ammoLotId),
                        '${sessionShotCount(s)}',
                        '${s.strings.length}',
                        '${s.trainingDope.length}',
                      ],
                    )
                    .toList(),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'All Session Strings',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const [
                  'Session Date',
                  'String #',
                  'Rifle',
                  'Ammo',
                  'Shots',
                  'DOPE Entries',
                ],
                data: [
                  for (final s in sessions) ...[
                    for (var i = 0; i < s.strings.length; i++)
                      [
                        _pdfDate(s.dateTime),
                        '${i + 1}',
                        _pdfRifleLabel(s.strings[i].rifleId),
                        _pdfAmmoLabel(s.strings[i].ammoLotId),
                        '${(s.shotsByString[s.strings[i].id] ?? const <ShotEntry>[]).length}',
                        '${(s.trainingDopeByString[s.strings[i].id] ?? const <DopeEntry>[]).length}',
                      ],
                    if (sessionShotCount(s) >
                        s.shotsByString.values.fold<int>(
                          0,
                          (sum, list) => sum + list.length,
                        ))
                      [
                        _pdfDate(s.dateTime),
                        'Unassigned',
                        _pdfRifleLabel(s.rifleId),
                        _pdfAmmoLabel(s.ammoLotId),
                        '${sessionShotCount(s) - s.shotsByString.values.fold<int>(0, (sum, list) => sum + list.length)}',
                        '0',
                      ],
                  ],
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Cold Bore Entries',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const [
                  'Session Date',
                  'Shot Time',
                  'Rifle',
                  'Ammo',
                  'Distance',
                  'Result',
                  'Baseline',
                  'Notes',
                ],
                data: [
                  for (final s in sessions)
                    for (final shot in s.shots.where((x) => x.isColdBore))
                      [
                        _pdfDate(s.dateTime),
                        _pdfDateTime(shot.time),
                        _pdfRifleLabel(s.rifleId),
                        _pdfAmmoLabel(s.ammoLotId),
                        shot.distance.trim().isEmpty
                            ? '-'
                            : shot.distance.trim(),
                        shot.result.trim().isEmpty ? '-' : shot.result.trim(),
                        shot.isBaseline ? 'Yes' : 'No',
                        shot.notes.trim().isEmpty ? '-' : shot.notes.trim(),
                      ],
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Cold Bore Display Targets',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              ...[
                for (final s in sessions)
                  for (final shot in s.shots.where((x) => x.isColdBore))
                    pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '${_pdfDateTime(shot.time)} | ${_pdfRifleLabel(s.rifleId)} | ${_pdfAmmoLabel(s.ammoLotId)}',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          if (shot.photos.isEmpty)
                            pw.Text(
                              'No display target image attached.',
                              style: const pw.TextStyle(fontSize: 9),
                            )
                          else
                            pw.Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final p in shot.photos)
                                  pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Container(
                                        width: 130,
                                        height: 130,
                                        decoration: pw.BoxDecoration(
                                          border: pw.Border.all(
                                            color: PdfColors.grey500,
                                            width: 0.5,
                                          ),
                                        ),
                                        child: pw.Image(
                                          pw.MemoryImage(p.bytes),
                                          fit: pw.BoxFit.cover,
                                        ),
                                      ),
                                      if (p.caption.trim().isNotEmpty)
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: pw.Text(
                                            p.caption.trim(),
                                            style: const pw.TextStyle(
                                              fontSize: 8,
                                            ),
                                            maxLines: 2,
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
              ],
              pw.SizedBox(height: 12),
              pw.Text(
                'Working DOPE (Rifle + Ammo)',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const [
                  'Rifle',
                  'Ammo',
                  'Distance',
                  'Elevation',
                  'Wind',
                  'L',
                  'R',
                ],
                data: [
                  for (final bucket in widget.state.workingDopeRifleAmmo.values)
                    for (final dope in bucket.values)
                      [
                        _pdfRifleLabel(dope.rifleId),
                        _pdfAmmoLabel(dope.ammoLotId),
                        '${dope.distance} ${_distanceUnitLabel(dope.distanceUnit)}',
                        '${dope.elevation} ${_elevationUnitLabel(dope.elevationUnit)}',
                        '${_windTypeLabel(dope.windType)} ${dope.windValue}'
                            .trim(),
                        dope.windageLeft.toStringAsFixed(2),
                        dope.windageRight.toStringAsFixed(2),
                      ],
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Working DOPE (Rifle Only)',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: const [
                  'Rifle',
                  'Distance',
                  'Elevation',
                  'Wind',
                  'L',
                  'R',
                ],
                data: [
                  for (final bucket in widget.state.workingDopeRifleOnly.values)
                    for (final dope in bucket.values)
                      [
                        _pdfRifleLabel(dope.rifleId),
                        '${dope.distance} ${_distanceUnitLabel(dope.distanceUnit)}',
                        '${dope.elevation} ${_elevationUnitLabel(dope.elevationUnit)}',
                        '${_windTypeLabel(dope.windType)} ${dope.windValue}'
                            .trim(),
                        dope.windageLeft.toStringAsFixed(2),
                        dope.windageRight.toStringAsFixed(2),
                      ],
                ],
              ),
            ],
          ],
        ),
      );

      final bytes = await doc.save();
      final filename = 'cold_bore_report_${_pdfFileDate(DateTime.now())}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: filename);

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF report generated.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
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
                const _SectionTitle('Export'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('PDF report (choose sections)'),
                    subtitle: const Text(
                      'Select what to include: charts, sessions, rifles, ammo, maintenance.',
                    ),
                    onTap: () => _exportPdfReport(context),
                  ),
                ),
                if (_builtinPdfPresets.isNotEmpty ||
                    _savedPdfPresets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Quick PDF presets',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in _builtinPdfPresets)
                        ActionChip(
                          label: Text(preset.name),
                          onPressed: () => _exportPdfReportWithOptions(
                            context,
                            preset.options,
                          ),
                        ),
                      for (final preset in _savedPdfPresets)
                        ActionChip(
                          avatar: const Icon(Icons.bookmark, size: 18),
                          label: Text(preset.name),
                          onPressed: () => _exportPdfReportWithOptions(
                            context,
                            preset.options,
                          ),
                        ),
                    ],
                  ),
                ],
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
            Icon(icon, size: 56, color: cs.onSurface.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
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
    final r = state.rifles.firstWhere(
      (x) => x.id == id,
      orElse: () => Rifle(
        id: id,
        caliber: '',
        notes: '',
        dope: '',
        dopeEntries: const [],
        preferredUnit: ElevationUnit.mil,
      ),
    );
    final parts = <String>[];
    if (r.manufacturer != null && r.manufacturer!.trim().isNotEmpty) {
      parts.add(r.manufacturer!.trim());
    }
    if (r.model != null && r.model!.trim().isNotEmpty) {
      parts.add(r.model!.trim());
    }
    if (r.caliber.trim().isNotEmpty) parts.add(r.caliber.trim());
    if (r.name != null && r.name!.trim().isNotEmpty) {
      parts.add('"${r.name!.trim()}"');
    }
    return parts.isEmpty ? id : parts.join(' • ');
  }

  String _ammoLabel(String? id) {
    if (id == null) return '—';
    final a = state.ammoLots.firstWhere(
      (x) => x.id == id,
      orElse: () =>
          AmmoLot(id: id, caliber: '', grain: 0, bullet: '', notes: ''),
    );
    final parts = <String>[];
    if (a.manufacturer != null && a.manufacturer!.trim().isNotEmpty) {
      parts.add(a.manufacturer!.trim());
    }
    if (a.name != null && a.name!.trim().isNotEmpty) parts.add(a.name!.trim());
    final bullet = a.bullet.trim().isEmpty ? null : a.bullet.trim();
    if (bullet != null) parts.add(bullet);
    if (a.grain > 0) parts.add('${a.grain}gr');
    if (a.caliber.trim().isNotEmpty) parts.add(a.caliber.trim());
    return parts.isEmpty ? id : parts.join(' • ');
  }

  String _fmt(DateTime d) {
    return '${d.month}/${d.day}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = session.strings.length;
    final activeIdx = session.strings.indexWhere(
      (x) => x.id == session.activeStringId,
    );
    final n = (activeIdx >= 0) ? (activeIdx + 1) : total;
    final active = (activeIdx >= 0) ? session.strings[activeIdx] : null;

    final started = (active == null) ? '—' : _fmt(active.startedAt);

    return Card(
      child: ListTile(
        title: Text('String $n of $total'),
        subtitle: Text(
          'Started: $started\nRifle: ${_rifleLabel(active?.rifleId)}\nAmmo: ${_ammoLabel(active?.ammoLotId)}',
        ),
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
    return '${d.month}/${d.day}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _rifleLabel(String? id) {
    if (id == null) return '—';
    final r = state.rifles.firstWhere(
      (x) => x.id == id,
      orElse: () => Rifle(
        id: id,
        caliber: '',
        notes: '',
        dope: '',
        dopeEntries: const [],
        preferredUnit: ElevationUnit.mil,
      ),
    );
    final parts = <String>[];
    if (r.manufacturer != null && r.manufacturer!.trim().isNotEmpty) {
      parts.add(r.manufacturer!.trim());
    }
    if (r.model != null && r.model!.trim().isNotEmpty) {
      parts.add(r.model!.trim());
    }
    if (r.caliber.trim().isNotEmpty) parts.add(r.caliber.trim());
    if (r.name != null && r.name!.trim().isNotEmpty) {
      parts.add('"${r.name!.trim()}"');
    }
    return parts.isEmpty ? id : parts.join(' • ');
  }

  String _ammoLabel(String? id) {
    if (id == null) return '—';
    final a = state.ammoLots.firstWhere(
      (x) => x.id == id,
      orElse: () =>
          AmmoLot(id: id, caliber: '', grain: 0, bullet: '', notes: ''),
    );
    final parts = <String>[];
    if (a.manufacturer != null && a.manufacturer!.trim().isNotEmpty) {
      parts.add(a.manufacturer!.trim());
    }
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
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
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(message),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: onAction,
                        child: Text(actionLabel!),
                      ),
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

class _UniqueIdentifierResult {
  final String name;
  final String identifier;

  const _UniqueIdentifierResult({required this.name, required this.identifier});
}

class _UniqueIdentifierPromptDialog extends StatefulWidget {
  const _UniqueIdentifierPromptDialog();

  @override
  State<_UniqueIdentifierPromptDialog> createState() =>
      _UniqueIdentifierPromptDialogState();
}

class _UniqueIdentifierPromptDialogState
    extends State<_UniqueIdentifierPromptDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _identifier = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _identifier.dispose();
    super.dispose();
  }

  void _submit() {
    final rawIdentifier = _normalizeUserIdentifier(_identifier.text);
    final error = _userIdentifierValidationMessage(rawIdentifier);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final rawName = _name.text.trim();
    Navigator.of(context).pop(
      _UniqueIdentifierResult(
        name: rawName.isEmpty ? rawIdentifier : rawName,
        identifier: rawIdentifier,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set your user identifier'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Create a unique identifier so nearby and remote partner sharing can find this device.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.words,
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              textCapitalization: TextCapitalization.characters,
              controller: _identifier,
              decoration: const InputDecoration(
                labelText: 'Unique identifier *',
                hintText: 'e.g. RANGER1',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tip: use something short and memorable. Example: RANGER1 or SPOTTER_A.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Set up later'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _name = TextEditingController();
  final _id = TextEditingController();
  String? _error;

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
            textCapitalization: TextCapitalization.characters,
            controller: _id,
            decoration: const InputDecoration(
              labelText: 'Identifier *',
              hintText: 'e.g. RANGER1',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('Load from Files')),
              TextButton.icon(
                onPressed: () async {
                  final res = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['json'],
                    withData: true,
                  );
                  if (res == null || res.files.isEmpty) return;
                  final bytes = res.files.single.bytes;
                  if (bytes == null) return;
                  setState(() {
                    _id.text = utf8.decode(bytes);
                  });
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse'),
              ),
            ],
          ),

          TextField(
            textCapitalization: TextCapitalization.none,
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final nameRaw = _name.text.trim();
            final name = nameRaw.isEmpty ? null : nameRaw;
            final identifier = _normalizeUserIdentifier(_id.text);
            final error = _userIdentifierValidationMessage(
              identifier,
              allowSeed: true,
            );
            if (error != null) {
              setState(() => _error = error);
              return;
            }
            Navigator.of(context).pop(
              _NewUserResult(
                ((name ?? '').trim().isEmpty)
                    ? identifier
                    : (name ?? '').trim(),
                identifier,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _NewSessionResult {
  final String locationName;
  final String folderName;
  final DateTime dateTime;
  final String notes;
  final double? latitude;
  final double? longitude;
  final double? temperatureF;
  final double? windSpeedMph;
  final int? windDirectionDeg;
  _NewSessionResult({
    required this.locationName,
    required this.folderName,
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
  final _folder = TextEditingController();
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
    _folder.dispose();
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
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _gpsError = 'Location permission denied.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lat = pos.latitude;
      _lon = pos.longitude;
      _location.text =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
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
        '?latitude=$_lat&longitude=$_lon'
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
      initialEntryMode: TimePickerEntryMode.inputOnly,
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
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location *'),
              maxLines: 1,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _folder,
              decoration: const InputDecoration(
                labelText: 'Folder (optional)',
                helperText: 'Examples: 2026 Season, PRS Matches, Team Practice',
              ),
              maxLines: 1,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              textCapitalization: TextCapitalization.none,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lat == null || _lon == null
                      ? (_gpsError ?? 'GPS: not set')
                      : 'GPS: ${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busy ? null : _fillGps,
                      child: Text(_busy ? '...' : 'Use GPS'),
                    ),
                    FilledButton.tonal(
                      onPressed: _busy ? null : _grabWeather,
                      child: Text(_busy ? '...' : 'Grab Weather'),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    controller: _tempF,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Temp (°F)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    controller: _windMph,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Wind (mph)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    controller: _windDir,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Wind dir (°)',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final loc = _location.text.trim();
            if (loc.isEmpty) return;
            Navigator.of(context).pop(
              _NewSessionResult(
                locationName: loc,
                folderName: _folder.text.trim(),
                dateTime: _dateTime,
                notes: _notes.text,
                latitude: _lat,
                longitude: _lon,
                temperatureF: double.tryParse(_tempF.text.trim()),
                windSpeedMph: double.tryParse(_windMph.text.trim()),
                windDirectionDeg: int.tryParse(_windDir.text.trim()),
              ),
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
  final double? offsetX;
  final double? offsetY;
  final String offsetUnit;
  final Uint8List? photoBytes;

  _ColdBoreResult({
    required this.time,
    required this.distance,
    required this.result,
    required this.notes,
    required this.offsetX,
    required this.offsetY,
    required this.offsetUnit,
    required this.photoBytes,
  });
}

class _ColdBoreDialog extends StatefulWidget {
  _ColdBoreDialog({DateTime? defaultTime})
    : defaultTime = defaultTime ?? DateTime.now();

  final DateTime defaultTime;

  @override
  State<_ColdBoreDialog> createState() => _ColdBoreDialogState();
}

class _ColdBoreDialogState extends State<_ColdBoreDialog> {
  static const List<String> _resultPresets = <String>[
    'Impact OK',
    'High',
    'Low',
    'Left',
    'Right',
    'Miss',
    'Called flyer',
  ];

  final _distance = TextEditingController(text: '100 yd');
  final _result = TextEditingController(text: 'Impact OK');
  final _notes = TextEditingController();
  final _hOffsetCtrl = TextEditingController();
  final _vOffsetCtrl = TextEditingController();

  bool _hasOffset = false;
  String _offsetUnit = 'in';
  bool _horizontalRight = true;
  bool _verticalUp = true;

  Uint8List? _photoBytes;

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
    _hOffsetCtrl.dispose();
    _vOffsetCtrl.dispose();
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

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: source, imageQuality: 90);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytes = bytes);
    } catch (e, st) {
      debugPrint('Photo pick failed: $e\n$st');
    }
  }

  Future<void> _choosePhoto() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'camera') {
      await _pickPhoto(ImageSource.camera);
    } else {
      await _pickPhoto(ImageSource.gallery);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cold bore entry'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.70,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Time: ${_fmtDateTime(_time)}')),
                  TextButton(onPressed: _pickTime, child: const Text('Edit')),
                ],
              ),
              TextField(
                textCapitalization: TextCapitalization.none,
                controller: _distance,
                decoration: const InputDecoration(labelText: 'Distance'),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                textCapitalization: TextCapitalization.none,
                controller: _result,
                decoration: const InputDecoration(
                  labelText: 'Result',
                  helperText: 'Pick a quick result below or type your own.',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _resultPresets.map((preset) {
                    final selected =
                        _result.text.trim().toLowerCase() ==
                        preset.toLowerCase();
                    return ChoiceChip(
                      label: Text(preset),
                      selected: selected,
                      onSelected: (_) => setState(() => _result.text = preset),
                    );
                  }).toList(),
                ),
              ),
              TextField(
                textCapitalization: TextCapitalization.none,
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              // Photo
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _photoBytes == null ? 'Photo: none' : 'Photo: attached',
                    ),
                  ),
                  TextButton(
                    onPressed: _choosePhoto,
                    child: Text(_photoBytes == null ? 'Add photo' : 'Replace'),
                  ),
                  if (_photoBytes != null)
                    IconButton(
                      tooltip: 'Remove photo',
                      onPressed: () => setState(() => _photoBytes = null),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
              if (_photoBytes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _photoBytes!,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              const Text(
                'Tip: For best results, use a 1-inch grid target and take the photo straight-on.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Impact Offset',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Optional: pick a direction and type the amount',
                ),
                value: _hasOffset,
                onChanged: (v) => setState(() => _hasOffset = v),
              ),
              if (_hasOffset) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _offsetUnit,
                  items: const [
                    DropdownMenuItem(value: 'in', child: Text('Inches')),
                    DropdownMenuItem(value: 'moa', child: Text('MOA')),
                    DropdownMenuItem(value: 'mil', child: Text('Mil')),
                  ],
                  onChanged: (v) => setState(() {
                    _offsetUnit = v ?? 'in';
                  }),
                  decoration: const InputDecoration(labelText: 'Units'),
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Horizontal'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Left'),
                          selected: !_horizontalRight,
                          onSelected: (_) =>
                              setState(() => _horizontalRight = false),
                        ),
                        ChoiceChip(
                          label: const Text('Right'),
                          selected: _horizontalRight,
                          onSelected: (_) =>
                              setState(() => _horizontalRight = true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      textCapitalization: TextCapitalization.none,
                      controller: _hOffsetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount (${_offsetUnit.toUpperCase()})',
                        helperText: 'Type the horizontal amount',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Vertical'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Up'),
                          selected: _verticalUp,
                          onSelected: (_) => setState(() => _verticalUp = true),
                        ),
                        ChoiceChip(
                          label: const Text('Down'),
                          selected: !_verticalUp,
                          onSelected: (_) =>
                              setState(() => _verticalUp = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      textCapitalization: TextCapitalization.none,
                      controller: _vOffsetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount (${_offsetUnit.toUpperCase()})',
                        helperText: 'Type the vertical amount',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final distance = _distance.text.trim();
            final result = _result.text.trim();
            if (distance.isEmpty || result.isEmpty) return;

            double? ox;
            double? oy;

            if (_hasOffset) {
              final hText = _hOffsetCtrl.text.trim();
              final vText = _vOffsetCtrl.text.trim();
              final hAmount = hText.isEmpty ? 0.0 : double.tryParse(hText);
              final vAmount = vText.isEmpty ? 0.0 : double.tryParse(vText);
              if (hAmount == null || vAmount == null) return;
              ox = (_horizontalRight ? 1 : -1) * hAmount.abs();
              oy = (_verticalUp ? 1 : -1) * vAmount.abs();
            } else {
              ox = null;
              oy = null;
            }

            // If Result is Impact OK and offsets were left blank, treat as 0/0.
            if (result.toLowerCase() == 'impact ok' && !_hasOffset) {
              ox = 0;
              oy = 0;
            }

            Navigator.of(context).pop(
              _ColdBoreResult(
                time: _time,
                distance: distance,
                result: result,
                notes: _notes.text,
                offsetX: ox,
                offsetY: oy,
                offsetUnit: _offsetUnit,
                photoBytes: _photoBytes,
              ),
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
              textCapitalization: TextCapitalization.none,
              controller: _c,
              decoration: const InputDecoration(
                labelText: 'Session notes (optional)',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: Use this for anything session-related (conditions, plan, observations, reminders, etc.).',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
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
          textCapitalization: TextCapitalization.none,
          controller: _c,
          decoration: const InputDecoration(labelText: 'Caption (optional)'),
          textInputAction: TextInputAction.done,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
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
          textCapitalization: TextCapitalization.none,
          controller: _c,
          decoration: const InputDecoration(labelText: 'DOPE notes'),
          maxLines: 6,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
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
  final List<String> trustedPartnerIdentifiers;
  final Set<String> initiallySelected;
  final bool initialShareNotesWithMembers;
  final bool initialShareTrainingDopeWithMembers;
  final bool initialShareLocationWithMembers;
  final bool initialSharePhotosWithMembers;
  final bool initialShareShotResultsWithMembers;
  final bool initialShareTimerDataWithMembers;
  final Set<String> initialExternalIdentifiers;

  const _ShareSessionDialog({
    required this.sessionTitle,
    required this.users,
    required this.trustedPartnerIdentifiers,
    required this.initiallySelected,
    required this.initialShareNotesWithMembers,
    required this.initialShareTrainingDopeWithMembers,
    required this.initialShareLocationWithMembers,
    required this.initialSharePhotosWithMembers,
    required this.initialShareShotResultsWithMembers,
    required this.initialShareTimerDataWithMembers,
    this.initialExternalIdentifiers = const <String>{},
  });

  @override
  State<_ShareSessionDialog> createState() => _ShareSessionDialogState();
}

class _NearbySessionShareDialog extends StatelessWidget {
  final AppState state;
  final Future<void> Function(NearbyPeer peer) onSelectPeer;
  final Future<void> Function() onRefresh;

  const _NearbySessionShareDialog({
    required this.state,
    required this.onSelectPeer,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final peers = state.nearbyPeers;
        final status = state.nearbyStatusMessage;
        return AlertDialog(
          title: const Text('Nearby Cold Bore users'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status),
                const SizedBox(height: 8),
                Text(
                  'Your identifier: ${state.activeUserIdentifier ?? 'not set'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (peers.isEmpty)
                  const Text(
                    'No nearby Cold Bore users found yet. Keep both iPhones unlocked, nearby, with Cold Bore open, and Local Network allowed.',
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: peers.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final peer = peers[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.phone_iphone_outlined),
                          title: Text(peer.displayName),
                          subtitle: Text(peer.identifier),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await onSelectPeer(peer);
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await onRefresh();
              },
              child: const Text('Refresh'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}

class _ShareSessionDialogState extends State<_ShareSessionDialog> {
  late final Set<String> _selected;
  late final Set<String> _selectedTrustedPartners;
  late bool _shareNotesWithMembers;
  late bool _shareTrainingDopeWithMembers;
  late bool _shareLocationWithMembers;
  late bool _sharePhotosWithMembers;
  late bool _shareShotResultsWithMembers;
  late bool _shareTimerDataWithMembers;
  late final TextEditingController _externalIdentifiersController;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelected};
    _selectedTrustedPartners = widget.initialExternalIdentifiers
        .where(widget.trustedPartnerIdentifiers.contains)
        .toSet();
    _shareNotesWithMembers = widget.initialShareNotesWithMembers;
    _shareTrainingDopeWithMembers = widget.initialShareTrainingDopeWithMembers;
    _shareLocationWithMembers = widget.initialShareLocationWithMembers;
    _sharePhotosWithMembers = widget.initialSharePhotosWithMembers;
    _shareShotResultsWithMembers = widget.initialShareShotResultsWithMembers;
    _shareTimerDataWithMembers = widget.initialShareTimerDataWithMembers;
    _externalIdentifiersController = TextEditingController(
      text: widget.initialExternalIdentifiers
          .where((id) => !widget.trustedPartnerIdentifiers.contains(id))
          .join(', '),
    );
  }

  @override
  void dispose() {
    _externalIdentifiersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Share "${_cleanText(widget.sessionTitle)}"'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Who should have access?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ...widget.users.map((u) {
              final checked = _selected.contains(u.id);
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: checked,
                title: Text(_displayUserIdentifier(u.identifier)),
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
            }),
            if (widget.trustedPartnerIdentifiers.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                'Trusted partners',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...widget.trustedPartnerIdentifiers.map((identifier) {
                final checked = _selectedTrustedPartners.contains(identifier);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  title: Text(_displayUserIdentifier(identifier)),
                  subtitle: const Text(
                    'Remote sharing works once sync is active for this identifier.',
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedTrustedPartners.add(identifier);
                      } else {
                        _selectedTrustedPartners.remove(identifier);
                      }
                    });
                  },
                );
              }),
            ],
            const SizedBox(height: 6),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _externalIdentifiersController,
              decoration: const InputDecoration(
                labelText: 'Also share with identifier(s)',
                hintText: 'e.g. RANGER1, SPOTTER2',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Use comma-separated identifiers from the other device user profile. Sessions auto-populate when that identifier is registered in the app; otherwise sync starts once they sign in with that identifier.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            const Text(
              'What should members see?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share notes'),
              value: _shareNotesWithMembers,
              onChanged: (v) => setState(() => _shareNotesWithMembers = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share training DOPE'),
              subtitle: const Text(
                'Turn off to keep your training/working DOPE private.',
              ),
              value: _shareTrainingDopeWithMembers,
              onChanged: (v) =>
                  setState(() => _shareTrainingDopeWithMembers = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share location and GPS'),
              value: _shareLocationWithMembers,
              onChanged: (v) => setState(() => _shareLocationWithMembers = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share photos and photo notes'),
              value: _sharePhotosWithMembers,
              onChanged: (v) => setState(() => _sharePhotosWithMembers = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share shot results'),
              value: _shareShotResultsWithMembers,
              onChanged: (v) =>
                  setState(() => _shareShotResultsWithMembers = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share timer data'),
              value: _shareTimerDataWithMembers,
              onChanged: (v) => setState(() => _shareTimerDataWithMembers = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(
            _ShareSessionResult(
              userIds: _selected,
              externalIdentifiers:
                  _externalIdentifiersController.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .map((e) => e.toUpperCase())
                      .toSet()
                    ..addAll(_selectedTrustedPartners),
              shareNotesWithMembers: _shareNotesWithMembers,
              shareTrainingDopeWithMembers: _shareTrainingDopeWithMembers,
              shareLocationWithMembers: _shareLocationWithMembers,
              sharePhotosWithMembers: _sharePhotosWithMembers,
              shareShotResultsWithMembers: _shareShotResultsWithMembers,
              shareTimerDataWithMembers: _shareTimerDataWithMembers,
            ),
          ),
          child: const Text('Share'),
        ),
      ],
    );
  }
}

class _ShareSessionResult {
  final Set<String> userIds;
  final Set<String> externalIdentifiers;
  final bool shareNotesWithMembers;
  final bool shareTrainingDopeWithMembers;
  final bool shareLocationWithMembers;
  final bool sharePhotosWithMembers;
  final bool shareShotResultsWithMembers;
  final bool shareTimerDataWithMembers;

  const _ShareSessionResult({
    required this.userIds,
    required this.externalIdentifiers,
    required this.shareNotesWithMembers,
    required this.shareTrainingDopeWithMembers,
    required this.shareLocationWithMembers,
    required this.sharePhotosWithMembers,
    required this.shareShotResultsWithMembers,
    required this.shareTimerDataWithMembers,
  });
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Caliber is required')));
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
        barrelRoundCount:
            widget.existing?.barrelRoundCount ??
            widget.existing?.manualRoundCount ??
            0,
        barrelInstalledDate: widget.existing?.barrelInstalledDate,
        barrelNotes: widget.existing?.barrelNotes ?? '',
        scopeMake: _scopeMake.text.trim().isEmpty
            ? null
            : _scopeMake.text.trim(),
        scopeModel: _scopeModel.text.trim().isEmpty
            ? null
            : _scopeModel.text.trim(),
        scopeSerial: _scopeSerial.text.trim().isEmpty
            ? null
            : _scopeSerial.text.trim(),
        scopeMount: _scopeMount.text.trim().isEmpty
            ? null
            : _scopeMount.text.trim(),
        scopeNotes: _scopeNotes.text.trim().isEmpty
            ? null
            : _scopeNotes.text.trim(),
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        caliber: caliber,
        notes: _notes.text.trim(),
        dope: _dope.text.trim(),
        dopeEntries: widget.existing?.dopeEntries ?? const [],
        manufacturer: _manufacturer.text.trim().isEmpty
            ? null
            : _manufacturer.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
        serialNumber: _serialNumber.text.trim().isEmpty
            ? null
            : _serialNumber.text.trim(),
        barrelLength: _barrelLength.text.trim().isEmpty
            ? null
            : _barrelLength.text.trim(),
        twistRate: _twistRate.text.trim().isEmpty
            ? null
            : _twistRate.text.trim(),
        purchaseDate: _purchaseDate,
        purchasePrice: _purchasePrice.text.trim().isEmpty
            ? null
            : _purchasePrice.text.trim(),
        purchaseLocation: _purchaseLocation.text.trim().isEmpty
            ? null
            : _purchaseLocation.text.trim(),
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
              textCapitalization: TextCapitalization.none,
              controller: _caliber,
              decoration: const InputDecoration(
                labelText: 'Caliber (ex: .308) *',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _manufacturer,
              decoration: const InputDecoration(labelText: 'Manufacturer *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
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
                  textCapitalization: TextCapitalization.none,
                  controller: _serialNumber,
                  decoration: const InputDecoration(
                    labelText: 'Serial number (optional)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        textCapitalization: TextCapitalization.none,
                        controller: _barrelLength,
                        decoration: const InputDecoration(
                          labelText: 'Barrel length (optional)',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        textCapitalization: TextCapitalization.none,
                        controller: _twistRate,
                        decoration: const InputDecoration(
                          labelText: 'Twist rate (optional)',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _purchaseDate == null
                            ? 'Purchase date (optional)'
                            : 'Purchase date: ${_purchaseDate!.month}/${_purchaseDate!.day}/${_purchaseDate!.year}',
                      ),
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
                  textCapitalization: TextCapitalization.none,
                  controller: _purchasePrice,
                  decoration: const InputDecoration(
                    labelText: 'Purchase price (optional)',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _purchaseLocation,
                  decoration: const InputDecoration(
                    labelText: 'Purchase location (optional)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
              ],
            ),

            const SizedBox(height: 12),

            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Scope'),
              subtitle: Text(
                'Adjustment unit: ${_scopeUnit.name.toUpperCase()}',
              ),
              children: [
                const SizedBox(height: 8),
                DropdownButtonFormField<ScopeUnit>(
                  initialValue: _scopeUnit,
                  decoration: const InputDecoration(
                    labelText: 'Adjustment unit',
                  ),
                  items: ScopeUnit.values
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(u.name.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _scopeUnit = v ?? ScopeUnit.mil),
                ),
                const SizedBox(height: 12),
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _scopeMake,
                  decoration: const InputDecoration(
                    labelText: 'Scope make (optional)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _scopeModel,
                  decoration: const InputDecoration(
                    labelText: 'Scope model (optional)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _scopeSerial,
                  decoration: const InputDecoration(
                    labelText: 'Scope serial (optional)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _scopeMount,
                  decoration: const InputDecoration(
                    labelText: 'Mount/rings (optional)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _scopeNotes,
                  decoration: const InputDecoration(
                    labelText: 'Scope notes (optional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _NewRifleResult {
  final ScopeUnit scopeUnit;
  final int manualRoundCount;
  final int? barrelRoundCount;
  final DateTime? barrelInstalledDate;
  final String barrelNotes;

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
    this.barrelRoundCount,
    this.barrelInstalledDate,
    this.barrelNotes = '',
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
              textCapitalization: TextCapitalization.none,
              controller: _caliber,
              decoration: const InputDecoration(
                labelText: 'Caliber (ex: .308) *',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _bullet,
              decoration: const InputDecoration(
                labelText: 'Bullet (ex: SMK) *',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _grain,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Bullet grain (ex: 175) *',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _bc,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Ballistic coefficient (optional)',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _manufacturer,
              decoration: const InputDecoration(labelText: 'Manufacturer *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _lot,
              decoration: const InputDecoration(
                labelText: 'Lot number (optional)',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
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
                      initialDate:
                          _purchaseDate ??
                          DateTime(now.year, now.month, now.day),
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
              textCapitalization: TextCapitalization.none,
              controller: _purchasePrice,
              decoration: const InputDecoration(
                labelText: 'Purchase price (optional)',
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.none,
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
            final manufacturer = manufacturerRaw.isEmpty
                ? null
                : manufacturerRaw;

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
  return '${dt.month}/${dt.day}/${dt.year}';
}

String _fmtDateTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${_fmtDate(dt)} $hh:$mm';
}

double _distanceStringToYards(String distance) {
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(distance);
  final value = match == null ? 0.0 : double.tryParse(match.group(1)!) ?? 0.0;
  return value <= 0 ? 100.0 : value;
}

double _shotOffsetToMoa(ShotEntry shot, double value) {
  if (shot.offsetUnit == 'moa') return value;
  if (shot.offsetUnit == 'mil') return value * 3.43774677;
  return value * (100.0 / (_distanceStringToYards(shot.distance) * 1.047));
}

double _shotOffsetToInches(ShotEntry shot, double value) {
  if (shot.offsetUnit == 'in') return value;
  final yards = _distanceStringToYards(shot.distance);
  if (shot.offsetUnit == 'mil') return value * (yards / 100.0) * 3.6;
  return value * (yards / 100.0) * 1.047;
}

class DopeManagerScreen extends StatelessWidget {
  final AppState state;
  final Rifle rifle;
  const DopeManagerScreen({
    super.key,
    required this.state,
    required this.rifle,
  });

  @override
  Widget build(BuildContext context) {
    final entries = rifle.dopeEntries;
    return Scaffold(
      appBar: AppBar(title: Text('DOPE • ${rifle.name}')),
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
                id: state.newChildId(),
                distance: res.distance,
                elevation: res.elevation,
                windage: res.windage,
                notes: res.notes,
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
                  title: Text(
                    '${e.distance} • Elev ${e.elevation} • Wind ${e.windage}',
                  ),
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
              textCapitalization: TextCapitalization.none,
              controller: _distance,
              decoration: const InputDecoration(labelText: 'Distance (yd/m)'),
            ),
            const SizedBox(height: 10),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _elev,
              decoration: const InputDecoration(labelText: 'Elevation (dial)'),
            ),
            const SizedBox(height: 10),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _wind,
              decoration: const InputDecoration(
                labelText: 'Windage (e.g., R0.2 / L0.1 / 0)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              textCapitalization: TextCapitalization.none,
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

String _maintenanceDueLabel(MaintenanceDueStatus status) {
  switch (status) {
    case MaintenanceDueStatus.good:
      return 'Good';
    case MaintenanceDueStatus.dueSoon:
      return 'Due soon';
    case MaintenanceDueStatus.overdue:
      return 'Overdue';
  }
}

Color _maintenanceDueColor(BuildContext context, MaintenanceDueStatus status) {
  final cs = Theme.of(context).colorScheme;
  switch (status) {
    case MaintenanceDueStatus.good:
      return Colors.green.shade700;
    case MaintenanceDueStatus.dueSoon:
      return Colors.orange.shade800;
    case MaintenanceDueStatus.overdue:
      return cs.error;
  }
}

String _maintenanceStatusSummary(MaintenanceReminderStatus status) {
  final parts = <String>[];
  if (status.roundsSince != null && status.rule.intervalRounds != null) {
    final roundsPart = status.roundsRemaining == null
        ? '${status.roundsSince} rounds since last ${_maintenanceTaskLabel(status.rule.type).toLowerCase()}'
        : (status.roundsRemaining! <= 0
              ? '${status.roundsSince} rounds since last ${_maintenanceTaskLabel(status.rule.type).toLowerCase()} (${status.roundsRemaining!.abs()} overdue)'
              : '${status.roundsRemaining} rounds remaining');
    parts.add(roundsPart);
  }
  if (status.daysSince != null && status.rule.intervalDays != null) {
    final daysPart = status.daysRemaining == null
        ? '${status.daysSince} days since last ${_maintenanceTaskLabel(status.rule.type).toLowerCase()}'
        : (status.daysRemaining! <= 0
              ? '${status.daysSince} days since last ${_maintenanceTaskLabel(status.rule.type).toLowerCase()} (${status.daysRemaining!.abs()} overdue)'
              : '${status.daysRemaining} days remaining');
    parts.add(daysPart);
  }
  if (parts.isEmpty && status.lastService != null) {
    parts.add('Last completed ${_fmtDate(status.lastService!.date)}');
  }
  return parts.isEmpty ? 'No maintenance history yet.' : parts.join(' • ');
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
        final snapshots = state.maintenanceSnapshots()
          ..sort((a, b) {
            final statusOrder = b.overallStatus.index.compareTo(
              a.overallStatus.index,
            );
            if (statusOrder != 0) return statusOrder;
            return _rifleLabel(a.rifle).compareTo(_rifleLabel(b.rifle));
          });
        final overdueCount = snapshots
            .where(
              (snapshot) =>
                  snapshot.overallStatus == MaintenanceDueStatus.overdue,
            )
            .length;
        final dueSoonCount = snapshots
            .where(
              (snapshot) =>
                  snapshot.overallStatus == MaintenanceDueStatus.dueSoon,
            )
            .length;
        final attention = snapshots
            .where(
              (snapshot) => snapshot.overallStatus != MaintenanceDueStatus.good,
            )
            .toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Maintenance')),
          body: snapshots.isEmpty
              ? const _EmptyState(
                  icon: Icons.build_outlined,
                  title: 'No rifles yet',
                  message:
                      'Add a rifle first to track maintenance and reminders.',
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MaintenanceSummaryCard(
                          label: 'Rifles',
                          value: '${snapshots.length}',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        _MaintenanceSummaryCard(
                          label: 'Overdue',
                          value: '$overdueCount',
                          color: _maintenanceDueColor(
                            context,
                            MaintenanceDueStatus.overdue,
                          ),
                        ),
                        _MaintenanceSummaryCard(
                          label: 'Due soon',
                          value: '$dueSoonCount',
                          color: _maintenanceDueColor(
                            context,
                            MaintenanceDueStatus.dueSoon,
                          ),
                        ),
                      ],
                    ),
                    if (attention.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Needs attention',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              ...attention.take(5).map((snapshot) {
                                final color = _maintenanceDueColor(
                                  context,
                                  snapshot.overallStatus,
                                );
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.warning_amber_outlined,
                                    color: color,
                                  ),
                                  title: Text(_rifleLabel(snapshot.rifle)),
                                  subtitle: Text(
                                    '${snapshot.overdueCount} overdue • ${snapshot.dueSoonCount} due soon',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => RifleServiceLogScreen(
                                          state: state,
                                          rifleId: snapshot.rifle.id,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ...snapshots.map((snapshot) {
                      final color = _maintenanceDueColor(
                        context,
                        snapshot.overallStatus,
                      );
                      final barrelDate =
                          snapshot.rifle.barrelInstalledDate == null
                          ? null
                          : _fmtDate(snapshot.rifle.barrelInstalledDate!);
                      final subtitleParts = <String>[
                        'Total rounds: ${snapshot.totalRounds}',
                        'Current barrel: ${snapshot.barrelRounds}',
                        if (barrelDate != null) 'Barrel since $barrelDate',
                      ];
                      final detail =
                          snapshot.overallStatus == MaintenanceDueStatus.good
                          ? (snapshot.lastService == null
                                ? 'No services logged yet'
                                : 'Last service ${_fmtDate(snapshot.lastService!.date)}')
                          : '${snapshot.overdueCount} overdue • ${snapshot.dueSoonCount} due soon';
                      return Card(
                        child: ListTile(
                          leading: Icon(Icons.build_outlined, color: color),
                          title: Text(_rifleLabel(snapshot.rifle)),
                          subtitle: Text(
                            '${subtitleParts.join(' • ')}\n$detail',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RifleServiceLogScreen(
                                  state: state,
                                  rifleId: snapshot.rifle.id,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ),
        );
      },
    );
  }
}

class _MaintenanceSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MaintenanceSummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class RifleServiceLogScreen extends StatefulWidget {
  final AppState state;
  final String rifleId;
  const RifleServiceLogScreen({
    super.key,
    required this.state,
    required this.rifleId,
  });

  @override
  State<RifleServiceLogScreen> createState() => _RifleServiceLogScreenState();
}

class _RifleServiceLogScreenState extends State<RifleServiceLogScreen> {
  MaintenanceTaskType? _serviceFilter;

  Future<void> _addService({
    MaintenanceTaskType initialTaskType = MaintenanceTaskType.general,
    String? initialServiceLabel,
  }) async {
    if (!await _guardWrite(context)) return;
    final res = await showDialog<RifleServiceEntry>(
      context: context,
      builder: (_) => _AddRifleServiceDialog(
        state: widget.state,
        rifleId: widget.rifleId,
        initialTaskType: initialTaskType,
        initialServiceLabel: initialServiceLabel,
      ),
    );
    if (res == null) return;
    widget.state.addRifleService(rifleId: widget.rifleId, entry: res);
  }

  Future<void> _editReminders() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RifleMaintenanceRulesScreen(
          state: widget.state,
          rifleId: widget.rifleId,
        ),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Maintenance reminder rules updated.')),
    );
  }

  Future<void> _resetBarrelCount() async {
    final rifle = widget.state.rifleById(widget.rifleId);
    if (rifle == null) return;
    final res = await showDialog<_ResetBarrelResult>(
      context: context,
      builder: (_) => _ResetBarrelDialog(rifle: rifle),
    );
    if (res == null) return;
    widget.state.resetRifleBarrelCount(
      rifleId: widget.rifleId,
      installedDate: res.installedDate,
      notes: res.notes,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Current barrel count reset and barrel change logged.'),
      ),
    );
  }

  Future<void> _markReminderDone(MaintenanceReminderStatus status) async {
    if (status.rule.type == MaintenanceTaskType.barrelLife) {
      await _resetBarrelCount();
      return;
    }
    widget.state.logRifleMaintenanceTask(
      rifleId: widget.rifleId,
      taskType: status.rule.type,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_maintenanceTaskLabel(status.rule.type)} logged.'),
      ),
    );
  }

  Future<void> _deleteService(RifleServiceEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete service entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.state.deleteRifleService(
        rifleId: widget.rifleId,
        serviceId: entry.id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service log'),
        actions: [
          IconButton(
            tooltip: 'Reminder rules',
            onPressed: _editReminders,
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          IconButton(
            tooltip: 'Reset barrel count',
            onPressed: _resetBarrelCount,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addService,
        child: const Icon(Icons.add),
      ),
      body: AnimatedBuilder(
        animation: widget.state,
        builder: (context, _) {
          final rifle = widget.state.rifleById(widget.rifleId);

          if (rifle == null) {
            return const Center(child: Text('Rifle not found.'));
          }

          final snapshot = widget.state.maintenanceSnapshotForRifle(
            widget.rifleId,
          );
          final services = [...rifle.services]
            ..sort((a, b) => b.date.compareTo(a.date));
          final filteredServices = _serviceFilter == null
              ? services
              : services
                    .where((entry) => entry.taskType == _serviceFilter)
                    .toList();
          final presentServiceTypes =
              <MaintenanceTaskType>{
                for (final service in services) service.taskType,
              }.toList()..sort(
                (a, b) => _maintenanceTaskLabel(
                  a,
                ).compareTo(_maintenanceTaskLabel(b)),
              );
          final overallColor = _maintenanceDueColor(
            context,
            snapshot.overallStatus,
          );
          final rifleModelLabel =
              '${(rifle.manufacturer ?? '').trim()} ${(rifle.model ?? '').trim()}'
                  .trim();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${rifle.caliber} • $rifleModelLabel',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: overallColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _maintenanceDueLabel(snapshot.overallStatus),
                              style: TextStyle(
                                color: overallColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Total rounds: ${snapshot.totalRounds}'),
                      Text('Current barrel rounds: ${snapshot.barrelRounds}'),
                      if (rifle.barrelInstalledDate != null)
                        Text(
                          'Current barrel installed: ${_fmtDate(rifle.barrelInstalledDate!)}',
                        ),
                      if (rifle.barrelNotes.trim().isNotEmpty)
                        Text('Barrel notes: ${rifle.barrelNotes.trim()}'),
                      if (snapshot.lastService != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Last service: ${snapshot.lastService!.service} on ${_fmtDate(snapshot.lastService!.date)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (snapshot.statuses.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Maintenance reminders',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No reminder rules are enabled for this rifle.',
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _editReminders,
                          child: const Text('Edit reminder rules'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Text(
                  'Active reminders',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...snapshot.statuses.map((status) {
                  final statusColor = _maintenanceDueColor(
                    context,
                    status.status,
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _maintenanceTaskIcon(status.rule.type),
                                color: statusColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _maintenanceTaskLabel(status.rule.type),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                _maintenanceDueLabel(status.status),
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(_maintenanceStatusSummary(status)),
                          if (status.rule.notes.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(status.rule.notes.trim()),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonal(
                                onPressed: () => _markReminderDone(status),
                                child: Text(
                                  status.rule.type ==
                                          MaintenanceTaskType.barrelLife
                                      ? 'Replace barrel'
                                      : 'Mark done',
                                ),
                              ),
                              if (status.rule.type !=
                                  MaintenanceTaskType.barrelLife)
                                TextButton(
                                  onPressed: () => _addService(
                                    initialTaskType: status.rule.type,
                                    initialServiceLabel: _maintenanceTaskLabel(
                                      status.rule.type,
                                    ),
                                  ),
                                  child: const Text('Log with notes'),
                                ),
                              TextButton(
                                onPressed: _editReminders,
                                child: const Text('Edit rules'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<MaintenanceTaskType?>(
                initialValue: _serviceFilter,
                decoration: const InputDecoration(labelText: 'History filter'),
                items: [
                  const DropdownMenuItem<MaintenanceTaskType?>(
                    value: null,
                    child: Text('All service types'),
                  ),
                  ...presentServiceTypes.map(
                    (type) => DropdownMenuItem<MaintenanceTaskType?>(
                      value: type,
                      child: Text(_maintenanceTaskLabel(type)),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _serviceFilter = value),
              ),
              const SizedBox(height: 12),
              if (filteredServices.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No service entries match the current filter.'),
                  ),
                )
              else
                ...filteredServices.map(
                  (service) => Card(
                    child: ListTile(
                      leading: Icon(_maintenanceTaskIcon(service.taskType)),
                      title: Text(service.service),
                      subtitle: Text(
                        '${_fmtDate(service.date)} • ${service.roundsAtService} total rds${service.notes.trim().isEmpty ? '' : ' • ${service.notes.trim()}'}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteService(service),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AddRifleServiceDialog extends StatefulWidget {
  final AppState state;
  final String rifleId;
  final MaintenanceTaskType initialTaskType;
  final String? initialServiceLabel;

  const _AddRifleServiceDialog({
    required this.state,
    required this.rifleId,
    this.initialTaskType = MaintenanceTaskType.general,
    this.initialServiceLabel,
  });

  @override
  State<_AddRifleServiceDialog> createState() => _AddRifleServiceDialogState();
}

class _AddRifleServiceDialogState extends State<_AddRifleServiceDialog> {
  final _serviceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _useCurrentRounds = true;
  final _roundsCtrl = TextEditingController();
  late MaintenanceTaskType _taskType;

  @override
  void initState() {
    super.initState();
    _taskType = widget.initialTaskType;
    if (_taskType != MaintenanceTaskType.general) {
      _serviceCtrl.text =
          widget.initialServiceLabel ?? _maintenanceTaskLabel(_taskType);
    }
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
      title: const Text('Log maintenance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<MaintenanceTaskType>(
              initialValue: _taskType,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(
                  value: MaintenanceTaskType.general,
                  child: Text('General service'),
                ),
                DropdownMenuItem(
                  value: MaintenanceTaskType.cleaning,
                  child: Text('Cleaning'),
                ),
                DropdownMenuItem(
                  value: MaintenanceTaskType.deepCleaning,
                  child: Text('Deep clean'),
                ),
                DropdownMenuItem(
                  value: MaintenanceTaskType.torqueCheck,
                  child: Text('Torque check'),
                ),
                DropdownMenuItem(
                  value: MaintenanceTaskType.zeroConfirm,
                  child: Text('Zero confirm'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _taskType = value;
                  if (_taskType != MaintenanceTaskType.general) {
                    _serviceCtrl.text = _maintenanceTaskLabel(_taskType);
                  }
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _serviceCtrl,
              decoration: const InputDecoration(labelText: 'Service'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              textCapitalization: TextCapitalization.none,
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
              title: const Text('Use current rifle total rounds'),
              subtitle: Text(
                _useCurrentRounds ? '$currentRounds rds' : 'Enter manually',
              ),
              value: _useCurrentRounds,
              onChanged: (v) => setState(() => _useCurrentRounds = v),
            ),
            if (!_useCurrentRounds)
              TextField(
                textCapitalization: TextCapitalization.none,
                controller: _roundsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Rounds at service',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final service = _serviceCtrl.text.trim().isEmpty
                ? _maintenanceTaskLabel(_taskType)
                : _serviceCtrl.text.trim();
            if (service.isEmpty) return;

            final rounds = _useCurrentRounds
                ? currentRounds
                : (int.tryParse(_roundsCtrl.text.trim()) ?? currentRounds);

            final entry = RifleServiceEntry(
              id: widget.state.newChildId(),
              service: service,
              date: _date,
              roundsAtService: rounds,
              notes: _notesCtrl.text.trim(),
              taskType: _taskType,
            );

            Navigator.pop(context, entry);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class RifleMaintenanceRulesScreen extends StatefulWidget {
  final AppState state;
  final String rifleId;

  const RifleMaintenanceRulesScreen({
    super.key,
    required this.state,
    required this.rifleId,
  });

  @override
  State<RifleMaintenanceRulesScreen> createState() =>
      _RifleMaintenanceRulesScreenState();
}

class _RifleMaintenanceRulesScreenState
    extends State<RifleMaintenanceRulesScreen> {
  final Map<MaintenanceTaskType, bool> _enabled = <MaintenanceTaskType, bool>{};
  final Map<MaintenanceTaskType, TextEditingController> _roundCtrls =
      <MaintenanceTaskType, TextEditingController>{};
  final Map<MaintenanceTaskType, TextEditingController> _dayCtrls =
      <MaintenanceTaskType, TextEditingController>{};
  final Map<MaintenanceTaskType, TextEditingController> _notesCtrls =
      <MaintenanceTaskType, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    final rules = widget.state.maintenanceRulesForRifle(widget.rifleId);
    for (final rule in rules) {
      _enabled[rule.type] = rule.enabled;
      _roundCtrls[rule.type] = TextEditingController(
        text: rule.intervalRounds?.toString() ?? '',
      );
      _dayCtrls[rule.type] = TextEditingController(
        text: rule.intervalDays?.toString() ?? '',
      );
      _notesCtrls[rule.type] = TextEditingController(text: rule.notes);
    }
  }

  @override
  void dispose() {
    for (final controller in _roundCtrls.values) {
      controller.dispose();
    }
    for (final controller in _dayCtrls.values) {
      controller.dispose();
    }
    for (final controller in _notesCtrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _parseOptionalInt(String raw) {
    final value = int.tryParse(raw.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  Future<void> _save() async {
    final rules = MaintenanceTaskType.values
        .where(_isConfigurableMaintenanceTask)
        .map((type) {
          return MaintenanceReminderRule(
            type: type,
            enabled: _enabled[type] == true,
            intervalRounds: _maintenanceTaskSupportsRounds(type)
                ? _parseOptionalInt(_roundCtrls[type]?.text ?? '')
                : null,
            intervalDays: _maintenanceTaskSupportsDays(type)
                ? _parseOptionalInt(_dayCtrls[type]?.text ?? '')
                : null,
            notes: (_notesCtrls[type]?.text ?? '').trim(),
          );
        })
        .toList();

    widget.state.updateRifleMaintenanceRules(
      rifleId: widget.rifleId,
      rules: rules,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final rifle = widget.state.rifleById(widget.rifleId);
    if (rifle == null) {
      return const Scaffold(body: Center(child: Text('Rifle not found.')));
    }
    final rifleModelLabel =
        '${(rifle.manufacturer ?? '').trim()} ${(rifle.model ?? '').trim()}'
            .trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder rules'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Set round-based or date-based reminders for $rifleModelLabel.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...MaintenanceTaskType.values
              .where(_isConfigurableMaintenanceTask)
              .map(
                (type) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(_maintenanceTaskIcon(type)),
                          title: Text(_maintenanceTaskLabel(type)),
                          value: _enabled[type] == true,
                          onChanged: (value) =>
                              setState(() => _enabled[type] = value),
                        ),
                        if (_enabled[type] == true) ...[
                          if (_maintenanceTaskSupportsRounds(type) ||
                              _maintenanceTaskSupportsDays(type))
                            Row(
                              children: [
                                if (_maintenanceTaskSupportsRounds(type))
                                  Expanded(
                                    child: TextField(
                                      textCapitalization:
                                          TextCapitalization.none,
                                      controller: _roundCtrls[type],
                                      decoration: const InputDecoration(
                                        labelText: 'Rounds interval',
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                    ),
                                  ),
                                if (_maintenanceTaskSupportsRounds(type) &&
                                    _maintenanceTaskSupportsDays(type))
                                  const SizedBox(width: 12),
                                if (_maintenanceTaskSupportsDays(type))
                                  Expanded(
                                    child: TextField(
                                      textCapitalization:
                                          TextCapitalization.none,
                                      controller: _dayCtrls[type],
                                      decoration: const InputDecoration(
                                        labelText: 'Days interval',
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          TextField(
                            textCapitalization: TextCapitalization.none,
                            controller: _notesCtrls[type],
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Notes (optional)',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ResetBarrelResult {
  final DateTime installedDate;
  final String notes;

  const _ResetBarrelResult({required this.installedDate, required this.notes});
}

class _ResetBarrelDialog extends StatefulWidget {
  final Rifle rifle;

  const _ResetBarrelDialog({required this.rifle});

  @override
  State<_ResetBarrelDialog> createState() => _ResetBarrelDialogState();
}

class _ResetBarrelDialogState extends State<_ResetBarrelDialog> {
  late DateTime _installedDate;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _installedDate = widget.rifle.barrelInstalledDate ?? DateTime.now();
    _notesCtrl = TextEditingController(text: widget.rifle.barrelNotes);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset barrel count'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use this when a new barrel is installed. Lifetime rounds stay unchanged.',
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Barrel installed'),
              subtitle: Text(_fmtDate(_installedDate)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _installedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _installedDate = picked);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              textCapitalization: TextCapitalization.none,
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Barrel notes (optional)',
              ),
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
              _ResetBarrelResult(
                installedDate: _installedDate,
                notes: _notesCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Reset'),
        ),
      ],
    );
  }
}

class _BackupScreen extends StatelessWidget {
  final AppState state;
  const _BackupScreen({required this.state});

  Rect _shareOriginRect(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const Rect.fromLTWH(0, 0, 1, 1);
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Future<String?> _pickJsonFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final bytes = res.files.single.bytes;
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  Future<void> _exportBackupFile(BuildContext context) async {
    try {
      final ts = DateTime.now();
      final fname =
          'cold_bore_backup_${ts.year.toString().padLeft(4, '0')}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}.json';
      final json = state.exportBackupJson();

      // Web: download directly (no sandboxed filesystem)
      if (kIsWeb) {
        _downloadTextFileWeb(fname, json, mimeType: 'application/json');
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Backup downloaded.')));
        return;
      }

      // Mobile/Desktop: share in-memory JSON file payload.
      final bytes = Uint8List.fromList(utf8.encode(json));
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'application/json', name: fname)],
        text: 'Cold Bore backup',
        sharePositionOrigin: _shareOriginRect(context),
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup file ready to save/share.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restoreBackupFile(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This will replace the current app data on this device with the backup file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    String? jsonText;
    if (kIsWeb) {
      jsonText = await _pickWebJsonFile();
    } else {
      jsonText = await _pickJsonFile();
    }

    if (jsonText == null || jsonText.trim().isEmpty) {
      final manual = await showDialog<_ImportBackupResult>(
        context: context,
        builder: (_) => const _ImportBackupDialog(),
      );
      jsonText = manual?.jsonText;
    }

    if (jsonText == null || jsonText.trim().isEmpty) return;

    try {
      state.importBackupJson(jsonText, replaceExisting: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restore complete.')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore failed. Invalid backup JSON.')),
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
              title: const Text('Create Backup File (JSON)'),
              subtitle: const Text(
                'Saves all app data to one shareable backup file.',
              ),
              onTap: () => _exportBackupFile(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Import or Restore JSON File'),
              subtitle: const Text(
                'Imports a shared session JSON or replaces this device data with a full backup file.',
              ),
              onTap: () => _restoreBackupFile(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportBackupResult {
  final String jsonText;
  const _ImportBackupResult({required this.jsonText});
}

class _ImportBackupDialog extends StatefulWidget {
  const _ImportBackupDialog();

  @override
  State<_ImportBackupDialog> createState() => _ImportBackupDialogState();
}

class _ImportBackupDialogState extends State<_ImportBackupDialog> {
  final _ctrl = TextEditingController();

  Future<void> _browseJson() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    final bytes = res.files.single.bytes;
    if (bytes == null) return;

    setState(() {
      _ctrl.text = utf8.decode(bytes);
    });
  }

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
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _browseJson,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              textCapitalization: TextCapitalization.none,
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final t = _ctrl.text.trim();
            if (t.isEmpty) return;
            Navigator.of(context).pop(_ImportBackupResult(jsonText: t));
          },
          child: const Text('Import'),
        ),
      ],
    );
  }
}
