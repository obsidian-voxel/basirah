import 'package:flutter/material.dart';

import 'blockp_theme.dart';
import 'brand_art.dart';

/// The "everything included" tab.
///
/// The reference sells a subscription here, and the first rebuild reproduced
/// its gold ticket, stars and perforation. There is no purchase flow, no
/// merchant account and no INTERNET permission in this build, so a ticket that
/// looks bought was pretending. What is left is the useful part: what the app
/// does, what it replaces, and that it costs nothing.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  static const _features = <(IconData, String, String)>[
    (Icons.block, 'App, site and keyword blocking', 'Your lists, enforced'),
    (Icons.blur_on, 'On-device screen blur', 'No frame leaves the phone'),
    (Icons.timer_outlined, 'Hours and daily limits', 'Per app, per day'),
    (Icons.nightlight_outlined, 'Calm sessions', 'One timer, everything else locked'),
    (Icons.link, 'Accountability partner', 'A name and a local log'),
    (Icons.wb_sunny_outlined, 'Morning affirmations', 'A pause before the phone opens'),
  ];

  static const _replaces = <(IconData, String, String)>[
    (Icons.block, 'Adult blocker', 'Picture and keyword filtering'),
    (Icons.public_off_outlined, 'Website blocker', 'Host-suffix matching'),
    (Icons.apps, 'App blocker', 'Package-level blocking'),
    (Icons.filter_hdr_outlined, 'Focus timer', 'Calm sessions'),
    (Icons.link, 'Accountability partner', 'Local partner log'),
  ];

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return BpPage(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const BpHeader(
          title: 'Everything included',
          subtitle: 'No subscription, no account, no ads.',
        ),
        _Hero(),
        const BpSectionLabel('What is inside'),
        BpCard(
          child: Column(
            children: [
              for (var i = 0; i < _features.length; i++)
                BpRow(
                  icon: Icon(_features[i].$1, size: 19, color: bp.primary),
                  title: _features[i].$2,
                  description: _features[i].$3,
                  trailing: Icon(
                    Icons.check_circle,
                    size: 20,
                    color: bp.switchOn,
                  ),
                  showDivider: i != _features.length - 1,
                ),
            ],
          ),
        ),
        const BpSectionLabel('One app instead of many'),
        BpCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why pay for 12+ apps when one is enough?',
                style: context.title.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'Each of these ships inside Basirah, offline.',
                style: context.body,
              ),
              const SizedBox(height: 8),
              for (final item in _replaces)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bp.innerCard,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item.$1, size: 17, color: bp.inkSoft),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: context.rowTitle.copyWith(fontSize: 14.5),
                            ),
                            Text(item.$3, style: context.small),
                          ],
                        ),
                      ),
                      Icon(Icons.check, size: 18, color: bp.primary),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: bp.innerCard,
            borderRadius: BorderRadius.circular(BpRadii.card),
            border: Border.all(color: bp.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 22, color: bp.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Total to pay',
                  style: context.rowTitle.copyWith(fontSize: 15),
                ),
              ),
              Text(
                'Nothing',
                style: context.rowTitle.copyWith(
                  fontSize: 18,
                  color: bp.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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

/// The headline card: the mark, one sentence, three facts.
class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark = context.bpIsDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BpRadii.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF1D3557), Color(0xFF152B45)]
              : const [Color(0xFF1A5CE5), Color(0xFF123F9E)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const BasirahMark(
              size: 26,
              color: Colors.white,
              strokeWidth: 2.6,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Your phone, on your terms.',
            style: BpType.display.copyWith(
              fontSize: 26,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Everything Basirah can do is switched on from the first launch. '
            'There is nothing to unlock.',
            style: BpType.body.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final fact in const [
                'Fully offline',
                'No account',
                'Android 11+',
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check,
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        fact,
                        style: BpType.small.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
