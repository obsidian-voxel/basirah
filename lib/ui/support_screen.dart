import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/blur_engine.dart';
import 'blockp_theme.dart';

/// Support tab.
///
/// The reference links out to WhatsApp, Discord, email and a subreddit. This
/// app has no server and no INTERNET permission, so every "contact" action
/// here is local: copy a diagnostic report, read the privacy note, or read the
/// answers. Nothing leaves the device and the screen says so.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _faq = <(String, String)>[
    (
      'Why was nothing blocked?',
      'Blocking depends on the accessibility service. If Android turned it off '
          '(a reboot, a battery optimiser, or a manual toggle) the dashboard '
          'shows the permission banner and nothing is enforced until it is on '
          'again. Open Advanced Settings → Permissions to check.',
    ),
    (
      'Why does the app need accessibility access?',
      'Android only lets one service notice which app is in the foreground and '
          'draw over it. That is exactly what the block screen needs. The '
          'service cannot read window content unless a keyword rule asks for '
          'the visible text, and it never leaves the device.',
    ),
    (
      'What belongs in the block list?',
      'Websites are matched as host suffixes (example.com covers every '
          'subdomain), keywords are matched against visible page text and the '
          'address bar, and apps are matched by package name. The list is '
          'yours: nothing is downloaded.',
    ),
    (
      'Does Basirah use the internet?',
      'No. The release build has no INTERNET permission at all, no account, no '
          'analytics and no update check. Models and block lists ship inside '
          'the APK.',
    ),
    (
      'Can I turn protection off?',
      'Yes, from the dashboard. If you set a long-sentence password, the app '
          'asks for it before a guard can be switched off. The point is to slow '
          'a decision down, not to trap you: Android always allows you to '
          'revoke accessibility or remove an admin.',
    ),
    (
      'Why can\'t I uninstall the app?',
      'If uninstall protection is on, Android requires you to deactivate device '
          'admin first, in Settings → Security → Device admin apps. The app '
          'requests no wipe, lock or password policies.',
    ),
  ];

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showNote(BuildContext context, String title, String body) {
    return showBpDialog<void>(
      context: context,
      title: title,
      confirmLabel: 'Close',
      showActions: true,
      content: Text(body, style: context.body.copyWith(color: context.bp.ink)),
    );
  }

  Future<void> _copyReport(BuildContext context) async {
    final status = blurEngine.status;
    final report = [
      'Basirah support report',
      'version: 1.0.0',
      'platform: ${Theme.of(context).platform.name}',
      'protection enabled: ${status.protectionEnabled}',
      'accessibility enabled: ${status.accessibilityEnabled}',
      'service connected: ${status.serviceConnected}',
      'device admin: ${status.deviceAdmin}',
      'notifications: ${status.notificationsEnabled}',
      'battery optimisation ignored: ${status.batteryOptimizationIgnored}',
      'blocked apps: ${blurEngine.filters.blockedApps.length}',
      'blocked keywords: ${blurEngine.filters.keywords.length}',
      'blocked sites added: ${blurEngine.filters.customDomains.length}',
      'events recorded: ${blurEngine.totalCount}',
      'calm session running: ${blurEngine.focusActive}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: report));
    if (!context.mounted) return;
    _snack(context, 'Report copied to the clipboard');
  }

  Future<void> _copyHistory(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: blurEngine.exportJson()));
    if (!context.mounted) return;
    _snack(context, 'History copied as JSON');
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return ListenableBuilder(
      listenable: blurEngine,
      builder: (context, _) {
        return BpPage(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
          children: [
            BpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    child: Text('Help', style: context.title),
                  ),
                  Divider(height: 1, color: bp.divider, indent: 18, endIndent: 18),
                  _HighlightRow(
                    icon: Icons.lock_outline,
                    title: 'Privacy note',
                    description: 'What the app can and cannot see',
                    onTap: () => _showNote(
                      context,
                      'Privacy',
                      'Basirah has no server. It has no INTERNET permission '
                          'in the release manifest, so it cannot send anything '
                          'anywhere even by accident.\n\n'
                          'The accessibility service uses its screenshot API to '
                          'look for nudity on screen, compares the frame on the '
                          'device with a bundled model, and draws a blurred copy '
                          'over it when it finds any. Frames are not saved; the '
                          'capture log is a short local diagnostic ring buffer '
                          'you can clear at any time.\n\n'
                          'Block lists, calm sessions, the partner name and the '
                          'event history live in this app\'s private storage. '
                          'Copying a report puts it on your clipboard, where '
                          'you decide what to do with it.',
                    ),
                  ),
                  _LinkRow(
                    icon: Icons.shield_outlined,
                    title: 'How blocking works',
                    description: 'Apps, sites, keywords and screen blur',
                    onTap: () => _showNote(
                      context,
                      'How blocking works',
                      'Apps: matched by package name the moment a window opens, '
                          'before any pixels are analysed.\n\n'
                          'Sites and keywords: the service reads the visible '
                          'text and an address-bar node when it can identify '
                          'one, then matches your keywords case-insensitively '
                          '(xxx* allows wildcards).\n\n'
                          'Screen blur: a screenshot is classified on-device by '
                          'the bundled LiteRT models. Explicit frames are '
                          'covered entirely; otherwise exposed skin inside a '
                          'person\'s awrah band is covered.\n\n'
                          'Calm mode: every app that is not on the allow list '
                          'is blocked until the session timer runs out.',
                    ),
                  ),
                  _LinkRow(
                    icon: Icons.description_outlined,
                    title: 'Copy a diagnostic report',
                    description: 'Permission state and counts, for a bug report',
                    onTap: () => _copyReport(context),
                  ),
                  _LinkRow(
                    icon: Icons.ios_share_outlined,
                    title: 'Export my history',
                    description: '${blurEngine.totalCount} events as JSON',
                    onTap: () => _copyHistory(context),
                    showDivider: false,
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
                      'Frequently Asked Questions',
                      style: context.title,
                    ),
                  ),
                  Divider(height: 1, color: bp.divider, indent: 18, endIndent: 18),
                  for (var i = 0; i < _faq.length; i++)
                    _FaqTile(
                      question: _faq[i].$1,
                      answer: _faq[i].$2,
                      showDivider: i != _faq.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Basirah 1.0.0 · offline build · no account',
                style: context.small.copyWith(fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The reference's tinted "chat with support" row, kept as the first action.
class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _HighlightRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Material(
            color: bp.primarySoft.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(BpRadii.inner),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(BpRadii.inner),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Row(
                  children: [
                    Icon(icon, size: 26, color: bp.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: context.rowTitle),
                          Text(description, style: context.body),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_outward, size: 24, color: bp.ink),
                  ],
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: bp.divider, indent: 18, endIndent: 18),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool showDivider;

  const _LinkRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
            child: Row(
              children: [
                Icon(icon, size: 26, color: bp.ink),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.rowTitle),
                      Text(description, style: context.body),
                    ],
                  ),
                ),
                Icon(Icons.arrow_outward, size: 24, color: bp.ink),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: bp.divider, indent: 18, endIndent: 18),
      ],
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  final bool showDivider;

  const _FaqTile({
    required this.question,
    required this.answer,
    required this.showDivider,
  });

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.question,
                    style: context.rowTitle.copyWith(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 26,
                    color: bp.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Text(widget.answer, style: context.body),
          ),
        ),
        if (widget.showDivider)
          Divider(height: 1, color: bp.divider, indent: 18, endIndent: 18),
      ],
    );
  }
}
