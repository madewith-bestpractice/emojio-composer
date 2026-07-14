import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../theme.dart';
import 'trial.dart';

/// Hard-wall paywall shown when the trial has ended. Its content — hero image,
/// title, feature bullets, price and buttons — is configured in the RevenueCat
/// dashboard (the current offering's paywall), NOT in Dart. When the user buys
/// or restores, [PurchaseManager]'s customer-info listener flips `unlocked` and
/// the app tree rebuilds away from this screen automatically.
class RcPaywall extends StatelessWidget {
  const RcPaywall({super.key});

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false, // trial's over — no way past it but to buy/restore
        child: Scaffold(
          backgroundColor: Toy.bg,
          body: PaywallView(displayCloseButton: false),
        ),
      );
}

/// Presents the RevenueCat paywall as a dismissible modal — used from the trial
/// banner so users can buy before the trial ends. Gated on [Purchases.isConfigured]:
/// presenting before the SDK is configured trips a native `Purchases.shared`
/// assertion (SIGTRAP) that a Dart try/catch can't catch, so we no-op instead.
Future<void> presentEmojioPaywall() async {
  if (!await Purchases.isConfigured) return;
  await RevenueCatUI.presentPaywall(displayCloseButton: true);
}

/// Opens the RevenueCat Customer Center (restore purchases, manage the unlock,
/// contact support). Makes sense to keep reachable even after unlocking. Gated
/// on [Purchases.isConfigured] for the same native-assertion reason as above.
Future<void> presentEmojioCustomerCenter() async {
  if (!await Purchases.isConfigured) return;
  await RevenueCatUI.presentCustomerCenter();
}

/// Slim banner shown during the trial (when not yet unlocked). Tapping opens
/// the paywall so users can buy before the trial ends.
class TrialBanner extends StatelessWidget {
  final TrialManager trial;
  final VoidCallback onTap;
  const TrialBanner({super.key, required this.trial, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = trial.daysLeft;
    return Material(
      color: Toy.highlight,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Free trial — $d ${d == 1 ? "day" : "days"} left',
                    style: Toy.label(8)),
              ),
              Text('UNLOCK ▸', style: Toy.label(8, Toy.accent)),
            ],
          ),
        ),
      ),
    );
  }
}
