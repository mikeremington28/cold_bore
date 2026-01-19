import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

enum DistanceUnit { yards, meters }

enum ElevationUnit { mil, moa }

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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ColdBoreApp());
}

///
/// Cold Bore (MVP Shell + First Feature Set)
/// - Unlock (biometrics attempt; falls back to allow unlock during MVP)
/// - Users (in-memory)
/// - Equipment: Rifles + Ammo Lots (in-memory)
/// - Sessions: assign rifle/ammo + add Cold Bore entries + photos + training DOPE
///
/// NOTE: Still "no database yet". We'll swap AppState storage to a real DB later.
///
class ColdBoreApp extends StatelessWidget {
  const ColdBoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cold Bore',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
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
    if (!_unlocked) {
      return HomeScreen(
        onUnlocked: () => setState(() => _unlocked = true),
      );
    }

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

  List<UserProfile> get users => List.unmodifiable(_users);
  List<Rifle> get rifles => List.unmodifiable(_rifles);
  List<AmmoLot> get ammoLots => List.unmodifiable(_ammoLots);

  List<TrainingSession> get sessions => List.unmodifiable(
        _sessions.where((s) => s.userId == _activeUser?.id),
      );

  UserProfile? get activeUser => _activeUser;

  Map<String, Map<DistanceKey, DopeEntry>> get workingDopeRifleOnly => _workingDopeRifleOnly;
  Map<String, Map<DistanceKey, DopeEntry>> get workingDopeRifleAmmo => _workingDopeRifleAmmo;

  void ensureSeedData() {
    if (_users.isNotEmpty) return;

    final u = UserProfile(
      id: _newId(),
      name: 'Demo User',
      identifier: 'DEMO',
    );
    _users.add(u);
    _activeUser = u;

    final demoRifle = Rifle(
      id: _newId(),
      name: 'Demo Rifle',
      caliber: '.308',
      notes: 'Placeholder rifle',
      dope: '',
    );
    _rifles.add(demoRifle);

    final demoAmmo = AmmoLot(
      id: _newId(),
      name: 'Demo Ammo',
      caliber: '.308',
      bullet: '175gr',
      notes: 'Placeholder ammo lot',
    );
    _ammoLots.add(demoAmmo);

    _sessions.add(
      TrainingSession(
        id: _newId(),
        userId: u.id,
        dateTime: DateTime.now(),
        locationName: 'Demo Range',
        notes: 'Tap a session to add rifle/ammo and a cold bore entry.',
        rifleId: demoRifle.id,
        ammoLotId: demoAmmo.id,
        shots: const [],
        photos: const [],
        trainingDope: const [],
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
    required String name,
    required String caliber,
    String notes = '',
    String dope = '',
  }) {
    _rifles.add(
      Rifle(
        id: _newId(),
        name: name.trim(),
        caliber: caliber.trim(),
        notes: notes.trim(),
        dope: dope.trim(),
      ),
    );
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
    required String name,
    required String caliber,
    String bullet = '',
    String notes = '',
  }) {
    _ammoLots.add(
      AmmoLot(
        id: _newId(),
        name: name.trim(),
        caliber: caliber.trim(),
        bullet: bullet.trim(),
        notes: notes.trim(),
      ),
    );
    notifyListeners();
  }

  TrainingSession? addSession({
    required String locationName,
    required DateTime dateTime,
    String notes = '',
  }) {
    final user = _activeUser;
    if (user == null) return null;

    final created = TrainingSession(
      id: _newId(),
      userId: user.id,
      dateTime: dateTime,
      locationName: locationName.trim(),
      notes: notes.trim(),
      rifleId: null,
      ammoLotId: null,
      shots: const [],
      photos: const [],
      trainingDope: const [],
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
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];
    _sessions[idx] = s.copyWith(
      rifleId: rifleId,
      ammoLotId: ammoLotId,
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

    _sessions[idx] = s.copyWith(shots: [...s.shots, entry]);
    notifyListeners();
  }

  void addTrainingDope({
    required String sessionId,
    required DopeEntry entry,
    bool promote = false,
    bool rifleOnly = true,
  }) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];

