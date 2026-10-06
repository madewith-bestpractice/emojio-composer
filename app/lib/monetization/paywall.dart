import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../theme.dart';
import 'access.dart';
import 'purchases.dart';
import 'trial.dart';

/// Emojio's own Premium sheet. It names the feature that opened it (when there
/// is one), lists everything Premium adds, and always renders *something*: a
/// real buy button when a product loaded, and a plain message plus a retry when
/// one didn't — so a failed product load never reads as a dead tap.
///
/// The copy speaks to the grown-up holding the iPad: the sheet usually opens
/// because a child tapped a locked sticker.
class UnlockSheet extends StatefulWidget {
  final PurchaseManager purchases;
  final VoidCallback onClose;

  /// The locked feature the user just reached for, or null when they opened
  /// Premium on purpose (header button, Customer Center fallback).
  final PremiumFeature? reason;

  const UnlockSheet({
    super.key,
    required this.purchases,
    required this.onClose,
    this.reason,
  });

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
    // Bought or restored from this sheet — dismiss back to the composer.
    if (_p.unlocked) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final price = _p.priceLabel;
    final reason = widget.reason;
    return Container(
      color: Toy.bg,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reason?.emoji ?? '✨', style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text(
              reason == null
                  ? 'EMOJIO PREMIUM'
                  : '${reason.title.toUpperCase()} IS PREMIUM',
              textAlign: TextAlign.center,
              style: Toy.label(13),
            ),
            if (reason != null) ...[
              const SizedBox(height: 10),
              Text(reason.blurb,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Toy.text)),
            ],
            const SizedBox(height: 18),
            // Everything Premium adds, so one purchase reads as worth it.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in PremiumFeature.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(f.emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(f.title, style: Toy.label(9))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'For grown-ups: one payment, yours forever.\nNo subscription.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 18),
            if (_p.purchasePending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CircularProgressIndicator(color: Toy.accent),
              )
            else
              ToyButton(
                label: price.isEmpty ? 'Get Premium' : 'Get Premium — $price',
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
            // No product loaded — say so plainly and offer a retry.
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
            const SizedBox(height: 22),
            TextButton(
              onPressed: widget.onClose,
              child: Text('Not now', style: Toy.label(9)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showUnlockSheet(BuildContext context, PurchaseManager purchases,
        {PremiumFeature? reason}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Toy.bg,
      isScrollControlled: true,
      builder: (sheetContext) => UnlockSheet(
        purchases: purchases,
        reason: reason,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );

/// Opens the purchase flow and resolves once it's dismissed; true if the user
/// now has the unlock.
///
/// From a locked feature ([reason] set) it shows [UnlockSheet], which can say
/// which feature was reached for. Opened on purpose (the header Premium button)
/// it prefers RevenueCat's dashboard paywall and falls back to [UnlockSheet]
/// when that can't be used — the SDK isn't configured, no product loaded, or
/// the native presentation returned an error. Every path ends with something
/// on screen; none of them no-op.
Future<bool> presentEmojioPaywall(
    BuildContext context, PurchaseManager purchases,
    {PremiumFeature? reason}) async {
  // Presenting before configure() trips a native `Purchases.shared` assertion
  // (SIGTRAP) that a Dart try/catch can't catch, so gate on it.
  final configured = await Purchases.isConfigured;
  // One retry: the offering may have failed to load at boot (e.g. offline
  // launch) and since recovered.
  if (configured && !purchases.canBuy) await purchases.reload();

  if (reason == null && configured && purchases.canBuy) {
    final result = await RevenueCatUI.presentPaywall(displayCloseButton: true);
    if (result == PaywallResult.purchased || result == PaywallResult.restored) {
      return true;
    }
    if (result != PaywallResult.error) return purchases.unlocked;
  }
  if (!context.mounted) return purchases.unlocked;
  await _showUnlockSheet(context, purchases, reason: reason);
  return purchases.unlocked;
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
  await _showUnlockSheet(context, purchases);
}

/// Slim ribbon shown during the reverse trial (Premium free for the first few
/// days), so the drop back to the free tier is never a surprise. Carries a real
/// [ToyButton]: styled as a flat ribbon it read as a status strip, and App
/// Review couldn't find the purchase behind it.
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
                child: Text(
                    'Premium free for $d more ${d == 1 ? "day" : "days"}',
                    style: Toy.label(9)),
              ),
              ToyButton(
                label: 'Keep Premium',
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
