import 'package:flutter/material.dart';
import '../theme.dart';
import 'purchases.dart';
import 'trial.dart';

/// The unlock screen. Shown as a hard wall when the trial has ended
/// (`dismissible: false`), or pushed as a dismissible route from the trial
/// banner so users can buy early.
class Paywall extends StatelessWidget {
  final PurchaseManager purchases;
  final bool dismissible;
  const Paywall({super.key, required this.purchases, this.dismissible = false});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: dismissible,
      child: Scaffold(
        backgroundColor: Toy.bg,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: purchases,
            builder: (context, _) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎵', style: TextStyle(fontSize: 64)),
                    const SizedBox(height: 16),
                    Text(dismissible ? 'Unlock Emojio' : 'Your free trial has ended',
                        textAlign: TextAlign.center, style: Toy.label(15)),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: toyBox(fill: Toy.panel),
                      child: Column(
                        children: const [
                          _Bullet('🎹', 'Every emoji voice & instrument'),
                          _Bullet('💾', 'Save unlimited songs on your iPad'),
                          _Bullet('♾️', 'Pay once — yours forever'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (purchases.purchasePending)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      )
                    else
                      ToyButton(
                        label: purchases.priceLabel.isEmpty
                            ? 'Unlock Forever'
                            : 'Unlock Forever · ${purchases.priceLabel}',
                        emoji: '🔓',
                        color: Toy.green,
                        fontSize: 11,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        onPressed: purchases.product == null ? null : purchases.buy,
                      ),
                    const SizedBox(height: 12),
                    ToyButton(
                      label: 'Restore Purchase',
                      color: Colors.white,
                      textColor: Toy.text,
                      onPressed: purchases.restore,
                    ),
                    if (dismissible) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text('Maybe later', style: Toy.label(8, Toy.text)),
                      ),
                    ],
                    if (purchases.product == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'Product not configured yet.\nCreate "${PurchaseManager.productId}"\n(non-consumable) in App Store Connect.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, color: Colors.black45),
                        ),
                      ),
                    if (purchases.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(purchases.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10, color: Toy.red)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String emoji;
  final String text;
  const _Bullet(this.emoji, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Toy.label(8).copyWith(height: 1.5))),
          ],
        ),
      );
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
