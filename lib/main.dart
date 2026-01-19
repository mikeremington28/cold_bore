// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:share_plus/share_plus.dart';
import 'package:file_selector/file_selector.dart';

import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RanchHandApp());
}

class RanchHandApp extends StatefulWidget {
  const RanchHandApp({super.key});

  @override
  State<RanchHandApp> createState() => _RanchHandAppState();
}

class _RanchHandAppState extends State<RanchHandApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _initThemeMode();
  }

  Future<void> _initThemeMode() async {
    final mode = await Storage.loadThemeMode();
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  void _setThemeMode(ThemeMode mode) {
    unawaited(Storage.saveThemeMode(mode));
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ranch Hand',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: _themeMode,
      home: DashboardScreen(
        currentThemeMode: _themeMode,
        onThemeChanged: _setThemeMode,
      ),
    );
  }
}
/* ============================
   Models
============================ */

class Equipment {
  final String id;
  String name;
  String type;

  // Optional details
  String? vin;
  String? serialNumber;
  DateTime? purchaseDate;

  // More optional details
  String? location;
  String? manufacturer;
  String? model;
  String? vendor;
  double? purchasePrice;
  DateTime? warrantyUntil;

  String notes;
  final DateTime createdAt;
  Map<String, String> specs;

  Equipment({
    required this.id,
    required this.name,
    required this.type,
    this.vin,
    this.serialNumber,
    this.purchaseDate,
    this.location,
    this.manufacturer,
    this.model,
    this.vendor,
    this.purchasePrice,
    this.warrantyUntil,
    required this.notes,
    required this.createdAt,
    Map<String, String>? specs,
  }) : specs = specs ?? {};

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'vin': vin,
        'serialNumber': serialNumber,
        'purchaseDate': purchaseDate?.toIso8601String(),
        'location': location,
        'manufacturer': manufacturer,
        'model': model,
        'vendor': vendor,
        'purchasePrice': purchasePrice,
        'warrantyUntil': warrantyUntil?.toIso8601String(),
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'specs': specs,
      };

  static Equipment fromMap(Map<String, dynamic> map) {
    final specsRaw = map['specs'];
    Map<String, String> specs = {};
    if (specsRaw is Map) {
      specs =
          specsRaw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
    }

    return Equipment(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      vin: (map['vin'] ?? '').toString().trim().isEmpty
          ? null
          : (map['vin'] ?? '').toString(),
      serialNumber: (map['serialNumber'] ?? '').toString().trim().isEmpty
          ? null
          : (map['serialNumber'] ?? '').toString(),
      purchaseDate: DateTime.tryParse((map['purchaseDate'] ?? '').toString()),
      location: (map['location'] ?? '').toString().trim().isEmpty ? null : (map['location'] ?? '').toString(),
      manufacturer: (map['manufacturer'] ?? '').toString().trim().isEmpty ? null : (map['manufacturer'] ?? '').toString(),
      model: (map['model'] ?? '').toString().trim().isEmpty ? null : (map['model'] ?? '').toString(),
      vendor: (map['vendor'] ?? '').toString().trim().isEmpty ? null : (map['vendor'] ?? '').toString(),
      purchasePrice: (map['purchasePrice'] is num)
          ? (map['purchasePrice'] as num).toDouble()
          : double.tryParse((map['purchasePrice'] ?? '').toString()),
      warrantyUntil: DateTime.tryParse((map['warrantyUntil'] ?? '').toString()),
      notes: (map['notes'] ?? '').toString(),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      specs: specs,
    );
  }
}

class MaintenanceRecord {
  final String id;
  final String equipmentId;
  final String equipmentName;
  final String serviceType;
  final DateTime? serviceDate;
  final int? hours;
  final int? mileage;
  final String notes;

  // Optional "next due" reminders
  final DateTime? nextDueDate;
  final int? nextDueHours;
  final int? nextDueMileage;

  MaintenanceRecord({
    required this.id,
    required this.equipmentId,
    required this.equipmentName,
    required this.serviceType,
    this.serviceDate,
    required this.hours,
    required this.mileage,
    required this.notes,
    this.nextDueDate,
    this.nextDueHours,
    this.nextDueMileage,
  });


  bool get hasNextDue =>
      nextDueDate != null || nextDueHours != null || nextDueMileage != null;

  bool get hasCompleted => serviceDate != null;
  Map<String, dynamic> toMap() => {
        'id': id,
        'equipmentId': equipmentId,
        'equipmentName': equipmentName,
        'serviceType': serviceType,
        'serviceDate': serviceDate?.toIso8601String(),
        'hours': hours,
        'mileage': mileage,
        'notes': notes,
        'nextDueDate': nextDueDate?.toIso8601String(),
        'nextDueHours': nextDueHours,
        'nextDueMileage': nextDueMileage,
      };

  static MaintenanceRecord fromMap(Map<String, dynamic> map) {
    return MaintenanceRecord(
      id: (map['id'] ?? '').toString(),
      equipmentId: (map['equipmentId'] ?? '').toString(),
      equipmentName: (map['equipmentName'] ?? '').toString(),
      serviceType: (map['serviceType'] ?? '').toString(),
      serviceDate: (() {
        final raw = (map['serviceDate'] ?? '').toString().trim();
        if (raw.isEmpty) return null;
        return DateTime.tryParse(raw);
      })(),
      hours: map['hours'] is int
          ? map['hours'] as int
          : int.tryParse((map['hours'] ?? '').toString()),
      mileage: map['mileage'] is int
          ? map['mileage'] as int
          : int.tryParse((map['mileage'] ?? '').toString()),
      notes: (map['notes'] ?? '').toString(),
      nextDueDate: DateTime.tryParse((map['nextDueDate'] ?? '').toString()),
      nextDueHours: (map['nextDueHours'] is num)
          ? (map['nextDueHours'] as num).toInt()
          : int.tryParse((map['nextDueHours'] ?? '').toString()),
      nextDueMileage: (map['nextDueMileage'] is num)
          ? (map['nextDueMileage'] as num).toInt()
          : int.tryParse((map['nextDueMileage'] ?? '').toString()),
    );
  }
}


class TrendPrediction {
  final int? typicalIntervalDays; // null if not enough data
  final DateTime? nextDue;
  final String confidence; // "High" | "Medium" | "Low" | "None"

  const TrendPrediction({
    required this.typicalIntervalDays,
    required this.nextDue,
    required this.confidence,
  });
}

enum _EquipmentFilter { all, dueSoon, overdue }

TrendPrediction predictNextDueFromDates(
  List<DateTime> serviceDates, {
  int fallbackIntervalDays = 60,
  int minRecordsForTrend = 3,
}) {
  if (serviceDates.isEmpty) {
    return const TrendPrediction(
      typicalIntervalDays: null,
      nextDue: null,
      confidence: "None",
    );
  }

  final dates = [...serviceDates]..sort((a, b) => a.compareTo(b));

  if (dates.length < minRecordsForTrend) {
    final last = dates.last;
    return TrendPrediction(
      typicalIntervalDays: fallbackIntervalDays,
      nextDue: last.add(Duration(days: fallbackIntervalDays)),
      confidence: "Low",
    );
  }

  final gaps = <int>[];
  for (int i = 1; i < dates.length; i++) {
    final gap = dates[i].difference(dates[i - 1]).inDays;
    if (gap > 0) gaps.add(gap);
  }

  if (gaps.length < 2) {
    final last = dates.last;
    return TrendPrediction(
      typicalIntervalDays: fallbackIntervalDays,
      nextDue: last.add(Duration(days: fallbackIntervalDays)),
      confidence: "Low",
    );
  }

  gaps.sort();
  int median(List<int> xs) => xs[xs.length ~/ 2];
  final typical = median(gaps);

  final within10pct = gaps.where((g) => (g - typical).abs() <= (typical * 0.10)).length;
  final ratio = within10pct / gaps.length;

  final confidence = (gaps.length >= 6 && ratio >= 0.6)
      ? "High"
      : (gaps.length >= 4 && ratio >= 0.4)
          ? "Medium"
          : "Low";

  final last = dates.last;
  return TrendPrediction(
    typicalIntervalDays: typical,
    nextDue: last.add(Duration(days: typical)),
    confidence: confidence,
  );
}

/* ============================
   Storage
============================ */

