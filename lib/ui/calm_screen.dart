import 'dart:async';

import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import 'blockp_theme.dart';
import 'brand_art.dart';

/// Calm tab: one timer that locks everything except the apps you allow.
///
/// The session state lives in [blurEngine]; this screen only drives it and
/// shows what the engine reports, so a killed UI cannot fake a session.
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
              flex: 42,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CalmScene(),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calm mode',
                            style: BpType.title.copyWith(
                              fontSize: 22,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            active
                                ? 'Everything but your allowed apps is locked.'
                                : 'A pause with the noise switched off.',
                            style: BpType.body.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: _TimerDial(
                      active: active,
                      minutes: active ? minutesLeft : _minutes,
                      progress: active ? progress : 0,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 58,
              child: Container(
                decoration: BoxDecoration(
                  color: bp.canvas,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(BpRadii.card),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  child: Column(
                    children: [
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: bp.muted.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (!active) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Session length',
                                style: context.rowTitle,
                              ),
                            ),
                            Text(
                              _durationLabel(_minutes),
                              style: context.rowTitle.copyWith(
                                color: bp.primary,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _DurationSlider(
                          minutes: _minutes,
                          min: _minMinutes,
                          max: _maxMinutes,
                          onChanged: (value) =>
                              setState(() => _minutes = _clampMinutes(value)),
                        ),
                        const SizedBox(height: 14),
                      ] else ...[
                        _SessionProgress(progress: progress),
                        const SizedBox(height: 16),
                      ],
                      BpCard(
                        child: Column(
                          children: [
                            BpRow(
                              icon: Icon(
                                Icons.apps,
                                size: 20,
                                color: bp.primary,
                              ),
                              title: 'Allowed apps',
                              description: _allowed.isEmpty
                                  ? 'Nothing is allowed — a session locks '
                                        'everything.'
                                  : '${_allowed.length} app(s) stay usable '
                                        'during a session.',
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _AllowedPreview(
                                    labels: [
                                      for (final package in _allowed.take(3))
                                        _labelFor(package),
                                    ],
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: 'Choose allowed apps',
                                    onPressed: active ? null : _pickAllowedApps,
                                    icon: Icon(
                                      Icons.add_circle_outline,
                                      size: 22,
                                      color: active ? bp.muted : bp.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            BpRow(
                              icon: Icon(
                                Icons.logout,
                                size: 20,
                                color: bp.primary,
                              ),
                              title: 'Prevent exit',
                              description: 'Recommended — the session cannot be '
                                  'ended early.',
                              trailing: BpSwitch(
                                value: blurEngine.focusPreventExit,
                                onChanged: (value) async {
                                  await blurEngine.setFocusPreventExit(value);
                                  if (!mounted) return;
                                  setState(() {});
                                },
                              ),
                              showDivider: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      BpButton(
                        label: active
                            ? (blurEngine.focusPreventExit
                                  ? 'Session locked'
                                  : 'End Calm Mode')
                            : 'Enter Calm Mode',
                        onPressed: active
                            ? (blurEngine.focusPreventExit ? null : _end)
                            : _start,
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

/// The remaining time inside a progress ring.
class _TimerDial extends StatelessWidget {
  final bool active;
  final int minutes;
  final double progress;

  const _TimerDial({
    required this.active,
    required this.minutes,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final label = minutes >= 60
        ? '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m'
        : '${minutes}m';
    return SizedBox(
      width: 176,
      height: 176,
      child: CustomPaint(
        painter: _DialPainter(progress: progress.clamp(0.0, 1.0)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: BpType.display.copyWith(
                  fontSize: 34,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                active ? 'remaining' : 'ready',
                style: BpType.small.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double progress;

  _DialPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final value = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5708,
        6.2832 * progress,
        false,
        value,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// A primary track with a round thumb.
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
      height: 40,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final x = (width - 22) * fraction;
          void setFrom(double dx) {
            final raw = (dx / width).clamp(0.0, 1.0);
            final value = (min + raw * (max - min)).round();
            onChanged((value / 15).round() * 15);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) =>
                setFrom(details.localPosition.dx),
            onTapDown: (details) => setFrom(details.localPosition.dx),
            child: Stack(
              children: [
                Positioned(
                  left: 4,
                  right: 4,
                  top: 17,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: bp.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 17,
                  width: (x + 4).clamp(0.0, width - 8),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: bp.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: x,
                  top: 10,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: bp.card,
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
        backgroundColor: bp.primary.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation<Color>(bp.primary),
      ),
    );
  }
}

/// Up to three circular initials for the allowed apps.
class _AllowedPreview extends StatelessWidget {
  final List<String> labels;

  const _AllowedPreview({required this.labels});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    if (labels.isEmpty) {
      return Text('None', style: context.small);
    }
    return SizedBox(
      width: 22.0 * labels.length + 4,
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < labels.length; i++)
            Positioned(
              left: 18.0 * i,
              top: 0,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i.isEven ? bp.primary : bp.primarySoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: bp.card, width: 2),
                ),
                child: Text(
                  labels[i].substring(0, 1).toUpperCase(),
                  style: BpType.small.copyWith(
                    color: i.isEven ? Colors.white : bp.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
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
