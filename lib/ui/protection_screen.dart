import 'package:flutter/material.dart';

import '../services/protection_service.dart';
import 'blockp_theme.dart';
import 'brand_art.dart';
import 'lock_gate.dart';

/// The protection dashboard.
///
/// It answers three questions with verified state only: which mode is running,
/// what Android currently has switched on, and which device actions this phone
/// can perform. Every value comes from the native report, which re-reads the
/// accessibility grant and the Device Owner policies on each request. A feature
/// Android cannot grant is shown as unsupported or as needing provisioning, not
/// as a green success row.
class ProtectionScreen extends StatefulWidget {
  /// Injectable for tests; production always talks to the native control
  /// channel through [ProtectionController]'s default bridge.
  final ProtectionController? controller;

  const ProtectionScreen({super.key, this.controller});

  @override
  State<ProtectionScreen> createState() => _ProtectionScreenState();
}

class _ProtectionScreenState extends State<ProtectionScreen>
    with WidgetsBindingObserver {
  late final ProtectionController _controller =
      widget.controller ?? ProtectionController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // A controller handed in by a test belongs to that test.
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// Accessibility and Device Owner state change in Android's own screens, so
  /// the report is re-read whenever this screen comes back to the front.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.refresh();
  }

  Future<void> _run(Future<ProtectionActionResult> Function() action) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _chooseTier(int index) async {
    final report = _controller.report;
    if (report == null) return;
    final target = ProtectionTier.values[index];
    if (target == report.tier) return;

    if (target == ProtectionTier.standard) {
      if (report.appliedRestrictions > 0) {
        await _removeRestrictions();
      } else {
        await _run(() => _controller.setTier(ProtectionTier.standard));
      }
      return;
    }
    if (!report.deviceOwner) {
      await _showProvisioning();
      return;
    }
    await _enableHardened();
  }

  Future<void> _enableHardened() async {
    final understood = await showBpDialog<bool>(
      context: context,
      title: 'Enable device restrictions?',
      confirmLabel: 'I understand',
      result: true,
      // Bounded so the disclosure scrolls on a short screen instead of
      // pushing the confirmation button out of the dialog.
      content: SizedBox(
        height: 300,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Bullet(
                'Prevents: Safe Mode, uninstalling or disabling apps from '
                'Settings, and a factory reset started from Settings.',
              ),
              _Bullet(
                'Does not prevent: ADB, root, a custom recovery, a '
                'firmware reflash, a Find My Mobile erasure, or holding the '
                'power button.',
              ),
              _Bullet(
                'Emergency calls, phone calls, system updates and '
                'accessibility services are left alone.',
              ),
              _Bullet(
                'Reversal: remove the restrictions on this screen '
                'whenever you want, and every change is confirmed by '
                'Android.',
              ),
              _Bullet(
                'Removing the Device Owner itself is different: Android '
                'requires a factory reset for that.',
              ),
            ],
          ),
        ),
      ),
    );
    if (understood != true || !mounted) return;

    final confirmed = await confirmWithDelay(
      context,
      title: 'Apply these restrictions now?',
      message:
          'Basirah will ask Android to apply three restrictions and block '
          'its own uninstall. Nothing is claimed until Android confirms each '
          'one, and every change is recorded in the local audit log.',
      action: 'Enable restrictions',
      seconds: 10,
    );
    if (!confirmed || !mounted) return;
    await _run(() => _controller.applyRestrictions());
  }

  Future<void> _removeRestrictions() async {
    final ok = await confirmWithDelay(
      context,
      title: 'Remove device restrictions?',
      message:
          'Android will allow uninstalling apps, force-stopping them and a '
          'factory reset from Settings again. Basirah keeps blocking; only the '
          'Device Owner restrictions are removed.',
      action: 'Remove restrictions',
      seconds: 10,
    );
    if (!ok || !mounted) return;
    await _run(() => _controller.removeRestrictions());
  }

  Future<void> _restart() async {
    final ok = await confirmWithDelay(
      context,
      title: 'Restart this phone?',
      message:
          'Basirah will ask Android to restart the phone. Your settings '
          'stay as they are and protection re-arms after the restart.',
      action: 'Restart',
      seconds: 5,
    );
    if (!ok || !mounted) return;
    await _run(() => _controller.restart());
  }

  Future<void> _turnOff() async {
    final ok = await confirmWithDelay(
      context,
      title: 'Turn off this phone?',
      message:
          'Android shows its own power menu. Choose Power off there: '
          'Basirah never switches the device off itself, and no app can.',
      action: 'Show power menu',
      seconds: 5,
    );
    if (!ok || !mounted) return;
    await _run(() => _controller.powerOff());
  }

  /// The written requirements, before anything is activated. Basirah never
  /// starts provisioning: this dialog only explains what the user must do.
  Future<void> _showProvisioning() async {
    await showBpDialog<void>(
      context: context,
      title: 'Provisioning hardened protection',
      confirmLabel: 'Close',
      content: SizedBox(
        height: 330,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What it is', style: context.rowTitle),
              const SizedBox(height: 4),
              Text(
                'Hardened protection needs this phone to be a fully managed '
                'device whose Device Owner app is Basirah. Android only grants '
                'that during device setup, never from an accessibility permission '
                'and never from this screen.',
                style: context.body,
              ),
              const SizedBox(height: 12),
              Text('Official routes', style: context.rowTitle),
              const SizedBox(height: 4),
              const _Bullet(
                'Factory-reset the phone and use Android\'s setup '
                'wizard with a QR code or NFC provisioning record.',
              ),
              const _Bullet(
                'On a spare, test device only: enable USB debugging '
                'and run the Android provisioning command from a computer:',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
                child: Text(
                  'adb shell dpm set-device-owner \\\n'
                  '  com.haramblur.haram_blur/.DeviceAdmin',
                  style: context.small.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const _Bullet(
                'The ADB route is refused when the phone already has '
                'accounts or a second user, so it usually works only before '
                'the first account is added.',
              ),
              const SizedBox(height: 12),
              Text('What it costs', style: context.rowTitle),
              const SizedBox(height: 4),
              Text(
                'Provisioning usually means erasing the phone first. A Device '
                'Owner cannot be removed in Settings: getting the phone back to '
                'normal requires a factory reset. Test on a device you can wipe.',
                style: context.body,
              ),
              const SizedBox(height: 12),
              Text('How to reverse it', style: context.rowTitle),
              const SizedBox(height: 4),
              Text(
                'Every restriction can be removed on this screen, verified by '
                'Android and logged locally. That restores normal Settings '
                'control but keeps Basirah as Device Owner, so a full reset of '
                'the phone still means a factory reset.',
                style: context.body,
              ),
              const SizedBox(height: 12),
              Text(
                'Basirah will not start provisioning, will not request an '
                'account, and cannot see the phone\'s accounts.',
                style: context.small,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Scaffold(
      backgroundColor: bp.canvas,
      body: DecoratedBox(
        decoration: context.bpCanvas,
        child: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final report = _controller.report;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(onBack: () => Navigator.of(context).maybePop()),
                    const SizedBox(height: 6),
                    if (report == null)
                      _UnavailableCard(
                        loading: _controller.loading,
                        error: _controller.error,
                        onRetry: _controller.refresh,
                      )
                    else ...[
                      _ModeCard(
                        report: report,
                        busy: _busy,
                        onTier: _chooseTier,
                        onProvisioning: _showProvisioning,
                      ),
                      if (report.notice != null) ...[
                        const SizedBox(height: 12),
                        _Notice(text: report.notice!),
                      ],
                      const SizedBox(height: 14),
                      _HealthCard(report: report),
                      const SizedBox(height: 14),
                      BpSectionCard(
                        icon: Icons.shield_outlined,
                        title: 'Protection status',
                        children: [
                          for (var i = 0; i < report.components.length; i++)
                            _FeatureRow(
                              title: _componentTitle(report.components[i].key),
                              feature: report.components[i],
                              showDivider: i != report.components.length - 1,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _RestrictionsCard(
                        report: report,
                        busy: _busy,
                        onEnable: _enableHardened,
                        onRemove: _removeRestrictions,
                        onProvisioning: _showProvisioning,
                      ),
                      const SizedBox(height: 14),
                      _ControlsCard(
                        report: report,
                        busy: _busy,
                        onRestart: _restart,
                        onTurnOff: _turnOff,
                      ),
                      const SizedBox(height: 14),
                      _RecoveryCard(report: report),
                    ],
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

String _componentTitle(String key) {
  switch (key) {
    case 'preferences':
      return 'Protection preferences';
    case 'accessibility':
      return 'Accessibility service';
    case 'detection_engine':
      return 'Detection engine';
    case 'matcher':
      return 'Keyword and URL matcher';
    case 'last_scan':
      return 'Last successful scan';
    case 'reboot_recovery':
      return 'Reboot recovery';
    case 'anti_tamper':
      return 'Anti-tamper monitoring';
    default:
      return key;
  }
}

String _restrictionTitle(String key) {
  switch (key) {
    case 'safe_boot':
      return 'Safe Mode prevention';
    case 'apps_control':
      return 'App management lock';
    case 'factory_reset':
      return 'Factory reset restriction';
    case 'uninstall_blocked':
      return 'Basirah uninstall block';
    default:
      return key;
  }
}

String _healthTitle(ProtectionState health) {
  switch (health) {
    case ProtectionState.active:
      return 'Protection active';
    case ProtectionState.temporarilyUnavailable:
      return 'Protection temporarily unavailable';
    case ProtectionState.degraded:
      return 'Protection degraded';
    case ProtectionState.disabled:
      return 'Protection disabled';
    case ProtectionState.unsupported:
      return 'Protection unsupported';
    default:
      return 'Protection status';
  }
}

IconData _healthIcon(ProtectionState health) {
  switch (health) {
    case ProtectionState.active:
      return Icons.shield_outlined;
    case ProtectionState.temporarilyUnavailable:
      return Icons.sync_problem;
    case ProtectionState.degraded:
      return Icons.priority_high;
    case ProtectionState.disabled:
      return Icons.pause_circle_outline;
    default:
      return Icons.block;
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;

  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: Icon(Icons.arrow_back, color: bp.ink),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            'Protection',
            style: context.title.copyWith(fontSize: 22),
          ),
        ),
        BasirahMark(size: 26, color: bp.primary, strokeWidth: 2.4),
        const SizedBox(width: 6),
      ],
    );
  }
}

/// The mode selector plus the verified Device Owner state.
class _ModeCard extends StatelessWidget {
  final ProtectionReport report;
  final bool busy;
  final ValueChanged<int> onTier;
  final VoidCallback onProvisioning;

  const _ModeCard({
    required this.report,
    required this.busy,
    required this.onTier,
    required this.onProvisioning,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final ownerState = report.deviceOwner
        ? ProtectionState.active
        : ProtectionState.requiresProvisioning;
    return BpCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Protection mode', style: context.title),
          const SizedBox(height: 6),
          Text(
            'Standard works on any Android phone through the accessibility '
            'service. The second mode adds Device Owner restrictions and needs '
            'a one-time provisioning step.',
            style: context.body,
          ),
          const SizedBox(height: 14),
          BpSegmented(
            labels: const ['Standard', 'Hardened'],
            index: report.tier.index,
            onChanged: busy ? (_) {} : onTier,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Device Owner',
                  style: context.rowTitle.copyWith(fontSize: 16),
                ),
              ),
              _StatePill(state: ownerState),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            report.deviceOwner
                ? 'Android reports Basirah as this device\'s Device Owner.'
                : 'No verified Device Owner. Hardened protection cannot be '
                      'activated until the phone is provisioned.',
            style: context.small,
          ),
          if (report.hardenedPending) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bp.warningBg,
                borderRadius: BorderRadius.circular(BpRadii.inner),
              ),
              child: Text(
                'Hardened protection was requested, but Standard protection is '
                'what is actually running.',
                style: context.small.copyWith(color: bp.warningInk),
              ),
            ),
          ],
          if (!report.deviceOwner) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: BpOutlineButton(
                label: 'How to provision',
                icon: Icons.help_outline,
                onPressed: onProvisioning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return BpCard(
      color: bp.warningBg,
      padding: const EdgeInsets.all(14),
      child: Text(text, style: context.small.copyWith(color: bp.warningInk)),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final ProtectionReport report;

  const _HealthCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final color = switch (report.health) {
      ProtectionState.active => bp.primary,
      ProtectionState.degraded => bp.warningInk,
      _ => bp.muted,
    };
    return BpCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bp.primarySoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(_healthIcon(report.health), size: 24, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _healthTitle(report.health),
                  style: context.title.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(report.healthDetail, style: context.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One verified feature: name, state pill and what the state means.
class _FeatureRow extends StatelessWidget {
  final String title;
  final ProtectionFeature feature;
  final bool showDivider;

  const _FeatureRow({
    required this.title,
    required this.feature,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 16, 0),
          child: Row(
            children: [
              Expanded(child: Text(title, style: context.rowTitle)),
              const SizedBox(width: 8),
              _StatePill(state: feature.state),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 3, 16, 14),
          child: Text(feature.detail, style: context.body),
        ),
        if (showDivider)
          Divider(height: 1, indent: 18, endIndent: 18, color: bp.divider),
      ],
    );
  }
}

class _RestrictionsCard extends StatelessWidget {
  final ProtectionReport report;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onRemove;
  final VoidCallback onProvisioning;

  const _RestrictionsCard({
    required this.report,
    required this.busy,
    required this.onEnable,
    required this.onRemove,
    required this.onProvisioning,
  });

  @override
  Widget build(BuildContext context) {
    final applied = report.appliedRestrictions;
    return BpSectionCard(
      icon: Icons.policy_outlined,
      title: 'Device restrictions',
      children: [
        for (var i = 0; i < report.restrictions.length; i++)
          _FeatureRow(
            title: _restrictionTitle(report.restrictions[i].key),
            feature: report.restrictions[i],
            showDivider: true,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!report.deviceOwner)
                BpButton(
                  label: 'Needs Device Owner provisioning',
                  icon: Icons.info_outline,
                  onPressed: busy ? null : onProvisioning,
                )
              else if (applied < report.restrictions.length)
                BpButton(
                  label: 'Enable hardened restrictions',
                  icon: Icons.lock_outline,
                  onPressed: busy ? null : onEnable,
                ),
              if (report.deviceOwner && applied > 0) ...[
                const SizedBox(height: 10),
                BpOutlineButton(
                  label: 'Remove restrictions',
                  icon: Icons.lock_open_outlined,
                  onPressed: busy ? null : onRemove,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlsCard extends StatelessWidget {
  final ProtectionReport report;
  final bool busy;
  final VoidCallback onRestart;
  final VoidCallback onTurnOff;

  const _ControlsCard({
    required this.report,
    required this.busy,
    required this.onRestart,
    required this.onTurnOff,
  });

  @override
  Widget build(BuildContext context) {
    final restart = report.control('restart');
    final powerOff = report.control('power_off');
    return BpSectionCard(
      icon: Icons.power_settings_new,
      title: 'Device controls',
      children: [
        BpRow.withIcon(
          Icons.restart_alt,
          title: 'Restart',
          description:
              restart?.detail ??
              'Opens Android\'s power menu; you choose the action there.',
          trailing: _PillAction(
            label: 'Restart now',
            onPressed: busy ? null : onRestart,
          ),
        ),
        BpRow.withIcon(
          Icons.power_settings_new,
          title: 'Turn off',
          description:
              powerOff?.detail ??
              'Android exposes no direct shutdown: the power menu is used.',
          trailing: _PillAction(
            label: 'Turn off now',
            onPressed: busy ? null : onTurnOff,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          child: Text(
            'If the power menu does not appear, hold the phone\'s side button '
            'until Android shows it. Basirah never claims the phone has '
            'restarted before Android does.',
            style: context.small,
          ),
        ),
      ],
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  final ProtectionReport report;

  const _RecoveryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final samsung = report.samsungDetail.isEmpty
        ? 'Device Owner policy is documented by Google and used by managed '
              'devices, but Basirah has not been validated on a physical '
              'Samsung Galaxy A56 here.'
        : report.samsungDetail;
    return BpSectionCard(
      icon: Icons.restore,
      title: 'Recovery and device notes',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Getting the phone back', style: context.rowTitle),
              const SizedBox(height: 4),
              Text(
                'Remove the device restrictions on this screen whenever you '
                'want: Basirah asks Android, reads the policy back and records '
                'the result in the local audit log. Safe Mode, app management '
                'and Settings-based reset return to normal immediately.',
                style: context.body,
              ),
              const SizedBox(height: 10),
              Text(
                'Removing the Device Owner itself is not something an app can '
                'do safely: Android requires a factory reset for that. Hardware '
                'shutdown, emergency calls and recovery mode never depend on '
                'Basirah.',
                style: context.body,
              ),
              const SizedBox(height: 12),
              Text('Samsung Galaxy A56', style: context.rowTitle),
              const SizedBox(height: 4),
              Text(samsung, style: context.small),
            ],
          ),
        ),
      ],
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  const _UnavailableCard({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return BpCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loading
                ? 'Reading Android state…'
                : 'Protection status unavailable',
            style: context.title,
          ),
          const SizedBox(height: 6),
          Text(
            error ??
                'Basirah reads every value from Android on this device, so this '
                    'panel has nothing to report here.',
            style: context.body,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: BpOutlineButton(label: 'Try again', onPressed: onRetry),
          ),
        ],
      ),
    );
  }
}

/// State badge: a dot plus the state in words. Colour is never the only
/// signal, and a green dot only appears for a state Android confirmed.
class _StatePill extends StatelessWidget {
  final ProtectionState state;

  const _StatePill({required this.state});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final dot = switch (state) {
      ProtectionState.active => bp.switchOn,
      ProtectionState.degraded => bp.warningInk,
      ProtectionState.requiresPrivilege ||
      ProtectionState.requiresProvisioning => bp.primary,
      ProtectionState.inactive => bp.muted,
      _ => bp.muted.withValues(alpha: 0.6),
    };
    return Semantics(
      container: true,
      label: 'Status: ${state.label}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: bp.innerCard,
            borderRadius: BorderRadius.circular(BpRadii.pill),
            border: Border.all(color: bp.divider.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                state.label,
                style: context.small.copyWith(
                  color: bp.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact pill for a row action, so a control reads as a button without a
/// full-width 56 dp bar inside a list row.
class _PillAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _PillAction({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: enabled
              ? bp.primarySoft
              : bp.primarySoft.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(BpRadii.pill),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(BpRadii.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(
                label,
                style: context.small.copyWith(
                  color: enabled ? bp.primary : bp.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bullet with a geometric marker: a small square, never a pointing glyph.
class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: bp.primary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.body)),
        ],
      ),
    );
  }
}
