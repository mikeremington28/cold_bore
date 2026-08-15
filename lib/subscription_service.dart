import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

const String kSubscriptionProductId = 'Coldbore_Pro_Yearly';
const String _entitlementPrefsKey = 'cold_bore.subscription.entitled_hint.v1';
const String _hadEntitlementPrefsKey =
    'cold_bore.subscription.had_entitlement.v1';
const String _forceLockedPrefsKey =
    'cold_bore.subscription.force_locked_for_testing.v1';
const MethodChannel _subscriptionChannel = MethodChannel(
  'com.remington.coldbore/subscription',
);

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;
  SubscriptionService._();

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Completer<bool>? _pendingEntitlementWait;

  ProductDetails? _product;
  bool _storeAvailable = false;
  bool _isEntitled = false;
  bool _loading = false;
  bool _purchasing = false;
  bool _restoring = false;
  bool _hadEntitlementEver = false;
  bool _initialized = false;
  String? _lastError;
  String _lastPurchaseStatus = 'idle';
  String _lastRestoreStatus = 'idle';
  DateTime? _lastRefreshAt;

  static const Duration _waitTimeout = Duration(seconds: 10);

  bool get isEntitled => _isEntitled;
  bool get loading => _loading;
  bool get purchasing => _purchasing;
  bool get restoring => _restoring;
  bool get hadEntitlementEver => _hadEntitlementEver;
  bool get forceLockedForTesting => false;
  bool get realAppleEntitlementActive => _isEntitled;
  String? get lastError => _lastError;

  ProductDetails? get product => _product;
  bool get storeAvailable => _storeAvailable;
  bool get canPurchase => _storeAvailable && _product != null;
  String get lastPurchaseStatus => _lastPurchaseStatus;
  String get lastRestoreStatus => _lastRestoreStatus;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _loadLocalFlags();

    if (kIsWeb) {
      notifyListeners();
      return;
    }

    _ensurePurchaseListener();
    await refresh();

    // Validate any cached entitlement in the background. Do not block startup or
    // normal writing on StoreKit restore timing; purchase stream events will
    // grant entitlement when Apple responds.
    unawaited(_restoreInternal(silent: true, reason: 'startup_validation'));
  }

  void _ensurePurchaseListener() {
    if (kIsWeb) return;
    _purchaseSub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        _lastError = e.toString();
        _lastPurchaseStatus = 'error';
        _lastRestoreStatus = 'error';
        _completePendingWait(false);
        notifyListeners();
      },
    );
  }

  Future<void> refresh() async {
    if (kIsWeb) return;
    _ensurePurchaseListener();

    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < const Duration(seconds: 10) &&
        !_restoring &&
        !_purchasing) {
      return;
    }

    _lastRefreshAt = now;
    _loading = true;
    _lastError = null;
    notifyListeners();

    try {
      _storeAvailable = await _iap.isAvailable();
      if (!_storeAvailable) {
        _product = null;
        _lastError = 'Subscription store is currently unavailable.';
        return;
      }

      final response = await _iap.queryProductDetails({kSubscriptionProductId});
      if (response.error != null) {
        _product = null;
        _lastError = response.error!.message;
        return;
      }

      if (response.productDetails.isEmpty) {
        _product = null;
        _lastError =
            'Subscription product not found in App Store ($kSubscriptionProductId).';
        return;
      }

      ProductDetails? foundProduct;
      for (final product in response.productDetails) {
        if (product.id == kSubscriptionProductId) {
          foundProduct = product;
          break;
        }
      }

      _product = foundProduct;
      if (_product == null) {
        _lastError =
            'Subscription product not found in App Store ($kSubscriptionProductId).';
        return;
      }

      final appleEntitlement = await _readAppleEntitlement();
      if (appleEntitlement != null) {
        await _applyAppleEntitlement(appleEntitlement);
      }
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loading = _purchasing || _restoring;
      notifyListeners();
    }
  }

  Future<bool> purchase() async {
    if (kIsWeb) return false;
    _ensurePurchaseListener();
    if (_purchasing) return false;

    _purchasing = true;
    _loading = true;
    _lastError = null;
    _lastPurchaseStatus = 'starting';
    notifyListeners();

    try {
      if (!_storeAvailable || _product == null) {
        await refresh();
      }

      if (!_storeAvailable || _product == null) {
        _lastPurchaseStatus = 'error';
        _lastError =
            'Subscription is temporarily unavailable. Please try again.';
        return false;
      }

      debugPrint(
        '[IAP] Start trial tapped product=${_product!.id} price=${_product!.price}',
      );
      final wait = _beginEntitlementWait();
      final param = PurchaseParam(productDetails: _product!);
      _lastPurchaseStatus = 'calling_purchase';
      await _iap.buyNonConsumable(purchaseParam: param);

      var unlocked = await wait;
      if (!unlocked && !kIsWeb && Platform.isIOS) {
        debugPrint(
          '[IAP] purchase returned without entitlement, running restore fallback',
        );
        unlocked = await _restoreInternal(
          silent: true,
          reason: 'purchase_fallback',
        );
      }

      if (unlocked) {
        _lastPurchaseStatus = 'purchased';
      } else if (_lastPurchaseStatus != 'canceled' &&
          _lastPurchaseStatus != 'error') {
        _lastPurchaseStatus = 'no_entitlement';
      }
      return unlocked;
    } catch (e) {
      _lastError = e.toString();
      _lastPurchaseStatus = 'error';
      _completePendingWait(false);
      if (!kIsWeb && Platform.isIOS) {
        return _restoreInternal(silent: true, reason: 'purchase_error_restore');
      }
      return false;
    } finally {
      _purchasing = false;
      _loading = _restoring;
      notifyListeners();
    }
  }

  Future<bool> restorePurchases() async {
    return _restoreInternal(silent: false, reason: 'manual_restore');
  }

  Future<bool> _restoreInternal({
    required bool silent,
    required String reason,
  }) async {
    if (kIsWeb) return false;
    _ensurePurchaseListener();
    if (_restoring) return false;

    _restoring = true;
    _loading = true;
    _lastError = null;
    _lastRestoreStatus = 'starting';
    notifyListeners();

    try {
      _storeAvailable = await _iap.isAvailable();
      if (!_storeAvailable) {
        _lastRestoreStatus = 'store_unavailable';
        _lastError = silent
            ? _lastError
            : 'Subscription store is currently unavailable.';
        return false;
      }

      final wait = _beginEntitlementWait();
      debugPrint('[IAP] restorePurchases called reason=$reason');
      await _iap.restorePurchases();
      final restored = await wait;

      if (restored) {
        _lastRestoreStatus = 'restored';
      } else {
        // A restore timeout/no-event is not proof of expiration. Keep any
        // current in-memory entitlement and let future StoreKit events update it.
        _lastRestoreStatus = 'not_found';
      }
      return restored;
    } catch (e) {
      _lastRestoreStatus = 'error';
      _lastError = e.toString();
      _completePendingWait(false);
      return false;
    } finally {
      _restoring = false;
      _loading = _purchasing;
      notifyListeners();
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      debugPrint(
        '[IAP] stream product=${purchase.productID} status=${purchase.status.name} '
        'error=${purchase.error?.code ?? '-'}:${purchase.error?.message ?? '-'} '
        'pendingComplete=${purchase.pendingCompletePurchase}',
      );

      if (purchase.productID != kSubscriptionProductId) {
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          _lastPurchaseStatus = 'pending';
          break;
        case PurchaseStatus.purchased:
          _lastPurchaseStatus = 'purchased';
          _lastRestoreStatus = 'restored';
          await _grantEntitlement();
          _completePendingWait(true);
          break;
        case PurchaseStatus.restored:
          _lastPurchaseStatus = 'restored';
          _lastRestoreStatus = 'restored';
          await _grantEntitlement();
          _completePendingWait(true);
          break;
        case PurchaseStatus.error:
          _lastPurchaseStatus = 'error';
          _lastRestoreStatus = 'error';
          _lastError = purchase.error?.message ?? 'Purchase failed.';
          _completePendingWait(false);
          break;
        case PurchaseStatus.canceled:
          _lastPurchaseStatus = 'canceled';
          _lastError = 'Purchase canceled.';
          _completePendingWait(false);
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }

    _loading = _purchasing || _restoring;
    notifyListeners();
  }

  Future<void> _grantEntitlement() async {
    _isEntitled = true;
    _hadEntitlementEver = true;
    _lastError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_entitlementPrefsKey, true);
    await prefs.setBool(_hadEntitlementPrefsKey, true);
    notifyListeners();
  }

  Future<bool?> _readAppleEntitlement() async {
    if (kIsWeb || !Platform.isIOS) return null;
    try {
      return await _subscriptionChannel.invokeMethod<bool>(
        'currentEntitlement',
        <String, dynamic>{'productId': kSubscriptionProductId},
      );
    } catch (e) {
      debugPrint('[IAP] Current entitlement check unavailable: $e');
      return null;
    }
  }

  Future<void> _applyAppleEntitlement(bool entitled) async {
    _isEntitled = entitled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_entitlementPrefsKey, entitled);
    if (entitled) {
      _hadEntitlementEver = true;
      await prefs.setBool(_hadEntitlementPrefsKey, true);
    }
    notifyListeners();
  }

  Future<void> _loadLocalFlags() async {
    final prefs = await SharedPreferences.getInstance();
    _hadEntitlementEver = prefs.getBool(_hadEntitlementPrefsKey) == true;
    // This is only a local startup hint so active users do not get re-paywalled
    // on every launch. StoreKit purchase/restore events remain the source that
    // grants this flag, and startup/resume validation runs in the background.
    _isEntitled = prefs.getBool(_entitlementPrefsKey) == true;
    // Force-lock testing is disabled in this build. Clear any stuck local
    // override so real Apple entitlement controls access again.
    await prefs.setBool(_forceLockedPrefsKey, false);
  }

  Future<void> setForceLockedForTesting(bool value) async {
    // Force-lock testing is disabled in this build. Always clear the local
    // override so it cannot block a valid Apple entitlement.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_forceLockedPrefsKey, false);
    notifyListeners();
  }

  Future<void> clearForceLockedForTesting() async {
    await setForceLockedForTesting(false);
  }

  Future<bool> _beginEntitlementWait() async {
    final pending = _pendingEntitlementWait ??= Completer<bool>();
    try {
      return await pending.future.timeout(
        _waitTimeout,
        onTimeout: () {
          _completePendingWait(false);
          return false;
        },
      );
    } finally {
      if (identical(_pendingEntitlementWait, pending)) {
        _pendingEntitlementWait = null;
      }
    }
  }

  void _completePendingWait(bool value) {
    final pending = _pendingEntitlementWait;
    if (pending != null && !pending.isCompleted) {
      pending.complete(value);
    }
    _pendingEntitlementWait = null;
  }

  Future<void> refreshOnResume() async {
    await initialize();
    await refresh();
    if (!kIsWeb && Platform.isIOS) {
      unawaited(_restoreInternal(silent: true, reason: 'resume_validation'));
    }
  }

  Future<void> refreshProductDetails() async {
    await initialize();
    await refresh();
  }

  Future<void> setCurrentUserIdentifier(String? identifier) async {
    // Intentionally unused in Apple-entitlement subscription logic.
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _purchaseSub = null;
    super.dispose();
  }
}
