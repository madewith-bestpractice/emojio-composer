import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../theme.dart';
import 'access.dart';
import 'purchases.dart';
import 'trial.dart';

/// Emojio's own Premium sheet, and the only paywall: RevenueCat supplies the
/// product, price, purchase and restore; the sheet is ours. It names the
/// feature that opened it (when there is one), lists everything Premium adds,
/// and always renders *something*: a real buy button when a product loaded,
/// and a plain message plus a retry when one didn't — so a failed product load
/// never reads as a dead tap. Someone who already owns Premium gets a thank-you
/// with Restore instead of a buy button.
///
/// The copy speaks to the grown-up holding the iPad: the sheet usually opens
/// because a child tapped a locked sticker.
class UnlockSheet extends StatefulWidget {
  final PurchaseManager purchases;
  final VoidCallback onClose;

  /// The locked feature the user just reached for, or null when they opened
  /// Premium on purpose (the header button, or a long-press on the logo).
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
  late final bool _ownedAtOpen = _p.unlocked;

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
    if (_p.unlocked && !_ownedAtOpen) widget.onClose();
  }

  /// Already Premium (opened from the logo): no buy button, just thanks,
  /// Restore for a new device, and where to ask for help.
  Widget _owned() => Container(
    color: Toy.bg,
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🎉', style: TextStyle(fontSize: 44)),
        const SizedBox(height: 14),
        Text('YOU HAVE PREMIUM', style: Toy.label(13)),
        const SizedBox(height: 10),
        const Text(
          'Thanks for supporting Emojio! Every sound, video export, MIDI, '
          'Pencil pressure and unlimited songs are yours, forever.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Toy.text),
        ),
        const SizedBox(height: 18),
        ToyButton(
          label: 'Restore Purchase',
          emoji: '♻️',
          color: Colors.white,
          textColor: Toy.text,
          fontSize: 9,
          onPressed: _p.restore,
        ),
        const SizedBox(height: 14),
        const SelectableText(
          'Questions? brendan@madewithbestpractice.com',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: widget.onClose,
          child: Text('Done', style: Toy.label(9)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_p.unlocked) return _owned();
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
/// now has the unlock. [reason] is the locked feature that opened it, if any.
Future<bool> presentEmojioPaywall(
    BuildContext context, PurchaseManager purchases,
    {PremiumFeature? reason}) async {
  // One retry: the offering may have failed to load at boot (e.g. offline
  // launch) and since recovered.
  if (await Purchases.isConfigured && !purchases.canBuy) await purchases.reload();
  if (!context.mounted) return purchases.unlocked;
  await _showUnlockSheet(context, purchases, reason: reason);
  return purchases.unlocked;
}

/// The long-press on the logo: the same sheet, which shows a thank-you with
/// Restore to someone who owns Premium. Restore is reachable from here and from
/// the Premium sheet at all times — Guideline 3.1.1 requires it for a
/// non-consumable.
Future<void> presentEmojioPurchases(
        BuildContext context, PurchaseManager purchases) =>
    _showUnlockSheet(context, purchases);

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
