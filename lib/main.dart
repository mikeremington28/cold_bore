import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ColdBoreApp());
}

///
/// Cold Bore (MVP Shell)
/// - Unlock (PIN/Biometrics placeholder with real biometric attempt)
/// - Users (in-memory)
/// - Sessions (in-memory)
///
/// NOTE: This is intentionally "no database yet" to keep the project stable.
/// We'll swap AppState storage to a real DB later.
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
    // Seed with a demo user so the app isn't empty on first run.
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
  final List<TrainingSession> _sessions = [];

  UserProfile? _activeUser;

  List<UserProfile> get users => List.unmodifiable(_users);
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

    // One demo session
    _sessions.add(
      TrainingSession(
        id: _newId(),
        userId: u.id,
        dateTime: DateTime.now(),
        locationName: 'Demo Range',
        notes: 'This is a placeholder session. Replace with your real data.',
      ),
    );
    notifyListeners();
  }

  void addUser({required String name, required String identifier}) {
    final u = UserProfile(id: _newId(), name: name.trim(), identifier: identifier.trim());
    _users.add(u);
    _activeUser ??= u;
    notifyListeners();
  }

  void switchUser(UserProfile user) {
    _activeUser = user;
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
      ),
    );
    notifyListeners();
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

class TrainingSession {
  final String id;
  final String userId;
  final DateTime dateTime;
  final String locationName;
  final String notes;

  TrainingSession({
    required this.id,
    required this.userId,
    required this.dateTime,
    required this.locationName,
    required this.notes,
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
        // Device doesn't support biometrics — in MVP shell we allow "unlock".
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
      // In the shell we still allow unlock if auth fails unexpectedly,
      // so you can keep building without being blocked.
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
                'Protected logbook (MVP shell)',
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
                'Tip: This is a placeholder unlock flow.\nWe will add PIN + biometrics settings next.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65)),
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
    final user = widget.state.activeUser;

    final pages = <Widget>[
      SessionsScreen(state: widget.state),
      ColdBorePlaceholderScreen(state: widget.state),
      EquipmentPlaceholderScreen(state: widget.state),
      ExportPlaceholderScreen(state: widget.state),
    ];

    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cold Bore'),
            actions: [
              if (user != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text(
                      '${user.identifier}',
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
              NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                label: 'Sessions',
              ),
              NavigationDestination(
                icon: Icon(Icons.ac_unit_outlined),
                label: 'Cold Bore',
              ),
              NavigationDestination(
                icon: Icon(Icons.build_outlined),
                label: 'Equipment',
              ),
              NavigationDestination(
                icon: Icon(Icons.ios_share_outlined),
                label: 'Export',
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
              return ListTile(
                title: Text(s.locationName),
                subtitle: Text(_fmtDateTime(s.dateTime)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SessionDetailPlaceholder(session: s),
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

class SessionDetailPlaceholder extends StatelessWidget {
  final TrainingSession session;
  const SessionDetailPlaceholder({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.locationName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(_fmtDateTime(session.dateTime)),
            const SizedBox(height: 16),
            const Text(
              'Placeholder',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'This is the shell. Next we will add:\n'
              '• Session fields (conditions, GPS toggle, attachments)\n'
              '• Shot Events (including Cold Bore)\n'
              '• Database persistence',
            ),
            const SizedBox(height: 16),
            if (session.notes.isNotEmpty) ...[
              const Text('Notes', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(session.notes),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder tabs (wired later)
class ColdBorePlaceholderScreen extends StatelessWidget {
  final AppState state;
  const ColdBorePlaceholderScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.ac_unit_outlined,
      title: 'Cold Bore',
      message: 'Next we’ll add the Cold Bore list + filters.',
    );
  }
}

class EquipmentPlaceholderScreen extends StatelessWidget {
  final AppState state;
  const EquipmentPlaceholderScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.build_outlined,
      title: 'Equipment',
      message: 'Next we’ll add Rifles, Optics, and Ammo Lots.',
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

/// Simple empty state widget
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

/// Dialogs

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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
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
  _NewSessionResult({
    required this.locationName,
    required this.dateTime,
    required this.notes,
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
              TextButton(
                onPressed: _pickDateTime,
                child: const Text('Change'),
              ),
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
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

String _fmtDateTime(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final y = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$m/$d/$y $hh:$mm';
}
