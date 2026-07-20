import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

/// Emojio's one-time "lifetime" unlock, via RevenueCat (`purchases_flutter`).
///
/// RevenueCat sits on top of the same App Store / Play product — it does NOT
/// replace the store IAP. Dashboard setup (once):
///   1. Products    → add your App Store product `emojio.unlock_forever`
///                    (+ the Play product later).
///   2. Entitlements→ create one with identifier [entitlementId] and attach
///                    the product to it.
///   3. Offerings   → create an offering (e.g. "default") with a **lifetime**
///                    package pointing to that product.
///
/// Entitlement state is checked from [CustomerInfo]; RevenueCat caches it
/// locally, so the launch gate is instant and works offline.
class PurchaseManager extends ChangeNotifier {
  /// RevenueCat PUBLIC SDK keys — designed to be embedded in the app binary.
  /// Platform-specific: the Apple key serves iOS + macOS, the Google key
  /// serves Android. (From RevenueCat → Project settings → API keys.)
  static const String _appleApiKey = 'appl_JadovrJqnnwnZGlfdTzOCaimYOw';
  static const String _googleApiKey = 'goog_SyBSDZbIchuFAXDAwSDejqxONLx';
  static String get _apiKey => Platform.isAndroid ? _googleApiKey : _appleApiKey;

  /// MUST exactly match the Entitlement *identifier* in the RevenueCat
  /// dashboard (case- and space-sensitive).
  static const String entitlementId = 'Emojio Genius';

  /// The lifetime package identifier in the offering (diagnostics / hints).
  static const String productId = 'lifetime';

  bool available = false;
  bool unlocked = false;
  bool purchasePending = false;
  Package? product; // the lifetime package from the current offering
  String? error;

  String get priceLabel => product?.storeProduct.priceString ?? '';

  /// True once we hold a package the store will actually sell. False means the
  /// offering never loaded — no agreement, no network, product not yet live —
  /// and every purchase surface must say so rather than render empty.
  bool get canBuy => product != null;

  /// Re-fetches the current offering, so a transient load failure isn't
  /// permanent and the unlock sheet can offer a retry.
  Future<void> reload() async {
    error = null;
    if (!available) return;
    await _loadOffering();
    notifyListeners();
  }

  Future<void> init() async {
    try {
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      available = true;
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _apply(await Purchases.getCustomerInfo()); // cached → instant, offline-safe
      await _loadOffering();
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> _loadOffering() async {
    try {
      final current = (await Purchases.getOfferings()).current;
      if (current == null) return;
      product = current.lifetime ??
          (current.availablePackages.isNotEmpty
              ? current.availablePackages.first
              : null);
    } catch (e) {
      error = '$e';
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    _apply(info);
    notifyListeners();
  }

  void _apply(CustomerInfo info) {
    unlocked = info.entitlements.active.containsKey(entitlementId);
  }

  /// Buy the lifetime unlock. Silently ignores user cancellation; surfaces real
  /// failures in [error].
  Future<void> buy() async {
    final p = product;
    if (p == null) {
      error = 'Product unavailable';
      notifyListeners();
      return;
    }
    error = null;
    purchasePending = true;
    notifyListeners();
    try {
      final result = await Purchases.purchase(PurchaseParams.package(p));
      _apply(result.customerInfo);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) !=
          PurchasesErrorCode.purchaseCancelledError) {
        error = e.message;
      }
    } catch (e) {
      error = '$e';
    } finally {
      purchasePending = false;
      notifyListeners();
    }
  }

  /// Replays past purchases so the entitlement survives reinstall / new device.
  Future<void> restore() async {
    error = null;
    try {
      _apply(await Purchases.restorePurchases());
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    super.dispose();
  }
}
