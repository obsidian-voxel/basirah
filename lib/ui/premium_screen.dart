import 'package:flutter/material.dart';

import 'blockp_theme.dart';
import 'brand_art.dart';

/// Premium tab.
///
/// The reference sells a subscription here. This build has no payment backend,
/// no merchant account and no network permission, so there is nothing to buy
/// and nothing to restore: the whole feature set ships unlocked. The screen
/// keeps the reference layout (ticket, feature checklist, comparison) and
/// replaces every price, review and publication logo with what is actually
/// true of this app.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  static const _features = <(IconData, String)>[
    (Icons.block, 'Standard Blocking'),
    (Icons.blur_on, 'Visual AI Blocking'),
    (Icons.link, 'Accountability partner'),
    (Icons.favorite_border, 'Social Media Blocking'),
    (Icons.tune, 'Custom Redirects'),
    (Icons.devices_outlined, 'Unlimited devices'),
  ];

  static const _replaces = <(IconData, String, String)>[
    (Icons.block, 'Adult Blocker', 'Picture and keyword filtering'),
    (Icons.public_off_outlined, 'Website Blocker', 'Host-suffix matching'),
    (Icons.apps, 'App Blocker', 'Package-level blocking'),
    (Icons.filter_hdr_outlined, 'Focus Timer', 'Calm sessions'),
    (Icons.link, 'Accountability Partner', 'Local partner log'),
  ];

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return BpPage(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        const Center(child: _Ticket()),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Basirah', style: context.display.copyWith(fontSize: 28)),
            const SizedBox(width: 10),
            Text(
              'بَصِيرَة',
              textDirection: TextDirection.rtl,
              style: BpType.arabic.copyWith(
                fontSize: 26,
                color: const Color(0xFFB08A3E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: bp.primarySoft,
              borderRadius: BorderRadius.circular(BpRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined, size: 20, color: bp.primary),
                const SizedBox(width: 8),
                Text(
                  'All features · no account',
                  style: context.small.copyWith(
                    color: bp.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Divider(color: bp.divider),
        const SizedBox(height: 18),
        _Checklist(features: _features),
        const SizedBox(height: 22),
        Divider(color: bp.divider),
        const SizedBox(height: 22),
        Center(
          child: Text(
            'On Android, on your device',
            style: context.rowTitle.copyWith(fontSize: 19),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.android, size: 34, color: bp.ink),
            const SizedBox(width: 10),
            Text(
              'Android 11+',
              style: context.body.copyWith(color: bp.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Divider(color: bp.divider),
        const SizedBox(height: 26),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontFamily: BpType.family,
              fontSize: 38,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: bp.ink,
            ),
            children: [
              TextSpan(
                text: 'One ',
                style: TextStyle(color: bp.primary),
              ),
              const TextSpan(text: 'app to\nreplace them all.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Why pay for 12+ apps when one is enough?',
            textAlign: TextAlign.center,
            style: context.body.copyWith(fontSize: 17, color: bp.inkSoft),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BpRadii.card),
            border: Border.all(color: bp.muted.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < _replaces.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Icon(_replaces[i].$1, size: 26, color: bp.ink),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _replaces[i].$2,
                              style: context.rowTitle.copyWith(fontSize: 18),
                            ),
                            Text(
                              _replaces[i].$3,
                              style: context.small.copyWith(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.check, size: 24, color: bp.primary),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          decoration: BoxDecoration(
            color: bp.primarySoft,
            borderRadius: BorderRadius.circular(BpRadii.card),
            border: Border.all(color: bp.primary, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 28, color: bp.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Total to pay',
                  style: context.rowTitle.copyWith(fontSize: 19),
                ),
              ),
              Text('Nothing', style: context.rowTitle.copyWith(fontSize: 20)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'This build has no purchase flow, no subscription and no server. '
          'Every feature above is included and works offline; the price is '
          'nothing because there is nothing to charge for.',
          textAlign: TextAlign.center,
          style: context.small,
        ),
      ],
    );
  }
}

/// The gold "Full Access" ticket, with the geometric mark where the reference
/// puts its mascot.
class _Ticket extends StatelessWidget {
  const _Ticket();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.04,
      child: Container(
        height: 230,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE4CFA2), Color(0xFFCDB07A), Color(0xFFB6935A)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8C6D3A).withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Perforation.
            Positioned(
              top: 16,
              bottom: 16,
              right: 74,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 12; i++)
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF3E6CB),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        size: 15,
                        color: Color(0xFF8A6B35),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Full Access',
                        style: TextStyle(
                          fontFamily: BpType.family,
                          fontSize: 17,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6E5327).withValues(alpha: 0.9),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        margin: const EdgeInsets.only(right: 60),
                        child: Row(
                          children: [
                            for (var i = 0; i < 3; i++)
                              const Icon(
                                Icons.star,
                                size: 11,
                                color: Color(0xFF8A6B35),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Center(
                      child: BasirahMark(
                        size: 128,
                        color: const Color(0xFF5E4520),
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'BASIRAH',
                        style: TextStyle(
                          fontFamily: BpType.family,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: const Color(
                            0xFF6E5327,
                          ).withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'بَصِيرَة',
                        textDirection: TextDirection.rtl,
                        style: BpType.arabic.copyWith(
                          fontSize: 14,
                          color: const Color(
                            0xFF6E5327,
                          ).withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Feature list with the reference's pale blue rail and check marks.
class _Checklist extends StatelessWidget {
  final List<(IconData, String)> features;

  const _Checklist({required this.features});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                for (final feature in features)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Icon(feature.$1, size: 26, color: bp.ink),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            feature.$2,
                            style: context.rowTitle.copyWith(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 54,
            decoration: BoxDecoration(
              color: bp.primarySoft,
              borderRadius: BorderRadius.circular(27),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < features.length; i++)
                  Icon(Icons.check, size: 24, color: bp.ink),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
