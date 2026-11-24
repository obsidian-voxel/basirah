import 'dart:async';

import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import 'blockp_theme.dart';
import 'brand_art.dart';

/// Calm tab: BlockP's calm mode.
///
/// A session locks every app that is not on the allow list until the timer
/// runs out. The session state lives in [blurEngine]; this screen only drives
/// it and shows what the engine reports, so a killed UI cannot fake a session.
class CalmScreen extends StatefulWidget {
  const CalmScreen({super.key});

  @override
  State<CalmScreen> createState() => _CalmScreenState();
}

class _CalmScreenState extends State<CalmScreen> {
  static const _minMinutes = 15;
  static const _maxMinutes = 180;

  int _minutes = 60;
  int? _sessionTotalMinutes;
  final Set<String> _allowed = <String>{};
  Map<String, String> _labels = <String, String>{};
  bool _wasActive = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _wasActive = blurEngine.focusActive;
    if (_wasActive) {
      _sessionTotalMinutes = blurEngine.focusMinutesLeft;
      _allowed.addAll(blurEngine.focusAllowedApps);
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final active = blurEngine.focusActive;
    if (active != _wasActive) {
      _wasActive = active;
      if (!active) {
        blurEngine.stopFocusSession();
        _sessionTotalMinutes = null;
      }
      setState(() {});
      return;
    }
    if (active) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _labelFor(String package) {
    final label = _labels[package];
    if (label != null && label.trim().isNotEmpty) return label;
    final tail = package.split('.').last;
    return tail.isEmpty ? package : tail;
  }

  Future<void> _pickAllowedApps() async {
    final apps = await nativeBridge.listApps();
    if (!mounted) return;
    if (apps.isEmpty) {
      _snack(nativeBridge.isSupported
          ? 'Android did not report any launchable apps.'
          : 'Installed-app picking is Android only.');
      return;
    }
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _AllowedAppsDialog(apps: apps, selected: _allowed),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _allowed
        ..clear()
        ..addAll(chosen);
      _labels = {
        ..._labels,
        for (final app in apps) app.packageName: app.label,
      };
    });
  }

  Future<void> _start() async {
    final duration = _clampMinutes(_minutes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Calm Mode?'),
        content: Text(
          'Every app other than the ${_allowed.length} allowed one(s) will be '
          'blocked for ${_durationLabel(duration)}.\n\n'
          'Are you sure you want to take this action?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await blurEngine.startFocusSession(
      duration: Duration(minutes: duration),
      allowedApps: _allowed.toList(growable: false),
    );
    if (!mounted) return;
    setState(() {
      _sessionTotalMinutes = duration;
      _wasActive = true;
    });
    _snack('Calm mode is on for ${_durationLabel(duration)}.');
  }

  Future<void> _end() async {
    if (blurEngine.focusPreventExit) {
      _snack('Prevent exit is on, so this session cannot end early.');
      return;
    }
    await blurEngine.stopFocusSession();
    if (!mounted) return;
    setState(() {
      _sessionTotalMinutes = null;
      _wasActive = false;
    });
    _snack('Calm mode ended.');
  }

  static int _clampMinutes(int value) =>
      value.clamp(_minMinutes, _maxMinutes).toInt();

  static String _durationLabel(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '${rest}min';
    return '${hours}h ${rest.toString().padLeft(2, '0')}min';
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return ListenableBuilder(
      listenable: blurEngine,
      builder: (context, _) {
        final active = blurEngine.focusActive;
        final minutesLeft = blurEngine.focusMinutesLeft;
        final total = _sessionTotalMinutes ?? minutesLeft;
        final progress = total <= 0 ? 0.0 : 1 - (minutesLeft / total);
        return Column(
          children: [
            Expanded(
              flex: 44,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CalmScene(),
                  if (active)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 18,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: bp.canvas.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(BpRadii.pill),
                          ),
                          child: Text(
                            'Calm mode · $minutesLeft min left',
                            style: context.rowTitle.copyWith(fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 56,
              child: Container(
                decoration: BoxDecoration(
                  color: bp.canvas,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(BpRadii.card),
                  ),
                ),
                child: SingleChildScrollView(
                  // The floating tab bar overlays this sheet, so reserve room
                  // for it at the end.
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: bp.muted.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        active
                            ? _durationLabel(minutesLeft)
                            : _durationLabel(_minutes),
                        style: context.display.copyWith(fontSize: 34),
                      ),
                      const SizedBox(height: 18),
                      if (!active)
                        _DurationSlider(
                          minutes: _minutes,
                          min: _minMinutes,
                          max: _maxMinutes,
                          onChanged: (value) =>
                              setState(() => _minutes = _clampMinutes(value)),
                        )
                      else
                        _SessionProgress(progress: progress),
                      const SizedBox(height: 18),
                      BpCard(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.list_alt_rounded,
                                    size: 24,
                                    color: bp.ink,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'Allowed apps (${_allowed.length})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.rowTitle.copyWith(
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 68,
                                    child: _AllowedPreview(
                                      labels: [
                                        for (final package in _allowed.take(3))
                                          _labelFor(package),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: active ? null : _pickAllowedApps,
                                    icon: Icon(
                                      Icons.add,
                                      size: 26,
                                      color: active
                                          ? bp.muted
                                          : bp.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: bp.divider),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.login_outlined,
                                    size: 24,
                                    color: bp.ink,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'Prevent exit (Recommended)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.rowTitle.copyWith(
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  BpSwitch(
                                    value: blurEngine.focusPreventExit,
                                    onChanged: (value) async {
                                      await blurEngine.setFocusPreventExit(
                                        value,
                                      );
                                      if (!mounted) return;
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_allowed.isEmpty && !active) ...[
                        const SizedBox(height: 12),
                        Text(
                          'No app is allowed: a session locks everything.',
                          textAlign: TextAlign.center,
                          style: context.small,
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: 220,
                        child: BpButton(
                          label: active
                              ? (blurEngine.focusPreventExit
                                  ? 'Session locked'
                                  : 'End Calm Mode')
                              : 'Enter Calm Mode',
                          onPressed: active
                              ? (blurEngine.focusPreventExit ? null : _end)
                              : _start,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Primary track with a pill thumb and a small origin dot, as in the reference.
class _DurationSlider extends StatelessWidget {
  final int minutes;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _DurationSlider({
    required this.minutes,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final fraction = ((minutes - min) / (max - min)).clamp(0.0, 1.0);
    return SizedBox(
      height: 34,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final x = (width - 30) * fraction;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              final raw = details.localPosition.dx / width;
              final value = (min + raw * (max - min)).round();
              onChanged((value / 15).round() * 15);
            },
            onTapDown: (details) {
              final raw = details.localPosition.dx / width;
              final value = (min + raw * (max - min)).round();
              onChanged((value / 15).round() * 15);
            },
            child: Stack(
              children: [
                Positioned(
                  left: 6,
                  right: 6,
                  top: 14,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: bp.primary.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 14,
                  width: (x + 7).clamp(0.0, width - 12),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: bp.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 10,
                  child: Container(
                    width: 22,
                    height: 14,
                    decoration: BoxDecoration(
                      color: bp.primary,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                Positioned(
                  left: x,
                  top: 10,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: bp.canvas,
                      shape: BoxShape.circle,
                      border: Border.all(color: bp.primary, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SessionProgress extends StatelessWidget {
  final double progress;

  const _SessionProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: bp.primary.withValues(alpha: 0.2),
        valueColor: AlwaysStoppedAnimation<Color>(bp.primary),
      ),
    );
  }
}

/// Up to three circular initials, matching the reference's app-icon preview.
class _AllowedPreview extends StatelessWidget {
  final List<String> labels;

  const _AllowedPreview({required this.labels});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    if (labels.isEmpty) {
      return Text(
        'None',
        textAlign: TextAlign.right,
        style: context.small,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < labels.length; i++)
          Transform.translate(
            offset: Offset(-6.0 * i, 0),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i.isEven ? bp.primary : bp.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: bp.card, width: 2),
              ),
              child: Text(
                labels[i].substring(0, 1).toUpperCase(),
                style: BpType.nav.copyWith(
                  color: i.isEven ? Colors.white : bp.ink,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AllowedAppsDialog extends StatefulWidget {
  final List<InstalledApp> apps;
  final Set<String> selected;

  const _AllowedAppsDialog({required this.apps, required this.selected});

  @override
  State<_AllowedAppsDialog> createState() => _AllowedAppsDialogState();
}

class _AllowedAppsDialogState extends State<_AllowedAppsDialog> {
  late final Set<String> _selected = Set<String>.of(widget.selected);
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final apps = widget.apps.where((app) {
      if (_query.isEmpty) return true;
      final query = _query.toLowerCase();
      return app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList(growable: false);

    return AlertDialog(
      title: const Text('Allowed apps'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search apps',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final app in apps)
                    CheckboxListTile(
                      dense: true,
                      value: _selected.contains(app.packageName),
                      title: Text(
                        app.label.isEmpty ? app.packageName : app.label,
                        style: context.rowTitle.copyWith(fontSize: 15),
                      ),
                      subtitle: Text(app.packageName, style: context.small),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(app.packageName);
                        } else {
                          _selected.remove(app.packageName);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
