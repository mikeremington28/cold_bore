import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meta_app_events_service.dart';

/// Product ID must match App Store Connect exactly (case-sensitive)
const String kSubscriptionProductId = 'Coldbore_Pro_Yearly';
const List<String> kSubscriptionProductIdCandidates = <String>[
  kSubscriptionProductId,
  'ColdBore_Pro_Yearly',
  'coldbore_pro_yearly',
];
const String _entitlementPrefsKey = 'cold_bore.subscription.entitled.v1';
const String _entitlementExpiryPrefsKey = 'cold_bore.subscription.expiry_ms.v1';
const String _hadEntitlementPrefsKey =
    'cold_bore.subscription.had_entitlement.v1';
const String _lastPurchaseMsPrefsKey =
    'cold_bore.subscription.last_purchase_ms.v1';
const String _metaLoggedEventKeysPrefsKey =
  'cold_bore.subscription.meta_event_keys.v1';

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
  bool _hadEntitlementEver = false;
  DateTime? _lastPurchaseAt;
  bool _loading = false;
  bool _available = false;
  ProductDetails? _product;
  String? _lastError;
  PurchaseStatus? _lastPurchaseStatus;
  bool _testerOverride = false;
  String? _currentIdentifier;
  final Set<String> _loggedMetaEventKeys = <String>{};

  /// True while initial availability check / purchase is in progress.
  bool get loading => _loading;

  /// True when the user has an active paid/trial entitlement from Apple.
  bool get isEntitled => _entitled || _testerOverride;

  bool get hasTesterAccess => _testerOverride;

  bool get hadEntitlementEver => _hadEntitlementEver;

  DateTime? get lastPurchaseAt => _lastPurchaseAt;

  bool get isLikelyInAppleTrial {
    // The in_app_purchase API used here does not provide a reliable flag for
    // "currently in introductory trial". Fall back to Pro Active labeling.
    return false;
  }

  /// The product to display in the paywall (may be null until loaded).
  ProductDetails? get product => _product;

  /// True when the native IAP store is reachable on this device.
  bool get storeAvailable => _available;

  /// True when purchases can be attempted (store available + product loaded).
  bool get canPurchase => _available && _product != null;

  /// Set when a purchase/restore fails.
  String? get lastError => _lastError;

  PurchaseStatus? get lastPurchaseStatus => _lastPurchaseStatus;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    // Restore cached entitlement quickly so UI doesn't flash locked state.
    await _loadCachedEntitlement();
    await _loadLoggedMetaEventKeys();

    if (kIsWeb) return; // IAP not available on web.

    debugPrint(
      '[IAP] initialize() platform=${defaultTargetPlatform.name} kIsWeb=$kIsWeb kReleaseMode=$kReleaseMode requestedIds=${kSubscriptionProductIdCandidates.join(', ')}',
    );
    _available = await _iap.isAvailable();
    debugPrint('[IAP] store availability: $_available');
    if (!_available) {
      _lastError = 'Subscription store is currently unavailable.';
      notifyListeners();
      return;
    }

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

  Future<void> refreshProductDetails() async {
    if (kIsWeb) return;

    try {
      debugPrint(
        '[IAP] refreshProductDetails() platform=${defaultTargetPlatform.name} kReleaseMode=$kReleaseMode requestedIds=${kSubscriptionProductIdCandidates.join(', ')}',
      );
      _available = await _iap.isAvailable();
      debugPrint('[IAP] refresh store availability: $_available');
      if (!_available) {
        _product = null;
        _lastError = 'Subscription store is currently unavailable.';
        notifyListeners();
        return;
      }

      await _loadProduct();
    } catch (e) {
      _product = null;
      _lastError = 'Subscription store is currently unavailable.';
      debugPrint('SubscriptionService: refresh failed: $e');
      notifyListeners();
    }
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
      debugPrint(
        '[IAP] Querying product details for IDs: ${kSubscriptionProductIdCandidates.join(', ')}',
      );
      final response = await _iap.queryProductDetails(
        kSubscriptionProductIdCandidates.toSet(),
      );
      debugPrint(
        '[IAP] queryProductDetails result: found=${response.productDetails.map((p) => p.id).join(', ')}, notFound=${response.notFoundIDs.join(', ')}',
      );
      if (response.productDetails.isNotEmpty) {
        final productById = {
          for (final product in response.productDetails) product.id: product,
        };
        ProductDetails? selected;
        for (final id in kSubscriptionProductIdCandidates) {
          selected = productById[id];
          if (selected != null) break;
        }
        _product = selected ?? response.productDetails.first;
        debugPrint(
          '[IAP] Product loaded: id=${_product!.id}, title=${_product!.title}, price=${_product!.price}',
        );
        _lastError = null;
        notifyListeners();
        return;
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('[IAP] Product not found IDs: ${response.notFoundIDs.join(', ')}');
        _product = null;
        _lastError =
            'Subscription product not found in App Store (${response.notFoundIDs.join(', ')}).';
        notifyListeners();
        return;
      }

      _product = null;
      _lastError =
          'Subscription product is not available yet. Please try again shortly.';
      notifyListeners();
    } catch (e) {
      _product = null;
      debugPrint('SubscriptionService: product load failed: $e');
      _lastError = 'Subscription store is currently unavailable.';
      notifyListeners();
    }
  }

  // ── purchase ──────────────────────────────────────────────────────────────

  Future<void> purchase() async {
    debugPrint(
      '[IAP] purchase() called. entitled=$isEntitled, storeAvailable=$_available, productLoaded=${_product != null}',
    );
    try {
      _available = await _iap.isAvailable();
    } catch (_) {
      _available = false;
    }
    if (!_available) {
      _lastError = 'Subscription store is currently unavailable.';
      notifyListeners();
      return;
    }

    if (_product == null) {
      await _loadProduct();
      if (_product == null) {
        _lastError =
            'Product not available. Please refresh and try again.';
        debugPrint('[IAP] purchase() aborted: product not loaded.');
        notifyListeners();
        return;
      }
    }
    _lastError = null;
    _lastPurchaseStatus = null;
    _loading = true;
    notifyListeners();

    try {
      final param = PurchaseParam(productDetails: _product!);
      debugPrint(
        '[IAP] Launching purchase sheet with product id=${_product!.id}, title=${_product!.title}, price=${_product!.price}',
      );
      // In in_app_purchase, subscriptions are started via buyNonConsumable.
      await _iap.buyNonConsumable(purchaseParam: param);

      // Some devices deliver the entitlement update slightly after the
      // purchase flow returns, so re-sync with the store immediately.
      await restorePurchases(silent: true);

      // If the storefront is dismissed without a terminal purchase update,
      // don't leave the paywall in a perpetual loading state.
      _loading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[IAP] purchase() exception: $e');
      _lastError = 'Purchase failed. ${e.toString()}';
      _lastPurchaseStatus = PurchaseStatus.error;
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
      }
    } finally {
      if (!silent) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  // ── purchase stream handler ───────────────────────────────────────────────

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    debugPrint('[IAP] purchaseStream update count=${purchases.length}');
    for (final purchase in purchases) {
      if (!kSubscriptionProductIdCandidates.contains(purchase.productID)) {
        debugPrint('[IAP] Ignoring purchase update for productID=${purchase.productID}');
        continue;
      }

      debugPrint(
        '[IAP] Purchase update: productID=${purchase.productID}, status=${purchase.status.name}, pendingComplete=${purchase.pendingCompletePurchase}',
      );

      if (purchase.status == PurchaseStatus.pending) {
        _lastPurchaseStatus = PurchaseStatus.pending;
        _loading = true;
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        _lastPurchaseStatus = PurchaseStatus.error;
        _lastError =
            purchase.error?.message ?? 'Purchase failed. Please try again.';
        _loading = false;
        notifyListeners();
      }

      if (purchase.status == PurchaseStatus.canceled) {
        _lastPurchaseStatus = PurchaseStatus.canceled;
        _lastError = null;
        _loading = false;
        notifyListeners();
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _lastPurchaseStatus = purchase.status;
        await _grantEntitlement(purchase: purchase);
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }

    _loading = false;
    notifyListeners();
  }

  // ── entitlement persistence ───────────────────────────────────────────────

  Future<void> _grantEntitlement({PurchaseDetails? purchase}) async {
    _entitled = true;
    _hadEntitlementEver = true;
    _lastError = null;
    final purchaseAt = _parsePurchaseDate(purchase);
    if (purchaseAt != null) {
      _lastPurchaseAt = purchaseAt;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_entitlementPrefsKey, true);
    await prefs.setBool(_hadEntitlementPrefsKey, true);
    if (_lastPurchaseAt != null) {
      await prefs.setInt(
        _lastPurchaseMsPrefsKey,
        _lastPurchaseAt!.millisecondsSinceEpoch,
      );
    }
    // Store a far-future expiry; StoreKit handles actual renewal checks.
    final farFuture = DateTime.now()
        .add(const Duration(days: 400))
        .millisecondsSinceEpoch;
    await prefs.setInt(_entitlementExpiryPrefsKey, farFuture);
    if (purchase != null && purchase.status == PurchaseStatus.purchased) {
      await _logMetaSubscriptionPurchase(purchase);
    }
    notifyListeners();
  }

  Future<void> _loadCachedEntitlement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entitled = prefs.getBool(_entitlementPrefsKey) == true;
      _hadEntitlementEver = prefs.getBool(_hadEntitlementPrefsKey) == true;
      final lastPurchaseMs = prefs.getInt(_lastPurchaseMsPrefsKey);
      _lastPurchaseAt = lastPurchaseMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastPurchaseMs);
      final expiryMs = prefs.getInt(_entitlementExpiryPrefsKey);
      if (entitled && expiryMs != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
        _entitled = DateTime.now().isBefore(expiry);
      } else {
        _entitled = entitled;
      }
    } catch (_) {
      _entitled = false;
      _hadEntitlementEver = false;
      _lastPurchaseAt = null;
    }
    notifyListeners();
  }

  DateTime? _parsePurchaseDate(PurchaseDetails? purchase) {
    final raw = purchase?.transactionDate;
    if (raw == null) return null;
    final ms = int.tryParse(raw);
    if (ms == null) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadLoggedMetaEventKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _loggedMetaEventKeys
        ..clear()
        ..addAll(prefs.getStringList(_metaLoggedEventKeysPrefsKey) ?? const []);
    } catch (_) {
      _loggedMetaEventKeys.clear();
    }
  }

  Future<void> _saveLoggedMetaEventKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _metaLoggedEventKeysPrefsKey,
      _loggedMetaEventKeys.toList(),
    );
  }

  String _purchaseEventKey(PurchaseDetails purchase) {
    final purchaseId = purchase.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) return purchaseId;

    final serverVerificationData =
        purchase.verificationData.serverVerificationData.trim();
    if (serverVerificationData.isNotEmpty) return serverVerificationData;

    final localVerificationData =
        purchase.verificationData.localVerificationData.trim();
    if (localVerificationData.isNotEmpty) return localVerificationData;

    return '${purchase.productID}:${purchase.status.name}';
  }

  Future<void> _logMetaSubscriptionPurchase(PurchaseDetails purchase) async {
    final key = _purchaseEventKey(purchase);
    if (_loggedMetaEventKeys.contains(key)) return;

    _loggedMetaEventKeys.add(key);
    await _saveLoggedMetaEventKeys();

    final amount = _product?.rawPrice;
    final currency = _product?.currencyCode;
    if (amount == null || currency == null || currency.trim().isEmpty) {
      return;
    }

    final parameters = <String, dynamic>{
      'product_id': purchase.productID,
      if (purchase.purchaseID != null && purchase.purchaseID!.trim().isNotEmpty)
        'purchase_id': purchase.purchaseID!.trim(),
    };

    await MetaAppEventsService.instance.logSubscribe(
      orderId: key,
      price: amount,
      currency: currency,
      parameters: parameters,
    );
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
