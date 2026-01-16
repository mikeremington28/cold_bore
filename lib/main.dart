import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ColdBoreApp());
}

///
/// Cold Bore (MVP Shell + First Feature Set)
/// - Unlock (biometrics attempt; falls back to allow unlock during MVP)
/// - Users (in-memory)
/// - Equipment: Rifles + Ammo Lots (in-memory)
/// - Sessions: assign rifle/ammo + add Cold Bore entries + photo placeholders
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
    if (!_unlocked) {
      return UnlockScreen(
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

  UserProfile? _activeUser;

  List<UserProfile> get users => List.unmodifiable(_users);
  List<Rifle> get rifles => List.unmodifiable(_rifles);
  List<AmmoLot> get ammoLots => List.unmodifiable(_ammoLots);

  List<TrainingSession> get sessions => List.unmodifiable(
        _sessions.where((s) => s.userId == _activeUser?.id),
      );

  UserProfile? get activeUser => _activeUser;

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

  void addRifle({required String name, required String caliber, String notes = ''}) {
    _rifles.add(
      Rifle(
        id: _newId(),
        name: name.trim(),
        caliber: caliber.trim(),
        notes: notes.trim(),
      ),
    );
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

  void addSession({
    required String locationName,
    required DateTime dateTime,
    String notes = '',
  }) {
    final user = _activeUser;
    if (user == null) return;

    _sessions.add(
      TrainingSession(
        id: _newId(),
        userId: user.id,
        dateTime: dateTime,
        locationName: locationName.trim(),
        notes: notes.trim(),
        rifleId: null,
        ammoLotId: null,
        shots: const [],
        photos: const [],
      ),
    );
    notifyListeners();
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
      distance: distance.trim(),
      result: result.trim(),
      notes: notes.trim(),
    );

    _sessions[idx] = s.copyWith(shots: [...s.shots, entry]);
    notifyListeners();
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

  Rifle({
    required this.id,
    required this.name,
    required this.caliber,
    required this.notes,
  });
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
  });

  TrainingSession copyWith({
    DateTime? dateTime,
    String? locationName,
    String? notes,
    String? rifleId,
    String? ammoLotId,
    List<ShotEntry>? shots,
    List<PhotoNote>? photos,
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
    );
  }
}

class ShotEntry {
  final String id;
  final DateTime time;
  final bool isColdBore;
  final String distance;
  final String result;
  final String notes;

  ShotEntry({
    required this.id,
    required this.time,
    required this.isColdBore,
    required this.distance,
    required this.result,
    required this.notes,
  });
}

/// MVP placeholder for photos until we wire image_picker + storage.
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

class UnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const UnlockScreen({super.key, required this.onUnlocked});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _busy = false;
  String? _error;

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      bool ok = false;

      if (isSupported && canCheck) {
        ok = await _auth.authenticate(
          localizedReason: 'Unlock Cold Bore',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );
      } else {
        // Device doesn't support biometrics — in MVP we allow unlock.
        ok = true;
      }

      if (!mounted) return;

      if (ok) {
        widget.onUnlocked();
      } else {
        setState(() => _error = 'Unlock canceled.');
      }
    } catch (e) {
      if (!mounted) return;
      // In MVP we still allow unlock if auth fails unexpectedly.
      setState(() => _error = 'Biometric error (allowed to continue): $e');
      widget.onUnlocked();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.shield_outlined, size: 64),
              const SizedBox(height: 12),
              const Text(
                'Cold Bore',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Protected logbook (MVP)',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.lock_open),
                label: Text(_busy ? 'Unlocking…' : 'Unlock'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const Spacer(),
              Text(
                'Tip: PIN + biometrics settings come next.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
              NavigationDestination(icon: Icon(Icons.ios_share_outlined), label: 'Export'),
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
    state.addSession(
      locationName: res.locationName,
      dateTime: res.dateTime,
      notes: res.notes,
    );
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
          appBar: AppBar(title: const Text('Session')),
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
              if (s.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(s.notes),
              ],
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
                          leading: const Icon(Icons.ac_unit_outlined),
                          title: Text('${shot.distance} • ${shot.result}'),
                          subtitle: Text(_fmtDateTime(shot.time)),
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
              leading: const Icon(Icons.ac_unit_outlined),
              title: Text('${r.shot.distance} • ${r.shot.result}'),
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
                    builder: (_) => SessionDetailScreen(state: state, sessionId: r.session.id),
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
    widget.state.addRifle(name: res.name, caliber: res.caliber, notes: res.notes);
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
                                  subtitle: Text(r.caliber + (r.notes.isEmpty ? '' : ' • ${r.notes}')),
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

class _NewRifleResult {
  final String name;
  final String caliber;
  final String notes;
  _NewRifleResult({required this.name, required this.caliber, required this.notes});
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

  @override
  void dispose() {
    _name.dispose();
    _caliber.dispose();
    _notes.dispose();
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
              _NewRifleResult(name: name, caliber: caliber, notes: _notes.text),
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
