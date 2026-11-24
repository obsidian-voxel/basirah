import 'dart:async';

import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import 'blockp_theme.dart';

/// The long-sentence lock, enforced where it used to be only advertised.
///
/// A password in Advanced Settings is meant to stop an impulsive change: the
/// user has to retype a sentence they did not memorise, which takes long
/// enough to think. Every guard-off path calls [requireLongSentencePassword].
Future<bool> requireLongSentencePassword(BuildContext context) async {
  final expected = blurEngine.longSentencePassword.trim();
  if (expected.isEmpty) return true;

  final controller = TextEditingController();
  final ok = await showBpDialog<bool>(
    context: context,
    title: 'Type your sentence',
    showActions: false,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This is the sentence you set to guard changes. It is not a '
          'recoverable password: if it is lost, only clearing app data '
          'removes it.',
          style: context.small,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(hintText: 'Long sentence password'),
        ),
        const SizedBox(height: 16),
        BpButton(
          label: 'Unlock',
          onPressed: () => Navigator.of(context).pop(
            _matches(controller.text, expected),
          ),
        ),
      ],
    ),
  );
  controller.dispose();
  return ok ?? false;
}

bool _matches(String typed, String expected) {
  String normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return normalise(typed) == normalise(expected);
}

/// Confirms an action only after a countdown, so a reflex tap cannot disable
/// protection. Returns false when the dialog is dismissed.
Future<bool> confirmWithDelay(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  int seconds = 15,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DelayedConfirmDialog(
      title: title,
      message: message,
      action: action,
      seconds: seconds,
    ),
  );
  return ok ?? false;
}

class _DelayedConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String action;
  final int seconds;

  const _DelayedConfirmDialog({
    required this.title,
    required this.message,
    required this.action,
    required this.seconds,
  });

  @override
  State<_DelayedConfirmDialog> createState() => _DelayedConfirmDialogState();
}

class _DelayedConfirmDialogState extends State<_DelayedConfirmDialog> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _left--);
      if (_left <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _left <= 0;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, style: context.body),
          const SizedBox(height: 12),
          Text(
            ready
                ? 'You can continue now.'
                : 'Waiting ${_left}s so this cannot be a reflex tap.',
            style: context.small,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Full-screen lock shown when Advanced Settings is opened while a sentence
/// password is set. Unlocking lasts until the screen is closed.
class SettingsLockPanel extends StatefulWidget {
  final VoidCallback onUnlocked;

  const SettingsLockPanel({super.key, required this.onUnlocked});

  @override
  State<SettingsLockPanel> createState() => _SettingsLockPanelState();
}

class _SettingsLockPanelState extends State<SettingsLockPanel> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _unlock() {
    if (_matches(_controller.text, blurEngine.longSentencePassword)) {
      setState(() => _error = null);
      widget.onUnlocked();
      return;
    }
    setState(() => _error = 'That does not match your sentence.');
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Scaffold(
      backgroundColor: bp.canvas,
      body: DecoratedBox(
        decoration: context.bpCanvas,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back, color: bp.ink),
                    ),
                  ],
                ),
                const Spacer(),
                Icon(Icons.lock_outline, size: 54, color: bp.ink),
                const SizedBox(height: 18),
                Text(
                  'Settings are locked',
                  textAlign: TextAlign.center,
                  style: context.title.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  'Type your long sentence to change a guard.',
                  textAlign: TextAlign.center,
                  style: context.body.copyWith(color: bp.muted),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  maxLines: 3,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    hintText: 'Your sentence',
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 18),
                BpButton(label: 'Unlock', onPressed: _unlock),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
