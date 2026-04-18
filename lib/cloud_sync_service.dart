import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class CloudShareResult {
  final List<String> resolvedIdentifiers;
  final List<String> unresolvedIdentifiers;

  const CloudShareResult({
    required this.resolvedIdentifiers,
    required this.unresolvedIdentifiers,
  });
}

class _MembershipState {
  final List<String> identifiers;
  final List<String> uids;

  const _MembershipState({required this.identifiers, required this.uids});
}

/// Phase 1 cloud foundation for cross-device auto-populate.
///
/// This initializes Firebase and signs in anonymously when possible.
/// If Firebase is not configured yet, it fails gracefully and keeps the app local-only.
class CloudSyncService extends ChangeNotifier {
  static final CloudSyncService _instance = CloudSyncService._();
  factory CloudSyncService() => _instance;
  CloudSyncService._();

  bool _ready = false;
  String? _userId;
  String? _lastError;
  DateTime? _lastSyncAt;
  String? _activeIdentifier;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sharedSessionSub;
  final Map<String, _MembershipState> _ownedSessionMembers =
      <String, _MembershipState>{};

  bool get isReady => _ready;
  String? get userId => _userId;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;

  String _normalizeIdentifier(String raw) => raw.trim().toUpperCase();

  bool get canSync => _ready && _activeIdentifier != null;

  void _setSyncedNow() {
    _lastSyncAt = DateTime.now();
    _lastError = null;
    notifyListeners();
  }

  Future<void> detachIdentity() async {
    _activeIdentifier = null;
    _ownedSessionMembers.clear();
    await _sharedSessionSub?.cancel();
    _sharedSessionSub = null;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_ready) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final auth = FirebaseAuth.instance;
      final current = auth.currentUser;
      if (current != null) {
        _userId = current.uid;
      } else {
        final credential = await auth.signInAnonymously();
        _userId = credential.user?.uid;
      }

      _ready = _userId != null;
      _lastError = _ready ? null : 'Anonymous sign-in failed.';

