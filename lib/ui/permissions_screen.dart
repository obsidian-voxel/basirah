import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import 'blockp_theme.dart';
import 'blockp_icons.dart';
import 'brand_art.dart';

/// The permission setup page, mirroring the reference's
/// "Please Enable Permissions" screen: a mark, a reassurance, three switches
/// and a short explanation of why each one is needed.
///
/// Each switch opens the matching Android screen; the value shown is read back
/// from the system, never assumed.
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
      body: DecoratedBox(
        decoration: context.bpCanvas,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: blurEngine,
            builder: (context, _) {
              final status = blurEngine.status;
              final allSet = status.accessibilityEnabled &&
                  status.notificationsEnabled &&
                  status.batteryOptimizationIgnored;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: widget.onSkip ??
                            () => Navigator.of(context).maybePop(),
                        child: Text('Skip', style: context.body),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: bp.card,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: BasirahMark(
                          size: 86,
                          color: bp.primary,
                          strokeWidth: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Please Enable Permissions',
                      textAlign: TextAlign.center,
                      style: context.display.copyWith(fontSize: 28),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Don't worry, we cannot see any of your personal data or "
                      'your browsing history.',
                      textAlign: TextAlign.center,
                      style: context.body,
                    ),
                    const SizedBox(height: 24),
                    BpCard(
                      child: Column(
                        children: [
                          BpRow(
                            icon: BpAbstractIcon(
                              BpAbstractIcon.system,
                              size: 24,
                              color: bp.ink,
                            ),
                            title: 'Accessibility permission',
                            description:
                                'Shows the block screen and notices app changes',
                            trailing: BpSwitch(
                              value: status.accessibilityEnabled,
                              onChanged: (_) => _grantAccessibility(),
                            ),
                          ),
                          BpRow.withIcon(
                            Icons.notifications_none,
                            title: 'Notifications',
                            description: 'Warns you when protection stops',
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
                            title: 'Disable battery optimization',
                            description: 'Lets the service keep running',
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
                    if (!status.accessibilityEnabled)
                      BpButton(
                        label: 'Enable accessibility',
                        onPressed: _grantAccessibility,
                      ),
                    if (allSet)
                      BpButton(
                        label: 'Continue',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      'You can always change these settings later, from '
                      'Advanced Settings.',
                      textAlign: TextAlign.center,
                      style: context.small,
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
