import 'dart:async';

import 'package:emojio/monetization/purchases.dart';

/// What the next buy() does, standing in for the store's answer.
enum BuyOutcome { success, cancel, pending, fail, hang }

/// A [PurchaseManager] that never touches RevenueCat: tests set what the store
/// "has" and how it answers, then drive the paywall like a user would.
class FakePurchaseManager extends PurchaseManager {
  FakePurchaseManager({
    this.sellable = true,
    this.price = r'$4.99',
    this.buyOutcome = BuyOutcome.success,
    this.ownedOnStore = false,
    this.reloadMakesSellable = false,
  }) {
    available = true;
  }

  bool sellable;
  String price;
  BuyOutcome buyOutcome;
  bool ownedOnStore;
  bool reloadMakesSellable;
  int buys = 0, restores = 0, reloads = 0;
  Completer<void>? hang;

  @override
  bool get canBuy => sellable;

  @override
  String get priceLabel => sellable ? price : '';

  @override
  Future<void> reload() async {
    reloads++;
    if (reloadMakesSellable) sellable = true;
    notifyListeners();
  }

  @override
  Future<void> buy() async {
    buys++;
    error = null;
    purchasePending = true;
    notifyListeners();
    switch (buyOutcome) {
      case BuyOutcome.success:
        unlocked = true;
      case BuyOutcome.cancel:
        break;
      case BuyOutcome.pending:
        awaitingApproval = true;
      case BuyOutcome.fail:
        error = 'store said no';
      case BuyOutcome.hang:
        hang = Completer<void>();
        await hang!.future;
    }
    purchasePending = false;
    notifyListeners();
  }

  @override
  Future<void> restore() async {
    restores++;
    notice = null;
    unlocked = ownedOnStore;
    if (!unlocked) {
      notice = 'No earlier purchase was found for this store account.';
    }
    notifyListeners();
  }

  /// The customer-info listener firing, e.g. an Ask to Buy approval landing.
  void grant() {
    unlocked = true;
    awaitingApproval = false;
    notifyListeners();
  }
}