      if (_ready) {
        // Touch Firestore to ensure plugin is initialized for later sync work.
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
        );
      }
    } on FirebaseAuthException catch (e) {
      _ready = false;
      _userId = null;
      if (e.code == 'admin-restricted-operation') {
        _lastError =
            'Cloud sync is disabled in Firebase. Enable Anonymous sign-in in Firebase Authentication to use session sync.';
      } else {
        _lastError = e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : e.toString();
      }
      debugPrint('CloudSyncService auth initialize failed: $e');
    } catch (e) {
      _ready = false;
      _userId = null;
      _lastError = e.toString();
      debugPrint('CloudSyncService initialize failed: $e');
    }

    notifyListeners();
  }

  Future<void> _registerProfile(String identifier) async {
    if (!_ready || _userId == null) return;
    final normalized = _normalizeIdentifier(identifier);
    if (normalized.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(_userId)
        .set({
          'uid': _userId,
          'identifierUpper': normalized,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<Map<String, String>> _resolveIdentifiersToUids(
    List<String> identifiers,
  ) async {
    final out = <String, String>{};
    if (!_ready || identifiers.isEmpty) return out;

    final normalized = identifiers
        .map(_normalizeIdentifier)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (normalized.isEmpty) return out;

    for (var i = 0; i < normalized.length; i += 10) {
      final chunk = normalized.sublist(
        i,
        i + 10 > normalized.length ? normalized.length : i + 10,
      );
      final query = await FirebaseFirestore.instance
          .collection('user_profiles')
          .where('identifierUpper', whereIn: chunk)
          .get();
      for (final doc in query.docs) {
        final data = doc.data();
        final key = _normalizeIdentifier(
          (data['identifierUpper'] ?? '').toString(),
        );
        final uid = (data['uid'] ?? doc.id).toString().trim();
        if (key.isNotEmpty && uid.isNotEmpty) {
          out[key] = uid;
        }
      }
    }

    return out;
  }

  Future<void> attachIdentity({
    required String identifier,
    required void Function(
      Map<String, dynamic> sessionMap,
      String ownerId,
      int updatedAtMs,
    )
    onRemoteSession,
  }) async {
    final normalized = _normalizeIdentifier(identifier);
    if (!_ready || normalized.isEmpty) return;
    if (_activeIdentifier == normalized && _sharedSessionSub != null) return;

    await _registerProfile(normalized);
    final uid = _userId;
    if (uid == null) return;

    _activeIdentifier = normalized;
    await _sharedSessionSub?.cancel();
    _ownedSessionMembers.clear();

    final owned = await FirebaseFirestore.instance
        .collection('shared_sessions')
        .where('ownerUid', isEqualTo: uid)
        .get();
    for (final doc in owned.docs) {
      final data = doc.data();
      final identifiers = ((data['memberIdentifiers'] as List?) ?? const [])
          .map((e) => _normalizeIdentifier(e.toString()))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      final uids = ((data['memberUids'] as List?) ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      _ownedSessionMembers[doc.id] = _MembershipState(
        identifiers: identifiers,
        uids: uids,
      );
    }

    _sharedSessionSub = FirebaseFirestore.instance
        .collection('shared_sessions')
        .where('memberIdentifiers', arrayContains: normalized)
        .snapshots()
        .listen(
          (snapshot) {
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final sessionRaw = data['session'];
              if (sessionRaw is! Map) continue;
              final ownerId = (data['ownerIdentifier'] ?? '').toString();
              final ts = data['updatedAt'];
              final updatedAtMs = ts is Timestamp
                  ? ts.millisecondsSinceEpoch
                  : DateTime.now().millisecondsSinceEpoch;
              onRemoteSession(
                Map<String, dynamic>.from(sessionRaw),
                ownerId,
                updatedAtMs,
              );
              _setSyncedNow();
            }
          },
          onError: (Object e) {
            _lastError = e.toString();
            notifyListeners();
          },
        );
  }

  Future<CloudShareResult> shareSession({
    required String sessionId,
    required String ownerIdentifier,
    required List<String> memberIdentifiers,
    required Map<String, dynamic> sessionMap,
  }) async {
    if (!_ready || _userId == null) {
      return const CloudShareResult(
        resolvedIdentifiers: <String>[],
        unresolvedIdentifiers: <String>[],
      );
    }

    final owner = _normalizeIdentifier(ownerIdentifier);
    if (owner.isEmpty) {
      return const CloudShareResult(
        resolvedIdentifiers: <String>[],
        unresolvedIdentifiers: <String>[],
      );
    }

    final identifiers = {
      owner,
      ...memberIdentifiers.map(_normalizeIdentifier),
    }.where((id) => id.isNotEmpty).toList();

    final resolved = await _resolveIdentifiersToUids(identifiers);
    final memberUids = <String>{_userId!, ...resolved.values}.toList();

    await FirebaseFirestore.instance
        .collection('shared_sessions')
        .doc(sessionId)
        .set({
          'sessionId': sessionId,
          'ownerUid': _userId,
          'ownerIdentifier': owner,
          'memberIdentifiers': identifiers,
          'memberUids': memberUids,
          'updatedAt': FieldValue.serverTimestamp(),
          'session': sessionMap,
        }, SetOptions(merge: true));

    _ownedSessionMembers[sessionId] = _MembershipState(
      identifiers: identifiers,
      uids: memberUids,
    );
    _setSyncedNow();

    final unresolved = identifiers
        .where((id) => !resolved.containsKey(id))
        .toList();

    return CloudShareResult(
      resolvedIdentifiers: identifiers
          .where((id) => resolved.containsKey(id))
          .toList(),
      unresolvedIdentifiers: unresolved,
    );
  }

  Future<void> syncOwnedSessions({
    required String ownerIdentifier,
    required Map<String, Map<String, dynamic>> sessionsById,
  }) async {
    if (!_ready || _userId == null) return;
    final owner = _normalizeIdentifier(ownerIdentifier);
    if (owner.isEmpty) return;

    for (final entry in _ownedSessionMembers.entries) {
      final sessionMap = sessionsById[entry.key];
      if (sessionMap == null) continue;

      final identifiers = entry.value.identifiers;
      final resolved = await _resolveIdentifiersToUids(identifiers);
      final memberUids = <String>{_userId!, ...resolved.values}.toList();

      await FirebaseFirestore.instance
          .collection('shared_sessions')
          .doc(entry.key)
          .set({
            'sessionId': entry.key,
            'ownerUid': _userId,
            'ownerIdentifier': owner,
            'memberIdentifiers': identifiers,
            'memberUids': memberUids,
            'updatedAt': FieldValue.serverTimestamp(),
            'session': sessionMap,
          }, SetOptions(merge: true));

      _ownedSessionMembers[entry.key] = _MembershipState(
        identifiers: identifiers,
        uids: memberUids,
      );
    }

    if (_ownedSessionMembers.isNotEmpty) {
      _setSyncedNow();
    }
  }

  @override
  void dispose() {
    _sharedSessionSub?.cancel();
    super.dispose();
  }
}
