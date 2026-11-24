import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../src/affirmations.dart';
import 'blockp_theme.dart';
import 'brand_art.dart';

/// Morning gate: after the configured time, Basirah opens here instead of
/// the dashboard until each affirmation has been read.
///
/// The reference app locks the whole phone until the sentences are spoken;
/// that needs microphone access and device-owner rights, so this gate covers
/// this app only and asks for a deliberate tap on every line rather than
/// pretending to listen.
class MorningAffirmationsGate extends StatefulWidget {
  const MorningAffirmationsGate({super.key});

  @override
  State<MorningAffirmationsGate> createState() =>
      _MorningAffirmationsGateState();
}

class _MorningAffirmationsGateState extends State<MorningAffirmationsGate> {
  final Set<int> _read = {};

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final custom = blurEngine.customAffirmations;
    final sentences =
        custom.isNotEmpty ? custom : builtInAffirmations;
    final done = _read.length == sentences.length;

    return Scaffold(
      backgroundColor: bp.canvas,
      body: DecoratedBox(
        decoration: context.bpCanvas,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: BasirahMark(size: 76, color: bp.ink, strokeWidth: 2.4),
                ),
                const SizedBox(height: 10),
                Text(
                  'Basirah',
                  textAlign: TextAlign.center,
                  style: context.title.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'بَصِيرَة',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: BpType.arabic.copyWith(fontSize: 17, height: 1.2),
                ),
                const SizedBox(height: 18),
                Text(
                  'Before you start',
                  textAlign: TextAlign.center,
                  style: context.title.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 8),
                Text(
                  'Read each line, then tap it. The app opens once they are '
                  'all read.',
                  textAlign: TextAlign.center,
                  style: context.body.copyWith(color: bp.muted),
                ),
                const SizedBox(height: 20),
                for (var i = 0; i < sentences.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AffirmationCard(
                      text: sentences[i],
                      read: _read.contains(i),
                      onTap: () => setState(() {
                        if (!_read.add(i)) _read.remove(i);
                      }),
                    ),
                  ),
                const SizedBox(height: 12),
                BpButton(
                  label: done
                      ? 'Start the day'
                      : 'Tap each line (${_read.length}/${sentences.length})',
                  onPressed: done
                      ? () => blurEngine.completeMorningAffirmations()
                      : null,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'This gate covers Basirah only. It is not a phone lock.',
                    textAlign: TextAlign.center,
                    style: context.small.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AffirmationCard extends StatelessWidget {
  final String text;
  final bool read;
  final VoidCallback onTap;

  const _AffirmationCard({
    required this.text,
    required this.read,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: read ? bp.card : bp.innerCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: read ? bp.primary : bp.divider,
            width: read ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              read ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: read ? bp.primary : bp.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: context.body.copyWith(
                  fontSize: 16,
                  height: 1.35,
                  color: bp.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
