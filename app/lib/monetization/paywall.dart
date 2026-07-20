import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../theme.dart';
import 'purchases.dart';
import 'trial.dart';

/// Hard-wall paywall shown when the trial has ended. Prefers the RevenueCat
/// dashboard paywall (hero, bullets, price, buttons all configured there), but
/// that renders nothing when the offering holds no purchasable package. Behind
/// `canPop: false` an empty render strands the user on a blank screen with no
/// way forward, so fall back to our own sheet, which always draws a button and
/// the reason it can't be used.
class RcPaywall extends StatelessWidget {
  final PurchaseManager purchases;
  const RcPaywall({super.key, required this.purchases});

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false, // trial's over — no way past it but to buy/restore
        child: Scaffold(
          backgroundColor: Toy.bg,
          body: purchases.canBuy
              ? PaywallView(displayCloseButton: false)
              : UnlockSheet(purchases: purchases),
        ),
      );
}

/// Emojio's own unlock screen, used whenever the RevenueCat paywall can't be
/// shown. It always renders *something*: a real buy button when a product
/// loaded, and the underlying error plus a retry when one didn't — so a failed
/// product load reads as a diagnosable message instead of a dead tap.
///
/// [onClose] null means this is the hard wall and there's no way out but to
/// buy or restore.
class UnlockSheet extends StatefulWidget {
  final PurchaseManager purchases;
  final VoidCallback? onClose;
  const UnlockSheet({super.key, required this.purchases, this.onClose});

  @override
  State<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<UnlockSheet> {
  PurchaseManager get _p => widget.purchases;

  @override
  void initState() {
    super.initState();
    _p.addListener(_onChange);
  }

  @override
  void dispose() {
    _p.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    // Bought or restored from this sheet — dismiss so the app tree behind it
    // rebuilds into the composer.
    if (_p.unlocked && widget.onClose != null) widget.onClose!();
  }

  @override
  Widget build(BuildContext context) {
    final price = _p.priceLabel;
    return Container(
      color: Toy.bg,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔓', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('EMOJIO LIFETIME UNLOCK',
                textAlign: TextAlign.center, style: Toy.label(13)),
            const SizedBox(height: 12),
            Text('All features, no subscriptions.',
                textAlign: TextAlign.center, style: Toy.label(9)),
            const SizedBox(height: 22),
            if (_p.purchasePending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CircularProgressIndicator(color: Toy.accent),
              )
            else
              ToyButton(
                label: price.isEmpty ? 'Unlock Forever' : 'Unlock — $price',
                emoji: '✨',
                color: Toy.accent,
                fontSize: 11,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                // Null when no product loaded: the button greys out rather than
                // throwing the user into a purchase that can't start.
                onPressed: _p.canBuy ? _p.buy : null,
              ),
            const SizedBox(height: 14),
            ToyButton(
              label: 'Restore Purchase',
              emoji: '♻️',
              color: Colors.white,
              textColor: Toy.text,
              fontSize: 9,
              onPressed: _p.restore,
            ),
            // No product loaded — say so plainly and offer a retry. This is the
            // state that previously rendered nothing.
            if (!_p.canBuy) ...[
              const SizedBox(height: 20),
              Text(
                "Purchases aren't available right now.\n"
                'Please try again in a moment.',
                textAlign: TextAlign.center,
                style: Toy.label(8),
              ),
              const SizedBox(height: 12),
              ToyButton(
                label: 'Try Again',
                emoji: '🔄',
                color: Toy.highlight,
                textColor: Toy.text,
                fontSize: 9,
                onPressed: _p.reload,
              ),
            ]
            // A product loaded but the last purchase or restore failed. One
            // short, human line — never the raw platform exception, which reads
            // as a crash to a user (or a reviewer).
            else if (_p.error != null) ...[
              const SizedBox(height: 18),
              Text("That didn't go through. Please try again.",
                  textAlign: TextAlign.center, style: Toy.label(8, Toy.red)),
            ],
            // Developers still get the underlying error to diagnose with; it is
            // compiled out of release builds, so users and reviewers never see
            // it.
            if (kDebugMode && _p.error != null) ...[
              const SizedBox(height: 12),
              Text(_p.error!,
                  textAlign: TextAlign.center, style: Toy.label(6, Toy.line)),
            ],
            if (widget.onClose != null) ...[
              const SizedBox(height: 22),
              TextButton(
                onPressed: widget.onClose,
                child: Text('Not now', style: Toy.label(9)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the purchase flow. Prefers RevenueCat's hosted paywall and falls back
/// to [UnlockSheet] when it can't be used — the SDK isn't configured, no
/// product loaded, or the native presentation returned an error. Every path
/// ends with something on screen; none of them no-op.
Future<void> presentEmojioPaywall(
    BuildContext context, PurchaseManager purchases) async {
  // Presenting before configure() trips a native `Purchases.shared` assertion
  // (SIGTRAP) that a Dart try/catch can't catch, so gate on it.
  final configured = await Purchases.isConfigured;
  // One retry: the offering may have failed to load at boot (e.g. offline
  // launch) and since recovered.
  if (configured && !purchases.canBuy) await purchases.reload();

  if (configured && purchases.canBuy) {
    final result = await RevenueCatUI.presentPaywall(displayCloseButton: true);
    if (result != PaywallResult.error) return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Toy.bg,
    isScrollControlled: true,
    builder: (sheetContext) => UnlockSheet(
      purchases: purchases,
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

/// Opens the RevenueCat Customer Center (restore, manage the unlock, contact
/// support). Falls back to [UnlockSheet], which carries its own Restore button,
/// so restoring is always reachable — Guideline 3.1.1 requires it for a
/// non-consumable.
Future<void> presentEmojioCustomerCenter(
    BuildContext context, PurchaseManager purchases) async {
  if (await Purchases.isConfigured) {
    await RevenueCatUI.presentCustomerCenter();
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Toy.bg,
    isScrollControlled: true,
    builder: (sheetContext) => UnlockSheet(
      purchases: purchases,
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

/// Slim banner shown during the trial (when not yet unlocked). Carries a real
/// [ToyButton] rather than bare text: styled as a flat ribbon it read as a
/// status strip, and App Review couldn't find the purchase behind it.
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Free trial — $d ${d == 1 ? "day" : "days"} left',
                    style: Toy.label(9)),
              ),
              ToyButton(
                label: 'Unlock',
                color: Toy.accent,
                fontSize: 9,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                onPressed: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
