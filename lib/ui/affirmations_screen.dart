import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../src/affirmations.dart';
import 'blockp_theme.dart';

/// Daily affirmations: the printed intentions the user starts the day with.
///
/// Everything here is local. Affirmations the user writes are stored in the
/// app's private preferences and can be removed at any time.
class AffirmationsScreen extends StatefulWidget {
  const AffirmationsScreen({super.key});

  @override
  State<AffirmationsScreen> createState() => _AffirmationsScreenState();
}

class _AffirmationsScreenState extends State<AffirmationsScreen> {
  final TextEditingController _controller = TextEditingController();

  Future<void> _pickLockTime() async {
    final current = blurEngine.affirmationLockMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    await blurEngine.setAffirmationLockMinute(picked.hour * 60 + picked.minute);
  }

  String get _lockTimeLabel {
    final minute = blurEngine.affirmationLockMinute;
    return '${(minute ~/ 60).toString().padLeft(2, '0')}:'
        '${(minute % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.length < 4) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Write at least a few words.')),
        );
      return;
    }
    await blurEngine.addAffirmation(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Scaffold(
      backgroundColor: bp.canvas,
      body: DecoratedBox(
        decoration: context.bpCanvas,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: blurEngine,
            builder: (context, _) {
              final custom = blurEngine.customAffirmations;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(Icons.arrow_back, color: bp.ink),
                        ),
                        Expanded(
                          child: Text(
                            'Daily Affirmations',
                            style: context.title.copyWith(fontSize: 22),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    BpSectionCard(
                      icon: Icons.wb_twilight,
                      title: 'Morning gate',
                      children: [
                        BpRow.withIcon(
                          Icons.lock_clock,
                          title: 'Open on affirmations',
                          description:
                              'After $_lockTimeLabel, Basirah opens here '
                              'until every line is read',
                          trailing: BpSwitch(
                            value: blurEngine.dailyAffirmations,
                            onChanged: (value) =>
                                blurEngine.setAdvanced(dailyAffirmations: value),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.schedule,
                          title: 'Lock after',
                          description: _lockTimeLabel,
                          onTap: _pickLockTime,
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    BpCard(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'What would you like to say?',
                            style: context.rowTitle.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Write a sentence you can read in the morning. It '
                            'stays on this device.',
                            style: context.body,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _controller,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Today I choose…',
                            ),
                          ),
                          const SizedBox(height: 12),
                          BpButton(label: 'Save', onPressed: _add),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    BpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                            child: Text(
                              'Your affirmations',
                              style: context.title.copyWith(fontSize: 19),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: bp.divider,
                            indent: 18,
                            endIndent: 18,
                          ),
                          if (custom.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 18, 18, 18),
                              child: Text(
                                'Nothing saved yet. The built-in sentences '
                                'below are always available.',
                                style: context.body,
                              ),
                            )
                          else
                            for (final text in custom)
                              BpRow.withIcon(
                                Icons.format_quote,
                                title: text,
                                trailing: IconButton(
                                  tooltip: 'Remove',
                                  onPressed: () =>
                                      blurEngine.removeAffirmation(text),
                                  icon: Icon(
                                    Icons.close,
                                    size: 20,
                                    color: bp.muted,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    BpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                            child: Text(
                              'Built-in sentences',
                              style: context.title.copyWith(fontSize: 19),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: bp.divider,
                            indent: 18,
                            endIndent: 18,
                          ),
                          for (var i = 0;
                              i < builtInAffirmations.length;
                              i++)
                            BpRow.withIcon(
                              Icons.wb_sunny_outlined,
                              title: builtInAffirmations[i],
                              iconColor: bp.muted,
                              showDivider:
                                  i != builtInAffirmations.length - 1,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Stored on this device. Nothing is recorded or '
                            'uploaded.',
                        style: context.small,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