class Storage {
  static const _kEquipmentListKey = 'equipmentListV2';
  static const _kMaintenanceListKey = 'maintenanceListV2';
  static const _kThemeModeKey = 'themeModeV1';
  static const _kMaintenanceRemindersEnabledKey = 'maintenanceRemindersEnabledV1';
  static const _kBackupRemindersEnabledKey = 'backupRemindersEnabledV1';
  static const _kLastBackupAtKey = 'lastBackupAtV1';


  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemeModeKey) ?? 'system';
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await prefs.setString(_kThemeModeKey, value);
  }

  static Future<bool> loadMaintenanceRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMaintenanceRemindersEnabledKey) ?? false;
  }

  static Future<void> saveMaintenanceRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMaintenanceRemindersEnabledKey, enabled);
  }

  static Future<bool> loadBackupRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBackupRemindersEnabledKey) ?? true;
  }

  static Future<void> saveBackupRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBackupRemindersEnabledKey, enabled);
  }

  static Future<DateTime?> loadLastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastBackupAtKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> saveLastBackupAt(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackupAtKey, when.toIso8601String());
  }


  static Future<List<Equipment>> loadEquipment() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kEquipmentListKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) =>
              Equipment.fromMap(m.map((k, v) => MapEntry(k.toString(), v))))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveEquipment(List<Equipment> list) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = list.map((e) => e.toMap()).toList();
    await prefs.setString(_kEquipmentListKey, jsonEncode(payload));
  }

  static Future<void> upsertEquipment(Equipment updated) async {
    final list = await loadEquipment();
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx == -1) {
      list.insert(0, updated);
    } else {
      list[idx] = updated;
    }
    await saveEquipment(list);
  }

  static Future<List<MaintenanceRecord>> loadMaintenance() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMaintenanceListKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => MaintenanceRecord.fromMap(
              m.map((k, v) => MapEntry(k.toString(), v))))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMaintenance(List<MaintenanceRecord> list) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = list.map((r) => r.toMap()).toList();
    await prefs.setString(_kMaintenanceListKey, jsonEncode(payload));
  }

  // ===== Backup export/import =====

  static Future<String> exportBackupJson() async {
    final equipment = await loadEquipment();
    final maintenance = await loadMaintenance();

    final payload = {
      'schema': 'ranch_hand_backup_v1',
      'exportedAt': DateTime.now().toIso8601String(),
      'equipment': equipment.map((e) => e.toMap()).toList(),
      'maintenance': maintenance.map((m) => m.toMap()).toList(),
    };

    return jsonEncode(payload);
  }

  static Future<void> importBackupJson(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) throw Exception('Invalid backup file.');

    final schema = (decoded['schema'] ?? '').toString();
    if (schema != 'ranch_hand_backup_v1') {
      throw Exception('Unsupported backup format.');
    }

    final eqRaw = decoded['equipment'];
    final mtRaw = decoded['maintenance'];

    final equipment = (eqRaw is List)
        ? eqRaw
            .whereType<Map>()
            .map((m) =>
                Equipment.fromMap(m.map((k, v) => MapEntry(k.toString(), v))))
            .toList()
        : <Equipment>[];

    final maintenance = (mtRaw is List)
        ? mtRaw
            .whereType<Map>()
            .map((m) => MaintenanceRecord.fromMap(
                m.map((k, v) => MapEntry(k.toString(), v))))
            .toList()
        : <MaintenanceRecord>[];

    await saveEquipment(equipment);
    await saveMaintenance(maintenance);
  }
}

/* ============================
   Helpers
============================ */

String fmtDateMDY(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final yyyy = d.year.toString();
  return '$mm/$dd/$yyyy';
}

String _normalizeText(String s) => s.replaceAll('\r', '\n');

Map<String, String> _extractSpecSuggestionsFromOcr(String raw) {
  final text = raw.toLowerCase();

  // likely part numbers / codes
  final codeRegex = RegExp(r'\b[a-z0-9\-]{5,}\b', caseSensitive: false);
  final codes = codeRegex
      .allMatches(raw)
      .map((m) => raw.substring(m.start, m.end).trim())
      .where(
          (c) => RegExp(r'[a-zA-Z]').hasMatch(c) && RegExp(r'\d').hasMatch(c))
      .toSet()
      .toList();

  String? pickCode() => codes.isNotEmpty ? codes.first : null;

  // tire patterns
  final tire1 = RegExp(r'\b\d{3}\/\d{2}R\d{2}\b', caseSensitive: false)
      .firstMatch(raw)
      ?.group(0);
  final tire2 = RegExp(r'\b\d{2}x\d{2}(\.\d+)?-\d{2}\b', caseSensitive: false)
      .firstMatch(raw)
      ?.group(0);

  final cca = RegExp(r'\b(\d{3,4})\s*CCA\b', caseSensitive: false)
      .firstMatch(raw)
      ?.group(1);

  final Map<String, String> out = {};

  if (text.contains('oil filter')) out['Oil filter #'] = pickCode() ?? '';
  if (text.contains('air filter')) out['Air filter #'] = pickCode() ?? '';
  if (text.contains('fuel filter')) out['Fuel filter #'] = pickCode() ?? '';
  if (text.contains('hydraulic filter')) {
    out['Hydraulic filter #'] = pickCode() ?? '';
  }
  if (text.contains('belt')) out['Belt'] = pickCode() ?? '';
  if (text.contains('spark') && text.contains('plug')) {
    out['Spark plug'] = pickCode() ?? '';
  }

  if (text.contains('battery')) {
    out['Battery'] = [
      if (cca != null) '$cca CCA',
      if (cca == null) (pickCode() ?? ''),
    ].where((s) => s.trim().isNotEmpty).join(' • ');
  }

  if (text.contains('hydraulic') && text.contains('fluid')) {
    out['Hydraulic fluid type'] = '';
  }
  if (text.contains('coolant') || text.contains('antifreeze')) {
    out['Coolant type'] = '';
  }
  if (text.contains('oil') &&
      (text.contains('sae') || text.contains('5w') || text.contains('10w'))) {
    out['Oil type'] = '';
  }

  if (tire1 != null) out['Tire size'] = tire1;
  if (tire2 != null && (out['Tire size'] ?? '').isEmpty) out['Tire size'] = tire2;

  if (out.isEmpty && codes.isNotEmpty) {
    out['Notes'] = 'Scanned code(s): ${codes.take(3).join(', ')}';
  }

  return out;
}

/* ============================
   Dashboard
============================ */

class DashboardScreen extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  const DashboardScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}
class _DashboardScreenState extends State<DashboardScreen> {
  static const int _freeEquipmentLimit = 3;

  // ---- Pro subscription / IAP ----
  static const String _kYearlyProductId = 'ranchhand_pro_yearly';
  static const String _kPrivacyUrl =
      'https://mikeremington28.github.io/ranch-hand-privacy/';
  static const String _kTermsUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _proEnabled = false;
  bool get _isPro => _proEnabled;

  bool _storeAvailable = false;
  bool _iapLoading = true;
  bool _purchaseInProgress = false;
  ProductDetails? _yearlyProduct;
  String? _iapError;

  static const String _kPrefsProKey = 'ranchhand_pro_enabled';

