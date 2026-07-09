import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Wraps the single non-consumable "unlock forever" IAP via the official
/// in_app_purchase plugin (StoreKit 2 on iOS/macOS).
///
/// SETUP REQUIRED: create a non-consumable product with id [productId] in App
/// Store Connect. Until then [available] is true but [product] stays null.
///
/// Non-consumables auto-restore through `restorePurchases()` (which replays
/// past purchases on the stream), so entitlement survives reinstall / new
/// device. We also cache the unlocked flag in the Keychain for instant,
/// offline gating on launch.
class PurchaseManager extends ChangeNotifier {
  static const String productId = 'com.madewithbestpractice.emojio.unlock_forever';
  static const _cacheKey = 'emojio.unlocked';

  final InAppPurchase _iap = InAppPurchase.instance;
  final FlutterSecureStorage _store;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  bool unlocked = false;
  bool purchasePending = false;
  ProductDetails? product;
  String? error;

  PurchaseManager([FlutterSecureStorage? store]) : _store = store ?? const FlutterSecureStorage();

  String get priceLabel => product?.price ?? '';

  Future<void> init() async {
    // Instant offline gate from the cached flag.
    unlocked = (await _store.read(key: _cacheKey)) == '1';
    notifyListeners();

    available = await _iap.isAvailable();
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      error = '$e';
      notifyListeners();
    });

    if (available) {
      final resp = await _iap.queryProductDetails({productId});
      if (resp.productDetails.isNotEmpty) product = resp.productDetails.first;
      // Replays owned non-consumables onto the stream -> _onPurchases.
      await _iap.restorePurchases();
    }
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) {
        purchasePending = true;
      } else {
        purchasePending = false;
        if (p.status == PurchaseStatus.error) {
          error = p.error?.message;
        } else if (p.productID == productId &&
            (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored)) {
          unlocked = true;
          await _store.write(key: _cacheKey, value: '1');
        }
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      }
    }
    notifyListeners();
  }

  Future<void> buy() async {
    if (product == null) {
      error = 'Product unavailable';
      notifyListeners();
      return;
    }
    error = null;
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product!));
  }

  Future<void> restore() async {
    error = null;
    await _iap.restorePurchases();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
