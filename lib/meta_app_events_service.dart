import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';

class MetaAppEventsService {
  MetaAppEventsService._();

  static final MetaAppEventsService instance = MetaAppEventsService._();

  final FacebookAppEvents _events = FacebookAppEvents();
  bool _configured = false;
  bool _activateLoggedForForeground = false;

  Future<void> bootstrap() async {
    await _configureOnce();
    await logAppActivated();
  }

  Future<void> onAppForegrounded() async {
    _activateLoggedForForeground = false;
    await _applyTrackingSettings();
    await logAppActivated();
  }

  void onAppBackgrounded() {
    _activateLoggedForForeground = false;
  }

  Future<void> logTrialStarted({
    required String orderId,
    double? price,
    String? currency,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      await _events.logStartTrial(
        orderId: orderId,
        price: price,
        currency: currency,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('MetaAppEventsService.logTrialStarted failed: $e');
    }
  }

  Future<void> logSubscribe({
    required String orderId,
    double? price,
    String? currency,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      await _events.logSubscribe(
        orderId: orderId,
        price: price,
        currency: currency,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('MetaAppEventsService.logSubscribe failed: $e');
    }
  }

  Future<void> logPurchase({
    required double amount,
    required String currency,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      await _events.logPurchase(
        amount: amount,
        currency: currency,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('MetaAppEventsService.logPurchase failed: $e');
    }
  }

  Future<void> _configureOnce() async {
    if (_configured) return;
    _configured = true;

    await _events.setAutoLogAppEventsEnabled(true);
    await _applyTrackingSettings();
  }

  Future<void> _applyTrackingSettings() async {
    await _events.setAdvertiserTracking(
      enabled: false,
      collectId: false,
    );
  }

  Future<void> logAppActivated() async {
    if (_activateLoggedForForeground) return;
    _activateLoggedForForeground = true;

    try {
      await _events.activateApp();
    } catch (e) {
      debugPrint('MetaAppEventsService.logAppActivated failed: $e');
    }
  }
}