    final updatedEntry = DopeEntry(
      id: _newId(),
      time: entry.time,
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

    _sessions[idx] = s.copyWith(trainingDope: [...s.trainingDope, updatedEntry]);

    if (promote) {
      final rifleId = s.rifleId;
      if (rifleId == null) return;

      String key;
      Map<String, Map<DistanceKey, DopeEntry>> workingMap;

      if (rifleOnly || s.ammoLotId == null) {
        key = rifleId;
        workingMap = _workingDopeRifleOnly;
      } else {
        key = '${rifleId}_${s.ammoLotId}';
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
}

class UserProfile {
  final String id;
  final String name;
  final String identifier;

  UserProfile({
    required this.id,
    required this.name,
    required this.identifier,
  });
}

class Rifle {
  final String id;
  final String name;
  final String caliber;
  final String notes;
  final String dope;

  Rifle({
    required this.id,
    required this.name,
    required this.caliber,
    required this.notes,
    required this.dope,
  });

  Rifle copyWith({
    String? name,
    String? caliber,
    String? notes,
    String? dope,
  }) {
    return Rifle(
      id: id,
      name: name ?? this.name,
      caliber: caliber ?? this.caliber,
      notes: notes ?? this.notes,
      dope: dope ?? this.dope,
    );
  }
}

class AmmoLot {
  final String id;
  final String name;
  final String caliber;
  final String bullet;
  final String notes;

  AmmoLot({
    required this.id,
    required this.name,
    required this.caliber,
    required this.bullet,
    required this.notes,
  });
}

class TrainingSession {
  final String id;
  final String userId;
  final DateTime dateTime;
  final String locationName;
  final String notes;

  final String? rifleId;
  final String? ammoLotId;

  final List<ShotEntry> shots;
  final List<PhotoNote> photos;
  final List<DopeEntry> trainingDope;

  TrainingSession({
    required this.id,
    required this.userId,
    required this.dateTime,
    required this.locationName,
    required this.notes,
    required this.rifleId,
    required this.ammoLotId,
    required this.shots,
    required this.photos,
    required this.trainingDope,
  });

  TrainingSession copyWith({
    DateTime? dateTime,
    String? locationName,
    String? notes,
    String? rifleId,
    String? ammoLotId,
    List<ShotEntry>? shots,
    List<PhotoNote>? photos,
    List<DopeEntry>? trainingDope,
  }) {
    return TrainingSession(
      id: id,
      userId: userId,
      dateTime: dateTime ?? this.dateTime,
      locationName: locationName ?? this.locationName,
      notes: notes ?? this.notes,
      rifleId: rifleId ?? this.rifleId,
      ammoLotId: ammoLotId ?? this.ammoLotId,
      shots: shots ?? this.shots,
      photos: photos ?? this.photos,
      trainingDope: trainingDope ?? this.trainingDope,
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

/// MVP placeholder for *session-level* photos (until we wire storage).
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
  bool _rifleOnly = true;
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
                            DataCell(Text('${e.elevation} ${e.elevationUnit.name} ${e.elevationNotes}')),
                            DataCell(Text('${e.windType.name}: ${e.windValue} ${e.windNotes}')),
                            DataCell(Text('${e.windageLeft}')),
                            DataCell(Text('${e.windageRight}')),
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
                          'No DOPE saved yet. Add it under Equipment → Rifles.',
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
                                  '${r.name} • ${r.caliber}',
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
    widget.state.addUser(name: res.name, identifier: res.identifier);
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
          return ListTile(
            title: Text(u.name),
            subtitle: Text(u.identifier),
            trailing: isActive ? const Icon(Icons.check_circle_outline) : null,
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
      notes: res.notes,
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
        final sessions = state.sessions;

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
            message: 'Tap “New Session” to add your first training day.',
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
              final subtitleBits = <String>[
                _fmtDateTime(s.dateTime),
                if (rifle != null) rifle.name,
                if (ammo != null) ammo.name,
              ];

              return ListTile(
                title: Text(s.locationName),
                subtitle: Text(subtitleBits.join(' • ')),
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
  final DateTime defaultTime;
  const _DopeEntryDialog({required this.defaultTime});

  @override
  State<_DopeEntryDialog> createState() => _DopeEntryDialogState();
}

class _DopeEntryDialogState extends State<_DopeEntryDialog> {
  final _distanceCtrl = TextEditingController();
  DistanceUnit _distanceUnit = DistanceUnit.yards;
  double _elevation = 0.0;
  ElevationUnit _elevationUnit = ElevationUnit.mil;
  final _elevationNotesCtrl = TextEditingController();
  WindType _windType = WindType.fullValue;
  final _windValueCtrl = TextEditingController();
  final _windNotesCtrl = TextEditingController();
  double _windageLeft = 0.0;
  double _windageRight = 0.0;
  bool _promote = false;
  bool _rifleOnly = true;

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
    return AlertDialog(
      title: const Text('Add Training DOPE'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              children: [
                const Text('Elevation'),
                Slider(
                  value: _elevation,
                  min: 0.0,
                  max: 20.0, // Adjust max as needed
                  divisions: 200,
                  label: _elevation.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _elevation = v),
                ),
                DropdownButton<ElevationUnit>(
                  value: _elevationUnit,
                  items: ElevationUnit.values
                      .map((u) => DropdownMenuItem(value: u, child: Text(u.name.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setState(() => _elevationUnit = v!),
                ),
              ],
            ),
            TextField(
              controller: _elevationNotesCtrl,
              decoration: const InputDecoration(labelText: 'Elevation notes (optional)'),
            ),
            const SizedBox(height: 8),
            const Text('Wind format:'),
            RadioListTile<WindType>(
              title: const Text('Full value (e.g. 0.8L)'),
              value: WindType.fullValue,
              groupValue: _windType,
              onChanged: (v) => setState(() => _windType = v!),
            ),
            RadioListTile<WindType>(
              title: const Text('Clock system (e.g. 3 o\'clock, 8 mph)'),
              value: WindType.clock,
              groupValue: _windType,
              onChanged: (v) => setState(() => _windType = v!),
            ),
            TextField(
              controller: _windValueCtrl,
              decoration: const InputDecoration(labelText: 'Wind value'),
            ),
            TextField(
              controller: _windNotesCtrl,
              decoration: const InputDecoration(labelText: 'Wind notes (optional)'),
            ),
            Column(
              children: [
                const Text('Windage Left'),
                Slider(
                  value: _windageLeft,
                  min: 0.0,
                  max: 10.0, // Adjust max as needed
                  divisions: 100,
                  label: _windageLeft.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _windageLeft = v),
                ),
              ],
            ),
            Column(
              children: [
                const Text('Windage Right'),
                Slider(
                  value: _windageRight,
                  min: 0.0,
                  max: 10.0, // Adjust max as needed
                  divisions: 100,
                  label: _windageRight.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _windageRight = v),
                ),
              ],
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

            final entry = DopeEntry(
              id: '', // will be set in state
              time: DateTime.now(),
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
      notes: res.notes,
    );
  }

  Future<void> _addPhotoNote(BuildContext context, TrainingSession s) async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => const _PhotoNoteDialog(),
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

  Future<void> _addDope(BuildContext context, TrainingSession s) async {
    final res = await showDialog<_DopeResult>(
      context: context,
      builder: (_) => _DopeEntryDialog(defaultTime: DateTime.now()),
    );
    if (res == null) return;

    if (res.promote) {
      if (s.rifleId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a rifle in Loadout to promote DOPE.')),
        );
        return;
      }
      if (!res.rifleOnly && s.ammoLotId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select ammo to promote to Rifle + Ammo scope.')),
        );
        return;
      }

      final key = res.rifleOnly ? s.rifleId! : '${s.rifleId}_${s.ammoLotId}';
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

        return Scaffold(
          appBar: AppBar(
            title: const Text('Session'),
            actions: [
              IconButton(
                tooltip: 'Edit training notes',
                onPressed: () => _editTrainingNotes(context, s),
                icon: const Icon(Icons.edit_note_outlined),
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
              const SizedBox(height: 16),
              _SectionTitle('Training Notes'),
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
              _SectionTitle('Loadout'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: s.rifleId,
                      decoration: const InputDecoration(labelText: 'Rifle'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                        ...state.rifles.map(
                          (r) => DropdownMenuItem<String?>(value: r.id, child: Text('${r.name} (${r.caliber})')),
                        ),
                      ],
                      onChanged: (v) => state.updateSessionLoadout(sessionId: s.id, rifleId: v, ammoLotId: s.ammoLotId),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: s.ammoLotId,
                      decoration: const InputDecoration(labelText: 'Ammo'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                        ...state.ammoLots.map(
                          (a) => DropdownMenuItem<String?>(value: a.id, child: Text('${a.name} (${a.caliber})')),
                        ),
                      ],
                      onChanged: (v) => state.updateSessionLoadout(sessionId: s.id, rifleId: s.rifleId, ammoLotId: v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionTitle('Cold Bore Entries'),
              const SizedBox(height: 8),
              if (s.shots.where((x) => x.isColdBore).isEmpty)
                _HintCard(
                  icon: Icons.ac_unit_outlined,
                  title: 'No cold bore entries yet',
                  message: 'Tap “Add Cold Bore” to log the first shot for this session.',
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
              _SectionTitle('Training DOPE'),
              const SizedBox(height: 8),
              if (s.trainingDope.isEmpty)
                _HintCard(
                  icon: Icons.my_location_outlined,
                  title: 'No training DOPE yet',
                  message: 'Tap Add to log DOPE during this session.',
                  actionLabel: 'Add DOPE',
                  onAction: () => _addDope(context, s),
                )
              else
                ...s.trainingDope.map(
                      (e) => Card(
                        child: ListTile(
                          title: Text('${e.distance} ${e.distanceUnit.name} • ${e.elevation} ${e.elevationUnit.name}'),
                          subtitle: Text('${e.windType.name}: ${e.windValue} • Left: ${e.windageLeft} • Right: ${e.windageRight}'),
                        ),
                      ),
                    ),
              const SizedBox(height: 16),
              _SectionTitle('Photos'),
              const SizedBox(height: 8),
              _HintCard(
                icon: Icons.photo_camera_outlined,
                title: 'Photo capture is next',
                message: 'For now, add a photo caption as a placeholder. Next step: wire real photo picking.',
                actionLabel: 'Add photo note',
                onAction: () => _addPhotoNote(context, s),
              ),
              if (s.photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...s.photos.map(
                      (p) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.photo_outlined),
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
                'Loadout: ${rifle?.name ?? '—'} / ${ammo?.name ?? '—'}',
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
            message: 'Open a session and tap “Add Cold Bore”.',
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
                  if (rifle != null) rifle.name,
                  if (ammo != null) ammo.name,
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
        const SnackBar(content: Text('No baseline set yet. Tap “Mark as Baseline” first.')),
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
      builder: (_) => const _NewRifleDialog(),
    );
    if (res == null) return;
    widget.state.addRifle(name: res.name, caliber: res.caliber, notes: res.notes, dope: res.dope);
  }

  Future<void> _addAmmo() async {
    final res = await showDialog<_NewAmmoResult>(
      context: context,
      builder: (_) => const _NewAmmoDialog(),
    );
    if (res == null) return;
    widget.state.addAmmoLot(
      name: res.name,
      caliber: res.caliber,
      bullet: res.bullet,
      notes: res.notes,
    );
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
                          emptyMessage: 'Tap “Add Rifle” to create your first rifle.',
                          items: rifles
                              .map(
                                (r) => ListTile(
                                  leading: const Icon(Icons.sports_martial_arts_outlined),
                                  title: Text(r.name),
                                  subtitle: Text(
                                    r.caliber +
                                        (r.notes.isEmpty ? '' : ' • ${r.notes}') +
                                        (r.dope.trim().isEmpty ? '' : ' • DOPE saved'),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Edit DOPE',
                                    icon: const Icon(Icons.edit_note_outlined),
                                    onPressed: () async {
                                      final updated = await showDialog<String>(
                                        context: context,
                                        builder: (_) => _EditDopeDialog(initialValue: r.dope),
                                      );
                                      if (updated == null) return;
                                      widget.state.updateRifleDope(rifleId: r.id, dope: updated);
                                    },
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      : _EquipmentList(
                          emptyTitle: 'No ammo lots yet',
                          emptyMessage: 'Tap “Add Ammo” to create your first ammo lot.',
                          items: ammo
                              .map(
                                (a) => ListTile(
                                  leading: const Icon(Icons.inventory_2_outlined),
                                  title: Text(a.name),
                                  subtitle: Text(
                                    a.caliber +
                                        (a.bullet.isEmpty ? '' : ' • ${a.bullet}') +
                                        (a.notes.isEmpty ? '' : ' • ${a.notes}'),
                                  ),
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

class ExportPlaceholderScreen extends StatelessWidget {
  final AppState state;
  const ExportPlaceholderScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.ios_share_outlined,
      title: 'Export',
      message: 'Next we’ll add PDF/CSV export options and redaction.',
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
  final String name;
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
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _id,
            decoration: const InputDecoration(labelText: 'Identifier (badge/initials)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            final identifier = _id.text.trim();
            if (name.isEmpty || identifier.isEmpty) return;
            Navigator.of(context).pop(_NewUserResult(name, identifier));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _NewSessionResult {
  final String locationName;
  final DateTime dateTime;
  final String notes;
  _NewSessionResult({required this.locationName, required this.dateTime, required this.notes});
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog();

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final _location = TextEditingController();
  final _notes = TextEditingController();
  DateTime _dateTime = DateTime.now();

  @override
  void dispose() {
    _location.dispose();
    _notes.dispose();
    super.dispose();
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
            decoration: const InputDecoration(labelText: 'Named location'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(_fmtDateTime(_dateTime))),
              TextButton(onPressed: _pickDateTime, child: const Text('Change')),
            ],
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 3,
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
              _NewSessionResult(locationName: loc, dateTime: _dateTime, notes: _notes.text),
            );
          },
          child: const Text('Save'),
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
  final DateTime defaultTime;
  const _ColdBoreDialog({required this.defaultTime});

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
      title: const Text('Training Notes'),
      content: TextField(
        controller: _c,
        maxLines: 6,
        decoration: const InputDecoration(
          hintText: 'Add training notes for this session…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
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
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Photo note'),
      content: TextField(
        controller: _caption,
        decoration: const InputDecoration(labelText: 'Caption'),
        maxLines: 2,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_caption.text),
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
      content: TextField(
        controller: _c,
        decoration: const InputDecoration(
          labelText: 'DOPE / Come-ups',
          hintText: 'Example: 100y 0.0 | 200y 0.6 | 300y 1.4 ...',
        ),
        maxLines: 6,
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

class _NewRifleResult {
  final String name;
  final String caliber;
  final String notes;
  final String dope;
  _NewRifleResult({
    required this.name,
    required this.caliber,
    required this.notes,
    required this.dope,
  });
}

class _NewRifleDialog extends StatefulWidget {
  const _NewRifleDialog();

  @override
  State<_NewRifleDialog> createState() => _NewRifleDialogState();
}

class _NewRifleDialogState extends State<_NewRifleDialog> {
  final _name = TextEditingController();
  final _caliber = TextEditingController();
  final _notes = TextEditingController();
  final _dope = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _caliber.dispose();
    _notes.dispose();
    _dope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add rifle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _caliber,
            decoration: const InputDecoration(labelText: 'Caliber'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _dope,
            decoration: const InputDecoration(
              labelText: 'DOPE (quick reference)',
              hintText: 'Example: 100y 0.0 | 200y 0.6 | 300y 1.4 ...',
            ),
            maxLines: 4,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            final caliber = _caliber.text.trim();
            if (name.isEmpty || caliber.isEmpty) return;
            Navigator.of(context).pop(
              _NewRifleResult(
                name: name,
                caliber: caliber,
                notes: _notes.text,
                dope: _dope.text,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _NewAmmoResult {
  final String name;
  final String caliber;
  final String bullet;
  final String notes;
  _NewAmmoResult({required this.name, required this.caliber, required this.bullet, required this.notes});
}

class _NewAmmoDialog extends StatefulWidget {
  const _NewAmmoDialog();

  @override
  State<_NewAmmoDialog> createState() => _NewAmmoDialogState();
}

class _NewAmmoDialogState extends State<_NewAmmoDialog> {
  final _name = TextEditingController();
  final _caliber = TextEditingController();
  final _bullet = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _caliber.dispose();
    _bullet.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add ammo lot'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _caliber,
            decoration: const InputDecoration(labelText: 'Caliber'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _bullet,
            decoration: const InputDecoration(labelText: 'Bullet (optional)'),
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
            final name = _name.text.trim();
            final caliber = _caliber.text.trim();
            if (name.isEmpty || caliber.isEmpty) return;
            Navigator.of(context).pop(
              _NewAmmoResult(name: name, caliber: caliber, bullet: _bullet.text, notes: _notes.text),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

String _fmtDateTime(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final y = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$m/$d/$y $hh:$mm';
}