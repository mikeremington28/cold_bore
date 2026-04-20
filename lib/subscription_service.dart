import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kSubscriptionProductId = 'Coldbore_Pro_Yearly';
const String _entitlementPrefsKey = 'cold_bore.subscription.entitled.v1';
const String _entitlementExpiryPrefsKey = 'cold_bore.subscription.expiry_ms.v1';
const String _trialStartPrefsKey = 'cold_bore.subscription.trial_start_ms.v1';
const int _trialDays = 30;

/// Lightweight subscription service.
///
/// Call [initialize] once at app start. Listen to [statusStream] for changes.
/// Check [isEntitled] before allowing write actions.
class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;
  SubscriptionService._();

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _entitled = false;
  DateTime? _trialEndsAt;
  bool _loading = false;
  bool _available = false;
  ProductDetails? _product;
  String? _lastError;
  bool _testerOverride = false;
  String? _currentIdentifier;

  /// True while initial availability check / purchase is in progress.
  bool get loading => _loading;

  /// True when the user has an active subscription or is in their free trial.
  bool get isEntitled => _entitled || _isTrialActive || _testerOverride;

  bool get hasTesterAccess => _testerOverride;

  bool get _isTrialActive =>
      _trialEndsAt != null && DateTime.now().isBefore(_trialEndsAt!);

  DateTime? get trialEndsAt => _trialEndsAt;

  int get trialDaysRemaining {
    if (!_isTrialActive || _trialEndsAt == null) return 0;
    final remaining = _trialEndsAt!.difference(DateTime.now()).inDays + 1;
    return remaining.clamp(0, _trialDays);
  }

  /// The product to display in the paywall (may be null until loaded).
  ProductDetails? get product => _product;

  /// Set when a purchase/restore fails.
  String? get lastError => _lastError;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    // Restore cached entitlement quickly so UI doesn't flash locked state.
    await _loadCachedEntitlement();
    await _loadOrStartTrial();

    if (kIsWeb) return; // IAP not available on web.

    _available = await _iap.isAvailable();
    if (!_available) return;

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        _lastError = e.toString();
        notifyListeners();
      },
    );

    await _loadProduct();
    await restorePurchases(silent: true);
  }

  Future<void> setCurrentUserIdentifier(String? identifier) async {
    final normalized = identifier?.trim().toUpperCase();
    final nextIdentifier = (normalized == null || normalized.isEmpty)
        ? null
        : normalized;
    if (_currentIdentifier == nextIdentifier) return;

    _currentIdentifier = nextIdentifier;
    await _refreshTesterOverride();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  // ── product loading ───────────────────────────────────────────────────────

  Future<void> _loadProduct() async {
    try {
      final response = await _iap.queryProductDetails({kSubscriptionProductId});
      if (response.productDetails.isNotEmpty) {
        _product = response.productDetails.first;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('SubscriptionService: product load failed: $e');
    }
  }

  // ── purchase ──────────────────────────────────────────────────────────────

  Future<void> purchase() async {
    if (_product == null) {
      _lastError = 'Product not available. Please try again.';
      notifyListeners();
      return;
    }
    _lastError = null;
    _loading = true;
    notifyListeners();

    try {
      final param = PurchaseParam(productDetails: _product!);
      // Subscriptions always use buyNonConsumable on iOS.
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      _lastError = 'Purchase failed. Please try again.';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> restorePurchases({bool silent = false}) async {
    if (!_available) return;
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      await _iap.restorePurchases();
    } catch (e) {
      if (!silent) {
        _lastError = 'Restore failed. Please try again.';
        _loading = false;
        notifyListeners();
      }
    }
  }

  // ── purchase stream handler ───────────────────────────────────────────────

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != kSubscriptionProductId) continue;

      if (purchase.status == PurchaseStatus.pending) {
        _loading = true;
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        _lastError =
            purchase.error?.message ?? 'Purchase failed. Please try again.';
        _loading = false;
        notifyListeners();
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _grantEntitlement();
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }

    _loading = false;
    notifyListeners();
  }

  // ── entitlement persistence ───────────────────────────────────────────────

  Future<void> _grantEntitlement() async {
    _entitled = true;
    _lastError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_entitlementPrefsKey, true);
    // Store a far-future expiry; StoreKit handles actual renewal checks.
    final farFuture = DateTime.now()
        .add(const Duration(days: 400))
        .millisecondsSinceEpoch;
    await prefs.setInt(_entitlementExpiryPrefsKey, farFuture);
    notifyListeners();
  }

  Future<void> _loadCachedEntitlement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entitled = prefs.getBool(_entitlementPrefsKey) == true;
      final expiryMs = prefs.getInt(_entitlementExpiryPrefsKey);
      if (entitled && expiryMs != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
        _entitled = DateTime.now().isBefore(expiry);
      } else {
        _entitled = entitled;
      }
    } catch (_) {
      _entitled = false;
    }
    notifyListeners();
  }

  Future<void> _loadOrStartTrial() async {
    // On iOS, rely on App Store introductory offer eligibility (Apple ID based)
    // instead of local trial storage that can be reset by reinstall.
    if (!kIsWeb && Platform.isIOS) {
      _trialEndsAt = null;
      notifyListeners();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      var startMs = prefs.getInt(_trialStartPrefsKey);
      if (startMs == null) {
        startMs = DateTime.now().millisecondsSinceEpoch;
        await prefs.setInt(_trialStartPrefsKey, startMs);
      }
      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      _trialEndsAt = start.add(const Duration(days: _trialDays));
    } catch (_) {
      _trialEndsAt = null;
    }
    notifyListeners();
  }

  Future<void> _refreshTesterOverride() async {
    final identifier = _currentIdentifier;
    if (identifier == null) {
      if (_testerOverride) {
        _testerOverride = false;
        notifyListeners();
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('tester_access')
          .doc(identifier)
          .get();
      final enabled = doc.exists && doc.data()?['enabled'] == true;
      if (_testerOverride != enabled) {
        _testerOverride = enabled;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('SubscriptionService tester access lookup failed: $e');
      if (_testerOverride) {
        _testerOverride = false;
        notifyListeners();
      }
    }
  }

  /// Call on iOS foreground resume to re-verify via restore (silent).
  Future<void> refreshOnResume() async {
    if (!kIsWeb && Platform.isIOS) {
      await restorePurchases(silent: true);
    }
    await _refreshTesterOverride();
  }
}