  Future<void> _loadProFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_kPrefsProKey) ?? false;
    if (!mounted) return;
    setState(() => _proEnabled = v);
  }

  Future<void> _setProFlag(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsProKey, v);
    if (!mounted) return;
    setState(() => _proEnabled = v);
  }

  Future<void> _initIap() async {
    await _loadProFlag();

    bool available = false;
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      available = false;
    }

    if (!mounted) return;
    setState(() {
      _storeAvailable = available;
      _iapLoading = true;
      _iapError = null;
      _yearlyProduct = null;
    });

    if (!available) {
      if (!mounted) return;
      setState(() {
        _iapLoading = false;
        _iapError =
            'Store is unavailable. Please check your internet connection and try again.';
      });
      return;
    }

    try {
      final response = await _iap.queryProductDetails({_kYearlyProductId});
      if (!mounted) return;

      final product = response.productDetails
          .where((p) => p.id == _kYearlyProductId)
          .cast<ProductDetails?>()
          .firstWhere((p) => p != null, orElse: () => null);

      setState(() {
        _yearlyProduct = product;
        _iapLoading = false;
        _iapError = response.error != null
            ? (response.error!.message)
            : (product == null
                ? 'Subscription is not available right now.'
                : null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _iapLoading = false;
        _iapError = 'Unable to load subscription: $e';
      });
    }
  }

  void _listenToPurchases() {
    _purchaseSub?.cancel();
    _purchaseSub = _iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        if (p.status == PurchaseStatus.purchased ||
            p.status == PurchaseStatus.restored) {
          await _setProFlag(true);
        }

        if (p.status == PurchaseStatus.error) {
          if (!mounted) continue;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(p.error?.message ?? 'Purchase failed.')),
          );
        }

        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      }

      if (mounted) setState(() => _purchaseInProgress = false);
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _purchaseInProgress = false;
        _iapError = 'Purchase listener error: $e';
      });
    });
  }

  Future<void> _buyYearly() async {
    // Always give visible feedback (Apple rejects silent failures).
    if (_iapLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading subscription… please try again.')),
      );
      return;
    }
    if (!_storeAvailable) {
      await _showSimpleError(
        title: 'Store unavailable',
        message: 'In‑app purchases are not available on this device right now.',
      );
      return;
    }
    if (_yearlyProduct == null) {
      await _showSimpleError(
        title: 'Subscription unavailable',
        message: _iapError ??
            'The subscription could not be loaded. Please try again later.',
      );
      return;
    }

    setState(() => _purchaseInProgress = true);

    // Safety timeout so the UI never looks “stuck” in review.
    final timeout = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (_purchaseInProgress) {
        setState(() => _purchaseInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Purchase did not start. Please try again. If this continues, check your App Store connection.',
            ),
          ),
        );
      }
    });

    try {
      final param = PurchaseParam(productDetails: _yearlyProduct!);
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchaseInProgress = false);
      await _showSimpleError(
        title: 'Purchase failed',
        message: 'Unable to start the purchase: $e',
      );
    } finally {
      timeout.cancel();
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _purchaseInProgress = true);
    try {
      await _iap.restorePurchases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restoring purchases…')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchaseInProgress = false);
      await _showSimpleError(
        title: 'Restore failed',
        message: 'Unable to restore purchases: $e',
      );
    }
  }

  Future<void> _showSimpleError({required String title, required String message}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open link: $url')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open link: $url')),
      );
    }
  }

  Future<void> _showUpgradeDialog() async {
    final price = _yearlyProduct?.price ?? '\$9.99';
    final upgradeEnabled = !_iapLoading && _yearlyProduct != null && !_purchaseInProgress;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ranch Hand Pro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yearly Subscription: $price / year'),
            const SizedBox(height: 8),
            const Text(
              'Auto-renewable subscription. Cancel anytime in your Apple ID settings.',
            ),
            const SizedBox(height: 12),
            if (_iapLoading)
              const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Expanded(child: Text('Loading subscription…')),
                ],
              ),
            if (!_iapLoading && _iapError != null)
              Text(_iapError!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => _openUrl(_kPrivacyUrl),
                  child: const Text('Privacy Policy'),
                ),
                TextButton(
                  onPressed: () => _openUrl(_kTermsUrl),
                  child: const Text('Terms (EULA)'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _purchaseInProgress ? null : () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: _purchaseInProgress ? null : _restorePurchases,
            child: const Text('Restore'),
          ),
          ElevatedButton(
            onPressed: upgradeEnabled
                ? () async {
                    Navigator.of(ctx).pop();
                    await _buyYearly();
                  }
                : null,
            child: _purchaseInProgress
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  bool _loading = true;
  final List<Equipment> _equipment = [];
  final List<MaintenanceRecord> _maintenance = [];

  bool _maintenanceRemindersEnabled = false;
  bool _backupRemindersEnabled = true;
  DateTime? _lastBackupAt;
  _EquipmentFilter _filter = _EquipmentFilter.all;

  @override
  void initState() {
    super.initState();
    _listenToPurchases();
    unawaited(_initIap());
    _loadAll();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final eq = await Storage.loadEquipment();
    final mt = await Storage.loadMaintenance();

    final remindersEnabled = await Storage.loadMaintenanceRemindersEnabled();
    final backupRemEnabled = await Storage.loadBackupRemindersEnabled();
    final lastBackupAt = await Storage.loadLastBackupAt();

    eq.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (!mounted) return;
    setState(() {
      _equipment
        ..clear()
        ..addAll(eq);
      _maintenance
        ..clear()
        ..addAll(mt);
      _maintenanceRemindersEnabled = remindersEnabled;
      _backupRemindersEnabled = backupRemEnabled;
      _lastBackupAt = lastBackupAt;
      _loading = false;
    });
  }

  Future<void> _saveAll() async {
    await Storage.saveEquipment(_equipment);
    await Storage.saveMaintenance(_maintenance);
  }

  // Share sheet export (AirDrop, Messages, etc.)
  Future<void> _exportBackupShare() async {
    try {
      final jsonText = await Storage.exportBackupJson();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final name = 'RanchHand_Backup_$stamp.json';

      final bytes = Uint8List.fromList(utf8.encode(jsonText));
      final xfile = XFile.fromData(bytes, mimeType: 'application/json', name: name);

            // iPad sometimes requires sharePositionOrigin. Use a safe on-screen rect.
      final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;
      final origin = overlayBox != null
          ? Rect.fromCenter(
              center: overlayBox.size.center(Offset.zero),
              width: 1,
              height: 1,
            )
          : const Rect.fromLTWH(0, 0, 1, 1);
await Share.shareXFiles(
        [xfile],
        text: 'Ranch Hand backup file',
        sharePositionOrigin: origin,
      );

      final now = DateTime.now();
      await Storage.saveLastBackupAt(now);
      if (mounted) setState(() => _lastBackupAt = now);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup created. Choose where to save it.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    }
  }

  // Files/iCloud Drive save (user picks location)
  Future<void> _importBackup() async {
  try {
    // iOS requires non-empty uniformTypeIdentifiers (UTIs).
    final typeGroup = XTypeGroup(
      label: 'Ranch Hand Backup',
      extensions: const ['json'],
      uniformTypeIdentifiers: const ['public.json'],
    );

    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    final raw = await file.readAsString();
    await Storage.importBackupJson(raw);

    await _loadAll();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup restored successfully.')),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restore failed: $e')),
    );
  }
}


  Future<void> _openAddEquipment() async {
    if (!_isPro && _equipment.length >= _freeEquipmentLimit) {
      await _showUpgradeDialog();
      return;
    }
    final result = await Navigator.of(context).push<Equipment>(
      MaterialPageRoute(builder: (_) => const AddEquipmentScreen()),
    );

    if (result == null) return;

    setState(() => _equipment.insert(0, result));
    await _saveAll();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "${result.name}"')),
    );
  }

  Future<void> _openEquipmentDetails(Equipment e) async {
    final result = await Navigator.of(context).push<_EquipmentDetailsResult>(
      MaterialPageRoute(
        builder: (_) => EquipmentDetailsScreen(
          equipment: e,
          allMaintenance: _maintenance,
        ),
      ),
    );

    if (result == null) {
      await _loadAll(); // autosave may have occurred
      return;
    }

    if (result.deletedEquipmentId != null) {
      setState(() {
        _equipment.removeWhere((x) => x.id == result.deletedEquipmentId);
        _maintenance
          ..clear()
          ..addAll(result.updatedMaintenance);
      });
      await _saveAll();
      return;
    }

    if (result.updatedEquipment != null) {
      final idx = _equipment.indexWhere((x) => x.id == result.updatedEquipment!.id);
      if (idx != -1) setState(() => _equipment[idx] = result.updatedEquipment!);
    }

    setState(() {
      _maintenance
        ..clear()
        ..addAll(result.updatedMaintenance);
    });

    _equipment.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _saveAll();
  }

  Future<void> _quickAddMaintenance() async {
    if (_equipment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add equipment first.')),
      );
      return;
    }

    final chosen = await Navigator.of(context).push<Equipment>(
      MaterialPageRoute(builder: (_) => ChooseEquipmentScreen(equipment: _equipment)),
    );
    if (chosen == null) return;

    final result = await Navigator.of(context).push<List<MaintenanceRecord>>(
      MaterialPageRoute(
        builder: (_) => AddMaintenanceScreen(equipment: chosen, existing: _maintenance),
      ),
    );
    if (result == null) return;

    setState(() {
      _maintenance
        ..clear()
        ..addAll(result);
    });
    await _saveAll();
  }

  @override
  Widget build(BuildContext context) {
    final count = _equipment.length;
    final lastAdded = _equipment.isNotEmpty ? fmtDateMDY(_equipment.first.createdAt) : '—';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranch Hand'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    currentThemeMode: widget.currentThemeMode,
                    onThemeChanged: widget.onThemeChanged,
                    onExportBackupShare: _exportBackupShare,
                    onImportBackup: _importBackup,
                    maintenanceRemindersEnabled: _maintenanceRemindersEnabled,
                    onMaintenanceRemindersChanged: (v) {
                      setState(() => _maintenanceRemindersEnabled = v);
                      unawaited(Storage.saveMaintenanceRemindersEnabled(v));
                      if (!v) setState(() => _filter = _EquipmentFilter.all);
                    },
                    backupRemindersEnabled: _backupRemindersEnabled,
                    onBackupRemindersChanged: (v) {
                      setState(() => _backupRemindersEnabled = v);
                      unawaited(Storage.saveBackupRemindersEnabled(v));
                    },
                    lastBackupAt: _lastBackupAt,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.agriculture),
                            const SizedBox(width: 10),
                            Text('Ranch Hand',
                                style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Track equipment and maintenance in one place.',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text('Equipment: $count'),
                            const SizedBox(width: 18),
                            Text('Last added: $lastAdded'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_backupRemindersEnabled &&
                    (_lastBackupAt == null ||
                        DateTime.now().difference(_lastBackupAt!).inDays >= 30))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Backup recommended'),
                      subtitle: Text(
                        _lastBackupAt == null
                            ? 'You haven\'t created a backup yet.'
                            : 'Last backup was ${fmtDateMDY(_lastBackupAt!)}.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _exportBackupShare,
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.add_box_outlined),
                          title: const Text('Add equipment'),
                          subtitle: const Text('Create a new item'),
                          onTap: _openAddEquipment,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.build_circle_outlined),
                          title: const Text('Maintenance'),
                          subtitle: const Text('Log a service'),
                          onTap: _quickAddMaintenance,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                                const SizedBox(height: 16),
                Text('Your equipment',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (count == 0)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No equipment yet.\n\nTap "Add equipment" to create your first item.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                else
                  ...[
                    if (_maintenanceRemindersEnabled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: _filter == _EquipmentFilter.all,
                              onSelected: (_) => setState(() => _filter = _EquipmentFilter.all),
                            ),
                            ChoiceChip(
                              label: const Text('Due soon'),
                              selected: _filter == _EquipmentFilter.dueSoon,
                              onSelected: (_) => setState(() => _filter = _EquipmentFilter.dueSoon),
                            ),
                            ChoiceChip(
                              label: const Text('Overdue'),
                              selected: _filter == _EquipmentFilter.overdue,
                              onSelected: (_) => setState(() => _filter = _EquipmentFilter.overdue),
                            ),
                          ],
                        ),
                      ),
                    ..._equipment.map((e) {
                    final subtitleParts = <String>[];

                    final type = e.type.trim();
                    if (type.isNotEmpty) subtitleParts.add(type);

                    final makeModel = [
                      (e.manufacturer ?? '').trim(),
                      (e.model ?? '').trim(),
                    ].where((s) => s.isNotEmpty).join(' ');
                    if (makeModel.isNotEmpty) subtitleParts.add(makeModel);

                    final serviceDates = _maintenance
                        .where((m) => m.equipmentId == e.id && m.serviceDate != null)
                        .map((m) => m.serviceDate!)
                        .toList()
                      ..sort();

                    final pred = predictNextDueFromDates(serviceDates);
                    final hasAnyNextDue = _maintenance.any(
                      (m) => m.equipmentId == e.id && m.hasNextDue,
                    );
                    IconData leadIcon = Icons.agriculture;

                    if (_maintenanceRemindersEnabled && pred.nextDue != null) {
                      final daysUntil = pred.nextDue!.difference(DateTime.now()).inDays;

                      if (_filter == _EquipmentFilter.overdue && daysUntil >= 0) {
                        return const SizedBox.shrink();
                      }
                      if (_filter == _EquipmentFilter.dueSoon &&
                          (daysUntil < 0 || daysUntil > 7)) {
                        return const SizedBox.shrink();
                      }

                      if (daysUntil < 0) {
                        leadIcon = Icons.warning_amber_rounded;
                      } else if (daysUntil <= 7) {
                        leadIcon = Icons.schedule;
                      } else {
                        leadIcon = Icons.check_circle_outline;
                      }

                      subtitleParts.add('Due ${fmtDateMDY(pred.nextDue!)}');
                    } else {
                      if (_maintenanceRemindersEnabled &&
                          (_filter == _EquipmentFilter.overdue ||
                              _filter == _EquipmentFilter.dueSoon)) {
                        return const SizedBox.shrink();
                      }
                      if (serviceDates.isNotEmpty) {
                        subtitleParts.add('Last service ${fmtDateMDY(serviceDates.last)}');
                      } else {
                        subtitleParts.add('No maintenance yet');
                      }
                    }

                    return Card(
                      child: ListTile(
                        leading: Icon(leadIcon),
                        title: Text(e.name),
                        subtitle: Text(subtitleParts.join(' • ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasAnyNextDue) const Icon(Icons.calendar_month, size: 18),
                            if (hasAnyNextDue) const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => _openEquipmentDetails(e),
                      ),
                    );
                  }), 
                  ],
                const SizedBox(height: 90),
              ],
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _openAddEquipment,
            icon: const Icon(Icons.add),
            label: const Text('Add Equipment'),
          ),
        ),
      ),
    );
  }
}

