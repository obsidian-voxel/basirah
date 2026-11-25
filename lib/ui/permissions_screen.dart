import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import 'blockp_theme.dart';
import 'blockp_icons.dart';
import 'brand_art.dart';

/// The permission setup page: what Basirah needs from Android, why, and one
/// action per requirement.
///
/// Each switch opens the matching Android screen; the value shown is read back
/// from the system, never assumed. The page is the first thing a new install
/// sees, so it says plainly that the app is offline and that every permission
/// can be changed later.
class PermissionsScreen extends StatefulWidget {
  /// Called by the first-run gate's Skip link. Pushed copies simply pop.
  final VoidCallback? onSkip;

  const PermissionsScreen({super.key, this.onSkip});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    blurEngine.refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) blurEngine.refreshStatus();
  }

  void _skip() {
    final onSkip = widget.onSkip;
    if (onSkip != null) {
      onSkip();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _grantAccessibility() async {
    final confirmed = await showBpDialog<bool>(
      context: context,
      title: 'Accessibility access',
      confirmLabel: 'Open Android settings',
      result: true,
      content: Text(
        'Basirah uses the accessibility service to notice which app opened '
        'and to draw the block screen over it. It cannot read your passwords '
        'or send anything anywhere: the release build has no network '
        'permission at all.\n\n'
        'After enabling it, come back to this screen.',
        style: context.body.copyWith(color: context.bp.ink),
      ),
    );
    if (confirmed != true) return;
    await nativeBridge.openAccessibilitySettings();
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Scaffold(
      backgroundColor: bp.canvas,
      body: BpCanvas(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: blurEngine,
            builder: (context, _) {
              final status = blurEngine.status;
              final allSet = status.accessibilityEnabled &&
                  status.notificationsEnabled &&
                  status.batteryOptimizationIgnored;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'SETUP',
                            style: BpType.eyebrow.copyWith(color: bp.muted),
                          ),
                        ),
                        TextButton(
                          onPressed: _skip,
                          child: Text('Skip', style: context.rowTitle),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Finish setting up',
                      style: context.display,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Android grants these three permissions itself. Basirah '
                      'cannot switch them on for you, and shows their real '
                      'state, not a promise.',
                      style: context.body,
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: bp.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: bp.divider),
                        ),
                        alignment: Alignment.center,
                        child: BasirahMark(
                          size: 52,
                          color: bp.primary,
                          strokeWidth: 3.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    BpCard(
                      child: Column(
                        children: [
                          BpRow(
                            icon: BpAbstractIcon(
                              BpAbstractIcon.system,
                              size: 22,
                              color: bp.primary,
                            ),
                            title: 'Accessibility',
                            description: status.accessibilityEnabled
                                ? 'Granted — the block screen can be drawn'
                                : 'Needed to notice apps and draw the block '
                                      'screen',
                            trailing: BpSwitch(
                              value: status.accessibilityEnabled,
                              onChanged: (_) => _grantAccessibility(),
                            ),
                          ),
                          BpRow.withIcon(
                            Icons.notifications_none,
                            title: 'Notifications',
                            description: status.notificationsEnabled
                                ? 'On — you are told when protection stops'
                                : 'Tells you if protection stops running',
                            trailing: BpSwitch(
                              value: status.notificationsEnabled,
                              onChanged: (_) async {
                                await nativeBridge
                                    .requestNotificationPermission();
                                await blurEngine.refreshStatus();
                              },
                            ),
                          ),
                          BpRow.withIcon(
                            Icons.battery_saver_outlined,
                            title: 'Battery optimization',
                            description: status.batteryOptimizationIgnored
                                ? 'Exempt — Android will not sleep the service'
                                : 'Exempting it keeps the service alive',
                            trailing: BpSwitch(
                              value: status.batteryOptimizationIgnored,
                              onChanged: (_) async {
                                await nativeBridge
                                    .requestIgnoreBatteryOptimizations();
                                await blurEngine.refreshStatus();
                              },
                            ),
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (allSet)
                      BpButton(
                        label: 'Continue',
                        icon: Icons.check,
                        onPressed: _skip,
                      )
                    else ...[
                      BpButton(
                        label: status.accessibilityEnabled
                            ? 'Continue'
                            : 'Enable accessibility',
                        onPressed: status.accessibilityEnabled
                            ? _skip
                            : _grantAccessibility,
                      ),
                      const SizedBox(height: 10),
                      BpOutlineButton(
                        label: 'Do this later',
                        onPressed: _skip,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 13,
                          color: bp.muted.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'No internet permission · no account · nothing '
                            'leaves this phone',
                            style: context.small.copyWith(
                              color: bp.muted.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
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