/* ============================
   Add Equipment
============================ */



class SettingsPage extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  final Future<void> Function() onExportBackupShare;
  final Future<void> Function() onImportBackup;

  final bool maintenanceRemindersEnabled;
  final ValueChanged<bool> onMaintenanceRemindersChanged;

  final bool backupRemindersEnabled;
  final ValueChanged<bool> onBackupRemindersChanged;

  final DateTime? lastBackupAt;

  const SettingsPage({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
    required this.onExportBackupShare,
    required this.onImportBackup,
    required this.maintenanceRemindersEnabled,
    required this.onMaintenanceRemindersChanged,
    required this.backupRemindersEnabled,
    required this.onBackupRemindersChanged,
    required this.lastBackupAt,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _maintenanceRemindersEnabled;
  late bool _backupRemindersEnabled;

  @override
  void initState() {
    super.initState();
    _maintenanceRemindersEnabled = widget.maintenanceRemindersEnabled;
    _backupRemindersEnabled = widget.backupRemindersEnabled;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep local state in sync if the parent value changes for any reason.
    if (oldWidget.maintenanceRemindersEnabled != widget.maintenanceRemindersEnabled) {
      _maintenanceRemindersEnabled = widget.maintenanceRemindersEnabled;
    }
    if (oldWidget.backupRemindersEnabled != widget.backupRemindersEnabled) {
      _backupRemindersEnabled = widget.backupRemindersEnabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastBackupAt = widget.lastBackupAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Preferences',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Maintenance reminders'),
              subtitle: const Text('Show due-soon and overdue indicators'),
              value: _maintenanceRemindersEnabled,
              onChanged: (v) {
                setState(() => _maintenanceRemindersEnabled = v);
                widget.onMaintenanceRemindersChanged(v);
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Backup reminders'),
              subtitle: Text(
                lastBackupAt == null
                    ? 'No backup created yet'
                    : 'Last backup: ${fmtDateMDY(lastBackupAt)}',
              ),
              value: _backupRemindersEnabled,
              onChanged: (v) {
                setState(() => _backupRemindersEnabled = v);
                widget.onBackupRemindersChanged(v);
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Backup & Restore',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export / Save backup'),
              subtitle: const Text('Creates a JSON backup and lets you save it to Files/iCloud or share it'),
              onTap: widget.onExportBackupShare,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Import backup'),
              subtitle: const Text('Restore equipment and maintenance from a JSON file'),
              onTap: widget.onImportBackup,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Theme',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System'),
                  value: ThemeMode.system,
                  groupValue: widget.currentThemeMode,
                  onChanged: (v) => widget.onThemeChanged(v!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                  groupValue: widget.currentThemeMode,
                  onChanged: (v) => widget.onThemeChanged(v!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                  groupValue: widget.currentThemeMode,
                  onChanged: (v) => widget.onThemeChanged(v!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddEquipmentScreen extends StatefulWidget {
  const AddEquipmentScreen({super.key});

  @override
  State<AddEquipmentScreen> createState() => _AddEquipmentScreenState();
}

class _AddEquipmentScreenState extends State<AddEquipmentScreen> {
  final _name = TextEditingController();
  final _type = TextEditingController();

  // Details
  final _manufacturer = TextEditingController();
  final _model = TextEditingController();

  final _vin = TextEditingController();
  final _serialNumber = TextEditingController();
  DateTime? _purchaseDate;

  bool _showMoreDetails = false;
  final _vendor = TextEditingController();
  final _purchasePrice = TextEditingController();
  DateTime? _warrantyUntil;
  final _location = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _manufacturer.dispose();
    _model.dispose();
    _vin.dispose();
    _serialNumber.dispose();
    _vendor.dispose();
    _purchasePrice.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final eq = Equipment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      type: _type.text.trim(),
      manufacturer: _manufacturer.text.trim().isEmpty ? null : _manufacturer.text.trim(),
      model: _model.text.trim().isEmpty ? null : _model.text.trim(),
      vin: _vin.text.trim().isEmpty ? null : _vin.text.trim(),
      serialNumber:
          _serialNumber.text.trim().isEmpty ? null : _serialNumber.text.trim(),
      purchaseDate: _purchaseDate,
      vendor: _vendor.text.trim().isEmpty ? null : _vendor.text.trim(),
      purchasePrice: _purchasePrice.text.trim().isEmpty ? null : double.tryParse(_purchasePrice.text.trim()),
      warrantyUntil: _warrantyUntil,
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      notes: _notes.text.trim(),
      createdAt: DateTime.now(),
    );

    Navigator.of(context).pop(eq);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add equipment')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Nickname',
                      hintText: 'e.g., Ford F150',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _type,
                    decoration: const InputDecoration(
                      labelText: 'Type (optional)',
                      hintText: 'e.g., Truck / Tractor / ATV',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _manufacturer,
                    decoration: const InputDecoration(
                      labelText: 'Manufacturer (optional)',
                      hintText: 'Brand',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _model,
                    decoration: const InputDecoration(
                      labelText: 'Model (optional)',
                      hintText: 'Model',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vin,
                    decoration: const InputDecoration(
                      labelText: 'VIN (optional)',
                      hintText: 'Vehicle identification number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serialNumber,
                    decoration: const InputDecoration(
                      labelText: 'Serial number (optional)',
                      hintText: 'Serial number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Purchase date (optional)'),
                    subtitle: Text(
                      _purchaseDate == null
                          ? 'Not set'
                          : fmtDateMDY(_purchaseDate!),
                    ),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _purchaseDate ?? now,
                        firstDate: DateTime(1970),
                        lastDate: DateTime(now.year + 5),
                      );
                      if (picked == null) return;
                      setState(() => _purchaseDate = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vendor,
                    decoration: const InputDecoration(
                      labelText: 'Vendor (optional)',
                      hintText: 'Where you bought it',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _purchasePrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Purchase price (optional)',
                      prefixText: '\$',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Warranty until (optional)'),
                    subtitle: Text(
                      _warrantyUntil == null ? 'Not set' : fmtDateMDY(_warrantyUntil!),
                    ),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _warrantyUntil ?? now,
                        firstDate: DateTime(1970),
                        lastDate: DateTime(now.year + 10),
                      );
                      if (picked == null) return;
                      setState(() => _warrantyUntil = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _location,
                    decoration: const InputDecoration(
                      labelText: 'Location (optional)',
                      hintText: 'Barn, shop, field, etc.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Anything you want to remember',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================
   Equipment Details (Autosave + Scan)
============================ */

class EquipmentDetailsScreen extends StatefulWidget {
  final Equipment equipment;
  final List<MaintenanceRecord> allMaintenance;

  const EquipmentDetailsScreen({
    super.key,
    required this.equipment,
    required this.allMaintenance,
  });

  @override
  State<EquipmentDetailsScreen> createState() => _EquipmentDetailsScreenState();
}

class _EquipmentDetailsScreenState extends State<EquipmentDetailsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _type;
  late final TextEditingController _vin;
  late final TextEditingController _serialNumber;
  DateTime? _purchaseDate;

  // More optional details
  late final TextEditingController _manufacturer;
  late final TextEditingController _model;
  late final TextEditingController _vendor;
  late final TextEditingController _purchasePrice;
  DateTime? _warrantyUntil;
  late final TextEditingController _location;

  late final TextEditingController _notes;

  late Equipment _working;

  bool _showMoreDetails = false;
  late List<MaintenanceRecord> _maintenanceWorking;

  static const List<String> _specOptions = [
    'Tire size',
    'Front tire size',
    'Rear tire size',
    'Oil type',
    'Oil capacity',
    'Hydraulic fluid type',
    'Hydraulic capacity',
    'Coolant type',
    'Fuel type',
    'Fuel capacity',
    'Oil filter #',
    'Air filter #',
    'Fuel filter #',
    'Hydraulic filter #',
    'Battery',
    'Spark plug',
    'Belt',
    'Grease type',
  ];

  String? _specToAdd;

  Timer? _autosaveTimer;
  bool _autosaveInFlight = false;

  final Map<String, TextEditingController> _specControllers = {};

  @override
  void initState() {
    super.initState();

    _working = Equipment(
      id: widget.equipment.id,
      name: widget.equipment.name,
      type: widget.equipment.type,
      vin: widget.equipment.vin,
      serialNumber: widget.equipment.serialNumber,
      purchaseDate: widget.equipment.purchaseDate,
      manufacturer: widget.equipment.manufacturer,
      model: widget.equipment.model,
      vendor: widget.equipment.vendor,
      purchasePrice: widget.equipment.purchasePrice,
      warrantyUntil: widget.equipment.warrantyUntil,
      location: widget.equipment.location,
      notes: widget.equipment.notes,
      createdAt: widget.equipment.createdAt,
      specs: Map<String, String>.from(widget.equipment.specs),
    );

    _maintenanceWorking = List<MaintenanceRecord>.from(widget.allMaintenance);

    _name = TextEditingController(text: _working.name);
    _type = TextEditingController(text: _working.type);
    _vin = TextEditingController(text: _working.vin ?? '');
    _serialNumber = TextEditingController(text: _working.serialNumber ?? '');
    _purchaseDate = _working.purchaseDate;

    _manufacturer = TextEditingController(text: _working.manufacturer ?? '');
    _model = TextEditingController(text: _working.model ?? '');
    _vendor = TextEditingController(text: _working.vendor ?? '');
    _purchasePrice = TextEditingController(
        text: _working.purchasePrice == null ? '' : _working.purchasePrice!.toString());
    _warrantyUntil = _working.warrantyUntil;
    _location = TextEditingController(text: _working.location ?? '');

    _notes = TextEditingController(text: _working.notes);

    _syncSpecControllersFromWorking();
  }

  void _syncSpecControllersFromWorking() {
    // create missing controllers
    for (final entry in _working.specs.entries) {
      _specControllers.putIfAbsent(
        entry.key,
        () => TextEditingController(text: entry.value),
      );
      _specControllers[entry.key]!.text = entry.value;
    }

    // dispose controllers for removed keys
    final keysToRemove =
        _specControllers.keys.where((k) => !_working.specs.containsKey(k)).toList();
    for (final k in keysToRemove) {
      _specControllers[k]?.dispose();
      _specControllers.remove(k);
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _name.dispose();
    _type.dispose();
    _manufacturer.dispose();
    _model.dispose();
    _vin.dispose();
    _serialNumber.dispose();
    _vendor.dispose();
    _purchasePrice.dispose();
    _location.dispose();
    _notes.dispose();
    for (final c in _specControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 450), () async {
      await _autosaveNow();
    });
  }

  Future<void> _autosaveNow() async {
    if (_autosaveInFlight) return;
    if (_working.name.trim().isEmpty) return;

    _autosaveInFlight = true;
    try {
      await Storage.upsertEquipment(
        Equipment(
          id: _working.id,
          name: _working.name.trim(),
          type: _working.type.trim(),
          vin: _working.vin,
          serialNumber: _working.serialNumber,
          purchaseDate: _working.purchaseDate,
          notes: _working.notes.trim(),
          createdAt: _working.createdAt,
          specs: Map<String, String>.from(_working.specs),
        ),
      );
    } finally {
      _autosaveInFlight = false;
    }
  }

  Future<void> _scanPackageAndSuggestSpecs() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo == null) return;

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(photo.path);
      final result = await recognizer.processImage(inputImage);
      await recognizer.close();

      final raw = _normalizeText(result.text);
      final suggestions = _extractSpecSuggestionsFromOcr(raw);

      if (!mounted) return;

      if (suggestions.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Nothing found'),
            content: const Text(
              'Could not detect usable specs from that photo. Try a closer shot of the part number label.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        return;
      }

      final controllers = <String, TextEditingController>{
        for (final e in suggestions.entries) e.key: TextEditingController(text: e.value),
      };

      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add scanned specs?'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...controllers.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: e.value,
                        decoration: InputDecoration(labelText: e.key),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      );

      if (approved == true) {
        setState(() {
          for (final entry in controllers.entries) {
            final key = entry.key;
            final value = entry.value.text.trim();

            if (key == 'Notes') {
              if (value.isNotEmpty) {
                final existing = _working.notes.trim();
                _working.notes = existing.isEmpty ? value : '$existing\n$value';
                _notes.text = _working.notes;
              }
            } else {
              _working.specs[key] = value;
            }
          }
          _syncSpecControllersFromWorking();
        });

        await _autosaveNow();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Specs added from scan.')),
        );
      }

      for (final c in controllers.values) {
        c.dispose();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    }
  }

  Future<void> _openAddMaintenance() async {
    final result = await Navigator.of(context).push<List<MaintenanceRecord>>(
      MaterialPageRoute(
        builder: (_) => AddMaintenanceScreen(
          equipment: _working,
          existing: _maintenanceWorking,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _maintenanceWorking
        ..clear()
        ..addAll(result);
    });

    await _autosaveNow();
  }

  Future<void> _openMaintenanceList() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MaintenanceListScreen(
          equipment: _working,
          allMaintenance: _maintenanceWorking,
        ),
      ),
    );

    // Maintenance edits/deletes happen on a separate screen and persist to Storage.
    // Reload when returning so the top Service Status card always reflects the latest data.
    if (changed == true) {
      final latest = await Storage.loadMaintenance();
      if (!mounted) return;
      setState(() {
        _maintenanceWorking = latest;
      });
    }
  }

  Future<void> _deleteThisEquipment() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this equipment?'),
        content: const Text(
          'This will permanently delete this equipment and all of its maintenance records.\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    final updatedMaintenance =
        widget.allMaintenance.where((m) => m.equipmentId != widget.equipment.id).toList();

    Navigator.of(context).pop(
      _EquipmentDetailsResult(
        deletedEquipmentId: widget.equipment.id,
        updatedEquipment: null,
        updatedMaintenance: updatedMaintenance,
      ),
    );
  }

  void _saveAndReturn() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    _working.name = name;
    _working.type = _type.text.trim();
    _working.notes = _notes.text.trim();

    await _autosaveNow();

    Navigator.of(context).pop(
      _EquipmentDetailsResult(
        deletedEquipmentId: null,
        updatedEquipment: _working,
        updatedMaintenance: _maintenanceWorking,
      ),
    );
  }

  void _removeSpec(String key) {
    setState(() {
      _working.specs.remove(key);
      _syncSpecControllersFromWorking();
    });
    _scheduleAutosave();
  }

  @override
  Widget build(BuildContext context) {
    final availableSpecs = _specOptions.where((s) => !_working.specs.containsKey(s)).toList();

    // Trend-based service prediction (learned from past maintenance history)
    final serviceDates = _maintenanceWorking
        .where((m) => m.equipmentId == widget.equipment.id && m.serviceDate != null)
        .map((m) => m.serviceDate!)
        .toList();
    final prediction = predictNextDueFromDates(serviceDates);
    final now = DateTime.now();
    final int? daysUntilDue = prediction.nextDue == null ? null : prediction.nextDue!.difference(now).inDays;

    // Earliest scheduled next service (user-entered) replaces prediction if present.
    final recordsForEq = _maintenanceWorking
        .where((m) => m.equipmentId == widget.equipment.id)
        .toList()
      ..sort((a, b) => (b.serviceDate ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.serviceDate ?? DateTime.fromMillisecondsSinceEpoch(0)));

    final completedForEq = recordsForEq.where((m) => m.serviceDate != null).toList()
      ..sort((a, b) => (b.serviceDate ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.serviceDate ?? DateTime.fromMillisecondsSinceEpoch(0)));
    final MaintenanceRecord? lastCompleted = completedForEq.isEmpty ? null : completedForEq.first;

    final scheduledWithDate = recordsForEq
        .where((m) => m.nextDueDate != null)
        .toList()
      ..sort((a, b) => a.nextDueDate!.compareTo(b.nextDueDate!));

    final int currentHoursEstimate = completedForEq
        .where((m) => m.hours != null)
        .map((m) => m.hours!)
        .fold<int>(0, (p, e) => e > p ? e : p);
    final int currentMileageEstimate = completedForEq
        .where((m) => m.mileage != null)
        .map((m) => m.mileage!)
        .fold<int>(0, (p, e) => e > p ? e : p);

    // Pick the soonest scheduled item across all services.
    MaintenanceRecord? nextScheduled;
    if (scheduledWithDate.isNotEmpty) {
      nextScheduled = scheduledWithDate.first;
    } else {
      MaintenanceRecord? best;
      int? bestDelta;

      final withHours = recordsForEq.where((m) => m.nextDueHours != null).toList()
        ..sort((a, b) => a.nextDueHours!.compareTo(b.nextDueHours!));
      for (final m in withHours) {
        final delta = m.nextDueHours! - currentHoursEstimate;
        if (delta < 0) continue;
        if (bestDelta == null || delta < bestDelta!) {
          bestDelta = delta;
          best = m;
        }
      }

      final withMileage = recordsForEq.where((m) => m.nextDueMileage != null).toList()
        ..sort((a, b) => a.nextDueMileage!.compareTo(b.nextDueMileage!));
      for (final m in withMileage) {
        final delta = m.nextDueMileage! - currentMileageEstimate;
        if (delta < 0) continue;
        if (bestDelta == null || delta < bestDelta!) {
          bestDelta = delta;
          best = m;
        }
      }

      // If we couldn't compute a "soonest" delta (missing estimates), fall back to smallest absolute.
      nextScheduled = best ??
          (withHours.isNotEmpty ? withHours.first : null) ??
          (withMileage.isNotEmpty ? withMileage.first : null);
    }

final bool showingScheduled = nextScheduled != null;
    final DateTime? topDueDate =
        showingScheduled ? nextScheduled!.nextDueDate : prediction.nextDue;
    final int? topDueHours = showingScheduled ? nextScheduled!.nextDueHours : null;
    final int? topDueMileage = showingScheduled ? nextScheduled!.nextDueMileage : null;
    final String predictedServiceName = (lastCompleted != null &&
            lastCompleted!.serviceType.trim().isNotEmpty)
        ? lastCompleted!.serviceType
        : 'Service';

    final String topServiceName =
        showingScheduled ? nextScheduled!.serviceType : predictedServiceName;



    return WillPopScope(
      onWillPop: () async {
        await _autosaveNow();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Equipment'),
          actions: [
            IconButton(
              tooltip: 'Delete equipment',
              onPressed: _deleteThisEquipment,
              icon: const Icon(Icons.delete_outline),
            ),
            TextButton(onPressed: _saveAndReturn, child: const Text('Save')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (prediction.nextDue != null)
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 56),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Service status',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),

                          // Service name (scheduled overrides prediction)
                          Text(
                            topServiceName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),

                          const SizedBox(height: 8),

                          // Last completed
                          Text(
                            lastCompleted == null
                                ? 'Last completed: —'
                                : 'Last completed: ${fmtDateMDY(lastCompleted!.serviceDate!)}'
                                    '${lastCompleted!.hours != null ? ' @ ${lastCompleted!.hours} hrs' : ''}'
                                    '${lastCompleted!.mileage != null ? ' @ ${lastCompleted!.mileage} mi' : ''}',
                          ),

                          const SizedBox(height: 8),

                          // Next due (scheduled or predicted)
                          Text(
                            (() {
                              if (showingScheduled) {
                                if (topDueDate != null) {
                                  return 'Next due (scheduled): ${fmtDateMDY(topDueDate!)}';
                                }
                                if (topDueHours != null) {
                                  return 'Next due (scheduled): ${topDueHours} hrs';
                                }
                                if (topDueMileage != null) {
                                  return 'Next due (scheduled): ${topDueMileage} mi';
                                }
                                return 'Next due: —';
                              } else {
                                return topDueDate == null
                                    ? 'Next due: —'
                                    : 'Next due (predicted): ~${fmtDateMDY(topDueDate!)}';
                              }
                            })(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),

                          const SizedBox(height: 8),

                          if (prediction.typicalIntervalDays != null)
                            Text('Typical interval: ~${prediction.typicalIntervalDays} days'),

                          const SizedBox(height: 4),
                          Text('Confidence: ${prediction.confidence}'),

                          const SizedBox(height: 8),

                          Builder(builder: (context) {
                            if (topDueDate == null && topDueHours == null && topDueMileage == null) {
                              return const SizedBox.shrink();
                            }

                            bool overdue = false;
                            bool dueSoon = false;

                            if (topDueDate != null) {
                              final daysUntil = topDueDate!.difference(now).inDays;
                              final int? intervalDays = prediction.typicalIntervalDays;
                              overdue = daysUntil < 0;
                              dueSoon = overdue ||
                                  daysUntil <= 14 ||
                                  (intervalDays != null && daysUntil <= (intervalDays * 0.2).round());
                            } else if (topDueHours != null) {
                              final delta = topDueHours! - currentHoursEstimate;
                              overdue = delta < 0;
                              // Heuristic for "soon" when we only have hours.
                              dueSoon = overdue || delta <= 10;
                            } else if (topDueMileage != null) {
                              final delta = topDueMileage! - currentMileageEstimate;
                              overdue = delta < 0;
                              // Heuristic for "soon" when we only have mileage.
                              dueSoon = overdue || delta <= 200;
                            }

                            final statusText = overdue
                                ? 'Status: Overdue'
                                : (dueSoon ? 'Status: Due soon' : 'Status: On track');

                            final statusIcon = overdue ? '🔴' : (dueSoon ? '🟡' : '🟢');
                            return Text('$statusIcon $statusText');
                          }),

                          const SizedBox(height: 4),
                          if (showingScheduled) const Text('Using your scheduled next service.'),
                        ],
                      ),
                      ),

                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MaintenanceScheduleScreen(
                                  equipment: _working,
                                  records: recordsForEq,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.table_chart),
                          label: const Text('View full maintenance schedule'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (prediction.nextDue != null) const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Basics', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nickname'),
                      onChanged: (v) {
                        _working.name = v;
                        _scheduleAutosave();
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _type,
                      decoration: const InputDecoration(labelText: 'Type (optional)'),
                      onChanged: (v) {
                        _working.type = v;
                        _scheduleAutosave();
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _manufacturer,
                      decoration: const InputDecoration(labelText: 'Manufacturer (optional)'),
                      onChanged: (v) {
                        final vv = v.trim();
                        _working.manufacturer = vv.isEmpty ? null : vv;
                        _scheduleAutosave();
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _model,
                      decoration: const InputDecoration(labelText: 'Model (optional)'),
                      onChanged: (v) {
                        final vv = v.trim();
                        _working.model = vv.isEmpty ? null : vv;
                        _scheduleAutosave();
                      },
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() => _showMoreDetails = !_showMoreDetails);
                        },
                        icon: Icon(_showMoreDetails ? Icons.expand_less : Icons.expand_more),
                        label: Text(_showMoreDetails ? 'View less' : 'View more'),
                      ),
                    ),
                    if (_showMoreDetails) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _vin,
                        decoration:
                            const InputDecoration(labelText: 'VIN (optional)'),
                        onChanged: (v) {
                          final vv = v.trim();
                          _working.vin = vv.isEmpty ? null : vv;
                          _scheduleAutosave();
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _serialNumber,
                        decoration: const InputDecoration(
                            labelText: 'Serial number (optional)'),
                        onChanged: (v) {
                          final vv = v.trim();
                          _working.serialNumber = vv.isEmpty ? null : vv;
                          _scheduleAutosave();
                        },
                      ),
                      

                      const SizedBox(height: 12),
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text('Purchase date (optional)'),
                                            subtitle: Text(_purchaseDate == null
                                                ? 'Not set'
                                                : fmtDateMDY(_purchaseDate!)),
                                            trailing: const Icon(Icons.calendar_month),
                                            onTap: () async {
                                              final now = DateTime.now();
                                              final picked = await showDatePicker(
                                                context: context,
                                                initialDate: _purchaseDate ?? now,
                                                firstDate: DateTime(1970),
                                                lastDate: DateTime(now.year + 5),
                                              );
                                              if (picked == null) return;
                                              setState(() => _purchaseDate = picked);
                                              _working.purchaseDate = picked;
                                              _scheduleAutosave();
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _vendor,
                                            decoration: const InputDecoration(labelText: 'Vendor (optional)'),
                                            onChanged: (v) {
                                              final vv = v.trim();
                                              _working.vendor = vv.isEmpty ? null : vv;
                                              _scheduleAutosave();
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _purchasePrice,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(labelText: 'Purchase price (optional)', prefixText: '\$'),
                                            onChanged: (v) {
                                              final vv = v.trim();
                                              _working.purchasePrice = vv.isEmpty ? null : double.tryParse(vv);
                                              _scheduleAutosave();
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text('Warranty until (optional)'),
                                            subtitle: Text(_warrantyUntil == null ? 'Not set' : fmtDateMDY(_warrantyUntil!)),
                                            trailing: const Icon(Icons.calendar_month),
                                            onTap: () async {
                                              final now = DateTime.now();
                                              final picked = await showDatePicker(
                                                context: context,
                                                initialDate: _warrantyUntil ?? now,
                                                firstDate: DateTime(1970),
                                                lastDate: DateTime(now.year + 10),
                                              );
                                              if (picked == null) return;
                                              setState(() => _warrantyUntil = picked);
                                              _working.warrantyUntil = picked;
                                              _scheduleAutosave();
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _location,
                                            decoration: const InputDecoration(labelText: 'Location (optional)'),
                                            onChanged: (v) {
                                              final vv = v.trim();
                                              _working.location = vv.isEmpty ? null : vv;
                                              _scheduleAutosave();
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _notes,
                                            maxLines: 3,
                                            decoration: const InputDecoration(labelText: 'Notes (optional)'),
                                            onChanged: (v) {
                                              _working.notes = v;
                                              _scheduleAutosave();
                                            },
                                          ),
                    
                    ],
const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openAddMaintenance,
                        icon: const Icon(Icons.add),
                        label: const Text('Add maintenance'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openMaintenanceList,
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('View maintenance records'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Vehicle specs', style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _scanPackageAndSuggestSpecs,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan package (photo)'),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add spec field', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _specToAdd,
                      items: availableSpecs
                          .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                          .toList(),
                      onChanged: availableSpecs.isEmpty ? null : (v) => setState(() => _specToAdd = v),
                      decoration: const InputDecoration(labelText: 'Choose a spec'),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_specToAdd == null)
                            ? null
                            : () {
                                final key = _specToAdd!;
                                setState(() {
                                  _working.specs[key] = _working.specs[key] ?? '';
                                  _specToAdd = null;
                                  _syncSpecControllersFromWorking();
                                });
                                _scheduleAutosave();
                              },
                        child: const Text('Add selected spec'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_working.specs.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No specs added yet.\n\nUse the dropdown above to add things like tire size, oil type, filter #s, etc.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ..._working.specs.keys.map((key) {
                final controller = _specControllers[key]!;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: InputDecoration(labelText: key),
                            onChanged: (v) {
                              _working.specs[key] = v;
                              _scheduleAutosave();
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _removeSpec(key),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Added'),
                subtitle: Text(fmtDateMDY(_working.createdAt)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _saveAndReturn,
                icon: const Icon(Icons.save),
                label: const Text('Save changes'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _EquipmentDetailsResult {
  final String? deletedEquipmentId;
  final Equipment? updatedEquipment;
  final List<MaintenanceRecord> updatedMaintenance;

  _EquipmentDetailsResult({
    required this.deletedEquipmentId,
    required this.updatedEquipment,
    required this.updatedMaintenance,
  });
}

/* ============================
   Choose equipment
============================ */

class ChooseEquipmentScreen extends StatelessWidget {
  final List<Equipment> equipment;
  const ChooseEquipmentScreen({super.key, required this.equipment});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose equipment')),
      body: ListView(
        children: equipment
            .map((e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.agriculture),
                    title: Text(e.name),
                    subtitle: e.type.trim().isEmpty ? null : Text(e.type.trim()),
                    onTap: () => Navigator.of(context).pop(e),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/* ============================
   Maintenance: Add + List
============================ */

class AddMaintenanceScreen extends StatefulWidget {
  final Equipment equipment;
  final List<MaintenanceRecord> existing;

  const AddMaintenanceScreen({
    super.key,
    required this.equipment,
    required this.existing,
  });

  @override
  State<AddMaintenanceScreen> createState() => _AddMaintenanceScreenState();
}

class _AddMaintenanceScreenState extends State<AddMaintenanceScreen> {
  static const List<String> _serviceTypes = [
    'Oil change',
    'Grease',
    'Air filter',
    'Fuel filter',
    'Hydraulic filter',
    'Hydraulic fluid',
    'Coolant',
    'Spark plugs',
    'Belt',
    'Tires',
    'Battery',
    'General inspection',
    'Other',
  ];

  String _serviceType = _serviceTypes.first;
  DateTime? _serviceDate;

  final _hours = TextEditingController();
  final _mileage = TextEditingController();

  // Next due (optional)
  DateTime? _nextDueDate;
  final _nextDueHours = TextEditingController();
  final _nextDueMileage = TextEditingController();

  final _notes = TextEditingController();

  @override
  void dispose() {
    _hours.dispose();
    _mileage.dispose();
    _nextDueHours.dispose();
    _nextDueMileage.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate,
      firstDate: DateTime(now.year - 30, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _serviceDate = picked);
  }

  Future<void> _save() async {
    final hours = int.tryParse(_hours.text.trim());
    final mileage = int.tryParse(_mileage.text.trim());
    final nextDueHours = int.tryParse(_nextDueHours.text.trim());
    final nextDueMileage = int.tryParse(_nextDueMileage.text.trim());

    final hasAnyNextDue = _nextDueDate != null ||
        _nextDueHours.text.trim().isNotEmpty ||
        _nextDueMileage.text.trim().isNotEmpty;
    if (_serviceDate == null && !hasAnyNextDue) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a service date or a next due to save.')),
      );
      return;
    }

    final rec = MaintenanceRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      equipmentId: widget.equipment.id,
      equipmentName: widget.equipment.name,
      serviceType: _serviceType,
      serviceDate: _serviceDate,
      hours: hours,
      mileage: mileage,
      notes: _notes.text.trim(),
      nextDueDate: _nextDueDate,
      nextDueHours: nextDueHours,
      nextDueMileage: nextDueMileage,
    );

    final updated = List<MaintenanceRecord>.from(widget.existing)..add(rec);
    updated.sort((a, b) => (b.serviceDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.serviceDate ?? DateTime.fromMillisecondsSinceEpoch(0)));

    await Storage.saveMaintenance(updated);

    if (!mounted) return;
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add maintenance • ${widget.equipment.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _serviceType,
                    items: _serviceTypes
                        .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _serviceType = v ?? _serviceTypes.first),
                    decoration: const InputDecoration(labelText: 'Service type'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Service date',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(_serviceDate == null ? 'Not set' : fmtDateMDY(_serviceDate!)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Pick'),
                      ),
                      IconButton(
                        tooltip: 'Clear date',
                        onPressed: () => setState(() => _serviceDate = null),
                        icon: const Icon(Icons.clear),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Hours (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mileage,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Mileage (optional)'),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Next due (optional)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Next due date'),
                    subtitle: Text(
                      _nextDueDate == null ? 'Not set' : fmtDateMDY(_nextDueDate!),
                    ),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _nextDueDate ?? now,
                        firstDate: DateTime(now.year - 30, 1, 1),
                        lastDate: DateTime(now.year + 10, 12, 31),
                      );
                      if (picked == null) return;
                      setState(() => _nextDueDate = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nextDueHours,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Next due hours'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nextDueMileage,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Next due mileage'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 20),

                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check),
                      label: const Text('Save maintenance'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MaintenanceListScreen extends StatefulWidget {
  final Equipment equipment;
  final List<MaintenanceRecord> allMaintenance;

  const MaintenanceListScreen({
    super.key,
    required this.equipment,
    required this.allMaintenance,
  });

  @override
  State<MaintenanceListScreen> createState() => _MaintenanceListScreenState();
}

class _MaintenanceListScreenState extends State<MaintenanceListScreen> {
  bool _loading = true;
  late List<MaintenanceRecord> _all;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    _all = await Storage.loadMaintenance();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<MaintenanceRecord> get _recordsForThisEquipment {
    final records = _all.where((r) => r.equipmentId == widget.equipment.id).toList()
      ..sort((a, b) => (b.serviceDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.serviceDate ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return records;
  }

  Future<Uint8List> _buildPdf(List<MaintenanceRecord> records) async {
    final doc = pw.Document();

    final title = widget.equipment.name.trim().isEmpty ? 'Equipment' : widget.equipment.name.trim();
    final generated = fmtDateMDY(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            'Ranch Hand — Maintenance Records',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Equipment: $title'),
          pw.Text('Generated: $generated'),
          pw.SizedBox(height: 16),
          if (records.isEmpty)
            pw.Text('No maintenance records.')
          else
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.topLeft,
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.2),
                1: pw.FlexColumnWidth(1.6),
                2: pw.FlexColumnWidth(1.0),
                3: pw.FlexColumnWidth(1.0),
                4: pw.FlexColumnWidth(2.2),
              },
              headers: const ['Date', 'Service', 'Hours', 'Miles', 'Notes'],
              data: records.map((r) {
                return [
                  r.serviceDate == null ? 'Scheduled' : fmtDateMDY(r.serviceDate!),
                  r.serviceType,
                  r.hours?.toString() ?? '',
                  r.mileage?.toString() ?? '',
                  r.notes.trim(),
                ];
              }).toList(),
            ),
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _export(BuildContext context, List<MaintenanceRecord> records) async {
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No maintenance records to export.')),
      );
      return;
    }

    final bytes = await _buildPdf(records);

    final safeName = widget.equipment.name.trim().isEmpty ? 'equipment' : widget.equipment.name.trim();
    final fileName = 'RanchHand_Maintenance_$safeName.pdf';

    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  @override
  Widget build(BuildContext context) {
    final records = _loading ? <MaintenanceRecord>[] : _recordsForThisEquipment;

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_changed);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        title: Text('Maintenance • ${widget.equipment.name}'),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            onPressed: _loading ? null : () => _export(context, records),
            icon: const Icon(Icons.picture_as_pdf),
          ),
        ],
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const Center(child: Text('No maintenance records yet.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: records.map((r) {
                    final chips = <String>[];
                    if (r.hours != null) chips.add('Hours: ${r.hours}');
                    if (r.mileage != null) chips.add('Miles: ${r.mileage}');

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.build),
                        title: Text(r.serviceType),
                        subtitle: Text(
                          [
                            r.serviceDate == null ? 'Scheduled' : fmtDateMDY(r.serviceDate!),
                            if (chips.isNotEmpty) chips.join(' • '),
                            if (r.notes.trim().isNotEmpty) 'Notes added',
                          ].join(' • '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (r.hasNextDue) const Icon(Icons.calendar_month, size: 18),
                            if (r.hasNextDue) const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () async {
                          final result = await Navigator.of(context).push<_MaintenanceDetailsResult>(
                            MaterialPageRoute(builder: (_) => MaintenanceDetailsScreen(record: r)),
                          );

                          if (result == null) return;

                          if (result.isDeleted) {
                            _all.removeWhere((x) => x.id == result.deletedId);
                            await Storage.saveMaintenance(_all);
                            await _reload();
                            _changed = true;
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Maintenance record deleted')),
                            );
                            return;
                          }

                          if (result.updated != null) {
                            final idx = _all.indexWhere((x) => x.id == result.updated!.id);
                            if (idx != -1) {
                              _all[idx] = result.updated!;
                              await Storage.saveMaintenance(_all);
                              await _reload();
                              _changed = true;
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Maintenance record updated')),
                              );
                            }
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
      ),
    );
  }
}

/* ============================
   Maintenance Details
============================ */

class _MaintenanceDetailsResult {
  final MaintenanceRecord? updated; // null if deleted
  final String? deletedId; // non-null if deleted

  const _MaintenanceDetailsResult._({this.updated, this.deletedId});

  factory _MaintenanceDetailsResult.updated(MaintenanceRecord r) =>
      _MaintenanceDetailsResult._(updated: r);

  factory _MaintenanceDetailsResult.deleted(String id) =>
      _MaintenanceDetailsResult._(deletedId: id);

  bool get isDeleted => deletedId != null;
}


class MaintenanceScheduleScreen extends StatelessWidget {
  final Equipment equipment;
  final List<MaintenanceRecord> records;

  const MaintenanceScheduleScreen({
    super.key,
    required this.equipment,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Group by service type (one row per type)
    final types = records.map((r) => r.serviceType).toSet().toList()..sort();

    if (types.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('${equipment.name} schedule')),
        body: const Center(child: Text('No services yet.')),
      );
    }

    String fmtNextDue({
      required MaintenanceRecord? scheduled,
      required TrendPrediction predicted,
    }) {
      if (scheduled != null) {
        if (scheduled.nextDueDate != null) {
          return 'Scheduled: ${fmtDateMDY(scheduled.nextDueDate!)}';
        }
        if (scheduled.nextDueHours != null) {
          return 'Scheduled: ${scheduled.nextDueHours} hrs';
        }
        if (scheduled.nextDueMileage != null) {
          return 'Scheduled: ${scheduled.nextDueMileage} mi';
        }
      }
      if (predicted.nextDue != null) {
        return 'Predicted: ~${fmtDateMDY(predicted.nextDue!)}';
      }
      return '—';
    }

    String fmtLastCompleted(MaintenanceRecord? last) {
      if (last == null || last.serviceDate == null) return '—';
      final parts = <String>[fmtDateMDY(last.serviceDate!)];
      if (last.hours != null) parts.add('${last.hours} hrs');
      if (last.mileage != null) parts.add('${last.mileage} mi');
      return parts.join(' @ ');
    }

    String fmtInterval(TrendPrediction pred) {
      if (pred.typicalIntervalDays == null) return '—';
      return '~${pred.typicalIntervalDays} days';
    }

    String fmtStatus({
      required MaintenanceRecord? scheduled,
      required TrendPrediction predicted,
      required int currentHoursEstimate,
      required int currentMileageEstimate,
    }) {
      bool overdue = false;
      bool dueSoon = false;

      if (scheduled?.nextDueDate != null) {
        final daysUntil = scheduled!.nextDueDate!.difference(now).inDays;
        final intervalDays = predicted.typicalIntervalDays;
        overdue = daysUntil < 0;
        dueSoon = overdue ||
            daysUntil <= 14 ||
            (intervalDays != null && daysUntil <= (intervalDays * 0.2).round());
      } else if (scheduled?.nextDueHours != null) {
        final delta = scheduled!.nextDueHours! - currentHoursEstimate;
        overdue = delta < 0;
        dueSoon = overdue || delta <= 10;
      } else if (scheduled?.nextDueMileage != null) {
        final delta = scheduled!.nextDueMileage! - currentMileageEstimate;
        overdue = delta < 0;
        dueSoon = overdue || delta <= 200;
      } else if (predicted.nextDue != null) {
        final daysUntil = predicted.nextDue!.difference(now).inDays;
        final intervalDays = predicted.typicalIntervalDays;
        overdue = daysUntil < 0;
        dueSoon = overdue ||
            daysUntil <= 14 ||
            (intervalDays != null && daysUntil <= (intervalDays * 0.2).round());
      } else {
        return '—';
      }

      final icon = overdue ? '🔴' : (dueSoon ? '🟡' : '🟢');
      final text = overdue ? 'Overdue' : (dueSoon ? 'Due soon' : 'On track');
      return '$icon $text';
    }

    MaintenanceRecord? pickSoonestScheduledForType(
      String type,
      int currentHoursEstimate,
      int currentMileageEstimate,
    ) {
      final perType = records.where((r) => r.serviceType == type).toList();

      final withDate = perType.where((r) => r.nextDueDate != null).toList()
        ..sort((a, b) => a.nextDueDate!.compareTo(b.nextDueDate!));
      if (withDate.isNotEmpty) return withDate.first;

      MaintenanceRecord? best;
      int? bestDelta;

      final withHours = perType.where((r) => r.nextDueHours != null).toList()
        ..sort((a, b) => a.nextDueHours!.compareTo(b.nextDueHours!));
      for (final r in withHours) {
        final delta = r.nextDueHours! - currentHoursEstimate;
        if (delta < 0) continue;
        if (bestDelta == null || delta < bestDelta!) {
          bestDelta = delta;
          best = r;
        }
      }

      final withMiles = perType.where((r) => r.nextDueMileage != null).toList()
        ..sort((a, b) => a.nextDueMileage!.compareTo(b.nextDueMileage!));
      for (final r in withMiles) {
        final delta = r.nextDueMileage! - currentMileageEstimate;
        if (delta < 0) continue;
        if (bestDelta == null || delta < bestDelta!) {
          bestDelta = delta;
          best = r;
        }
      }

      return best ??
          (withHours.isNotEmpty ? withHours.first : null) ??
          (withMiles.isNotEmpty ? withMiles.first : null);
    }

    return Scaffold(
      appBar: AppBar(title: Text('${equipment.name} schedule')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Service')),
              DataColumn(label: Text('Last Completed')),
              DataColumn(label: Text('Next Due')),
              DataColumn(label: Text('Interval')),
              DataColumn(label: Text('Status')),
            ],
            rows: [
              for (final type in types)
                () {
                  final completed = records
                      .where((r) => r.serviceType == type && r.serviceDate != null)
                      .toList()
                    ..sort((a, b) => b.serviceDate!.compareTo(a.serviceDate!));
                  final last = completed.isEmpty ? null : completed.first;

                  final currentHoursEstimate = completed
                      .where((m) => m.hours != null)
                      .map((m) => m.hours!)
                      .fold<int>(0, (p, e) => e > p ? e : p);
                  final currentMileageEstimate = completed
                      .where((m) => m.mileage != null)
                      .map((m) => m.mileage!)
                      .fold<int>(0, (p, e) => e > p ? e : p);

                  final predicted = predictNextDueFromDates(
                    completed.map((r) => r.serviceDate!).toList(),
                  );

                  final scheduled = pickSoonestScheduledForType(
                    type,
                    currentHoursEstimate,
                    currentMileageEstimate,
                  );

                  return DataRow(
                    cells: [
                      DataCell(Text(type)),
                      DataCell(Text(fmtLastCompleted(last))),
                      DataCell(Text(fmtNextDue(scheduled: scheduled, predicted: predicted))),
                      DataCell(Text(fmtInterval(predicted))),
                      DataCell(Text(fmtStatus(
                        scheduled: scheduled,
                        predicted: predicted,
                        currentHoursEstimate: currentHoursEstimate,
                        currentMileageEstimate: currentMileageEstimate,
                      ))),
                    ],
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }
}

class MaintenanceDetailsScreen extends StatefulWidget {
  final MaintenanceRecord record;

  const MaintenanceDetailsScreen({
    super.key,
    required this.record,
  });

  @override
  State<MaintenanceDetailsScreen> createState() => _MaintenanceDetailsScreenState();
}

class _MaintenanceDetailsScreenState extends State<MaintenanceDetailsScreen> {
  late TextEditingController _serviceType;
  late TextEditingController _hours;
  late TextEditingController _mileage;

  // Next due (optional)
  DateTime? _nextDueDate;
  late TextEditingController _nextDueHours;
  late TextEditingController _nextDueMileage;

  late TextEditingController _notes;

  DateTime? _serviceDate;

  @override
  void initState() {
    super.initState();
    _serviceType = TextEditingController(text: widget.record.serviceType);
    _hours = TextEditingController(text: widget.record.hours?.toString() ?? '');
    _mileage = TextEditingController(text: widget.record.mileage?.toString() ?? '');
    _nextDueDate = widget.record.nextDueDate;
    _nextDueHours = TextEditingController(text: widget.record.nextDueHours?.toString() ?? '');
    _nextDueMileage = TextEditingController(text: widget.record.nextDueMileage?.toString() ?? '');
    _notes = TextEditingController(text: widget.record.notes);

    _serviceDate = widget.record.serviceDate;
  }

  @override
  void dispose() {
    _serviceType.dispose();
    _hours.dispose();
    _mileage.dispose();
    _nextDueHours.dispose();
    _nextDueMileage.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate,
      firstDate: DateTime(now.year - 30, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked == null) return;
    setState(() => _serviceDate = picked);
  }

  void _save() {
    final hasAnyNextDue = _nextDueDate != null ||
        _nextDueHours.text.trim().isNotEmpty ||
        _nextDueMileage.text.trim().isNotEmpty;
    if (_serviceDate == null && !hasAnyNextDue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a service date or a next due to save.')),
      );
      return;
    }
    if (_serviceType.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service type is required.')),
      );
      return;
    }
    final nextDueHours = int.tryParse(_nextDueHours.text.trim());
    final nextDueMileage = int.tryParse(_nextDueMileage.text.trim());

    final updated = MaintenanceRecord(
      id: widget.record.id,
      equipmentId: widget.record.equipmentId,
      equipmentName: widget.record.equipmentName,
      serviceType: _serviceType.text.trim().isEmpty ? widget.record.serviceType : _serviceType.text.trim(),
      serviceDate: _serviceDate,
      hours: int.tryParse(_hours.text.trim()),
      mileage: int.tryParse(_mileage.text.trim()),
      notes: _notes.text.trim(),
      nextDueDate: _nextDueDate,
      nextDueHours: nextDueHours,
      nextDueMileage: nextDueMileage,
    );

    Navigator.of(context).pop(_MaintenanceDetailsResult.updated(updated));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this record?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    Navigator.of(context).pop(_MaintenanceDetailsResult.deleted(widget.record.id));
  }

  @override
  Widget build(BuildContext context) {
    final hasNextDue = _nextDueDate != null ||
        _nextDueHours.text.trim().isNotEmpty ||
        _nextDueMileage.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Expanded(child: Text('Maintenance Details')),
            if (hasNextDue) const Icon(Icons.calendar_month, size: 18),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _serviceType,
                    decoration: const InputDecoration(labelText: 'Service type'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Service date',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(_serviceDate == null ? 'Not set' : fmtDateMDY(_serviceDate!)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Pick'),
                      ),
                      IconButton(
                        tooltip: 'Clear date',
                        onPressed: () => setState(() => _serviceDate = null),
                        icon: const Icon(Icons.clear),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Hours (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mileage,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Mileage (optional)'),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Next due (optional)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Next due date'),
                    subtitle: Text(
                      _nextDueDate == null ? 'Not set' : fmtDateMDY(_nextDueDate!),
                    ),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _nextDueDate ?? now,
                        firstDate: DateTime(now.year - 30, 1, 1),
                        lastDate: DateTime(now.year + 10, 12, 31),
                      );
                      if (picked == null) return;
                      setState(() => _nextDueDate = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nextDueHours,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Next due hours'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nextDueMileage,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Next due mileage'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 20),

                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save changes'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete record'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class BackupRestorePage extends StatelessWidget {
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onImportBackup;

  const BackupRestorePage({
    super.key,
    required this.onExportBackup,
    required this.onImportBackup,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: onExportBackup,
              icon: const Icon(Icons.upload_file),
              label: const Text('Export Backup'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onImportBackup,
              icon: const Icon(Icons.download),
              label: const Text('Restore Backup'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tip: Save backups to iCloud Drive so they survive phone swaps.',
            ),
          ],
        ),
      ),
    );
  }
}
