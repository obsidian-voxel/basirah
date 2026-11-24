import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import 'accountability_screen.dart';
import 'affirmations_screen.dart';
import 'blockp_theme.dart';
import 'blockp_icons.dart';
import 'brand_art.dart';
import 'lock_gate.dart';
import 'permissions_screen.dart';
import 'protection_screen.dart';
import 'settings_screen.dart';

/// Dashboard: the protection state, the streak and the bypass-prevention
/// switches, laid out like the reference app's home tab.
///
/// The reference's dog mascot is replaced by [BasirahMark] (see brand_art.dart).
class HomeScreen extends StatefulWidget {
  /// Used by rows that jump to another tab.
  final void Function(int index)? onOpenTab;

  const HomeScreen({super.key, this.onOpenTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Permission state is granted in system screens, so re-read it on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) blurEngine.refreshStatus();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickMode() async {
    final chosen = await showBpDialog<int>(
      context: context,
      title: 'Protection mode',
      result: null,
      showActions: false,
      content: Column(
        children: [
          for (final mode in ProtectionMode.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BpOutlineButton(
                label: mode.label,
                onPressed: () => Navigator.of(context).pop(mode.index),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final mode = ProtectionMode.values[chosen];
    // Turning protection off is the one change worth slowing down: it needs
    // the sentence (if set) and a deliberate wait.
    if (mode == ProtectionMode.off &&
        blurEngine.mode != ProtectionMode.off) {
      if (!await requireLongSentencePassword(context)) return;
      if (!mounted) return;
      final ok = await confirmWithDelay(
        context,
        title: 'Turn protection off?',
        message:
            'Blocking stops and this phone becomes unprotected until you turn '
            'it back on.',
        action: 'Turn off',
        seconds: 15,
      );
      if (!ok) return;
    }
    await blurEngine.setMode(mode);
    if (!mounted) return;
    if (mode != ProtectionMode.off && !blurEngine.status.accessibilityEnabled) {
      _snack('Enable the accessibility permission to protect the screen.');
    }
  }

  Future<void> _toggleUninstallProtection(bool value) async {
    if (!value) {
      _snack('Uninstall protection cannot be turned off from inside the app.');
      return;
    }
    final problem = await nativeBridge.openDeviceAdmin();
    if (!mounted) return;
    if (problem != null) {
      _snack(problem);
      return;
    }
    await blurEngine.refreshStatus();
  }

  Future<void> _openSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
                        builder: (_) => const PermissionsScreen(),
      ),
    );
    if (!mounted) return;
    await blurEngine.refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: blurEngine,
      builder: (context, _) {
        final bp = context.bp;
        final status = blurEngine.status;
        final missing = [
          if (!status.accessibilityEnabled) 'accessibility',
          if (!status.notificationsEnabled) 'notifications',
          if (!status.batteryOptimizationIgnored) 'battery',
        ].length;
        final mode = blurEngine.mode;

        return BpPage(
          // The reference's toolbar row sits 39 dp below the top edge. The
          // banners use a 14 dp gutter (`marginHorizontal` on the APK's
          // `dash_frag_permission_required_layout`), which is 37 px on the
          // 1080 px reference screen.
          padding: const EdgeInsets.fromLTRB(14, 38, 14, 28),
          children: [
            Row(
              children: [
                _CircleAction(
                  child: BpAbstractIcon(
                    BpAbstractIcon.bond,
                    size: 30,
                    color: bp.ink,
                    strokeWidth: 2.1,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountabilityScreen(),
                    ),
                  ),
                ),
                const Spacer(),
                // Basirah's wordmark: the Latin name beside its Arabic form.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Basirah',
                      style: context.title.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      'بَصِيرَة',
                      textDirection: TextDirection.rtl,
                      style: BpType.arabic.copyWith(
                        fontSize: 13,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _CircleAction(
                  child: BpSettingsIcon(size: 32, color: bp.ink),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Hero(mode: mode, onTap: _pickMode),
            if (missing > 0) ...[
              const SizedBox(height: 27),
              BpWarningBanner(
                title: 'Please enable essential permissions ($missing)',
                message: '',
                onTap: _openSetup,
              ),
              const SizedBox(height: 11),
              _SetupBanner(
                onTap: _openSetup,
                label: 'Finish setting up your app',
              ),
              const SizedBox(height: 21),
            ],
            _StreakCard(
              streak: blurEngine.currentStreak,
              days: blurEngine.weekEventFree,
              onTap: () => widget.onOpenTab?.call(4),
            ),
            const SizedBox(height: 10),
            _SettingsCard(
              deviceAdmin: status.deviceAdmin,
              onUninstall: _toggleUninstallProtection,
              engine: blurEngine,
              onAccountability: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AccountabilityScreen(),
                ),
              ),
              onAffirmations: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AffirmationsScreen(),
                ),
              ),
              onAdvanced: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
              onProtection: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProtectionScreen(),
                ),
              ),
              onCalm: () => widget.onOpenTab?.call(3),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'Fully offline · no account · no INTERNET permission',
                style: context.small.copyWith(
                  color: bp.muted.withValues(alpha: 0.75),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Circular white affordance used for the profile and settings buttons.
/// The reference draws them 49.5 dp across, 38.5 dp below the top edge.
class _CircleAction extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _CircleAction({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Material(
      color: bp.card,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 49.5,
          height: 49.5,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// The mascot slot: a large disc with the geometric mark and the mode title.
class _Hero extends StatelessWidget {
  final ProtectionMode mode;
  final VoidCallback onTap;

  const _Hero({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Column(
      children: [
        // The reference's `rive_animation_block_btn` sits between the top-bar
        // row (which ends 87 dp down) and the mode title (396 dp down), so the
        // mascot slot is 309 dp tall.
        SizedBox(
          height: 294,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      bp.card.withValues(alpha: 0.95),
                      bp.card.withValues(alpha: 0.0),
                    ],
                    stops: const [0.62, 1.0],
                  ),
                ),
              ),
              BasirahMark(
                size: 120,
                color: mode == ProtectionMode.off ? bp.ink : bp.primary,
                strokeWidth: 5,
              ),
            ],
          ),
        ),
        Text(mode.label, style: context.display),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BpRadii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _lineFor(mode),
                  style: context.body.copyWith(color: bp.muted, fontSize: 18.2),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: bp.muted.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _lineFor(ProtectionMode mode) {
    switch (mode) {
      case ProtectionMode.off:
        return 'Basirah is switched off';
      case ProtectionMode.normal:
        return 'Basirah is protecting you';
      case ProtectionMode.strict:
        return 'Basirah is in strict mode';
    }
  }
}

/// Blue "Finish setting up your app" stadium with the wrench-in-ring icon.
///
/// The reference's `dashboard_finish_setup_layout` measures 1000 x 166 px on
/// the 1080 px screen, i.e. 381 x 63 dp: a `edit_text_back_color` (#240076F4)
/// stadium over the canvas with a 33 dp `blocker_set_up_icon` at x = 40 dp,
/// the title 55 dp further along and a trailing arrow.
class _SetupBanner extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SetupBanner({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Material(
      color: bp.bannerBg,
      borderRadius: BorderRadius.circular(BpRadii.banner),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 63,
          child: Row(
            children: [
              const SizedBox(width: 25),
              BpSetupIcon(size: 27, color: bp.ink),
              const SizedBox(width: 27),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.rowTitle.copyWith(fontSize: 18.2),
                ),
              ),
              Icon(Icons.chevron_right, size: 24, color: bp.ink),
              const SizedBox(width: 25),
            ],
          ),
        ),
      ),
    );
  }
}

/// Streak card: header row plus the seven day circles.
///
/// The reference's header is a lightning bolt in a filled blue circle, the
/// title, and a chevron; below it sits a one-line description and then the
/// seven day pips.
class _StreakCard extends StatelessWidget {
  final int streak;
  final List<bool> days;
  final VoidCallback onTap;

  const _StreakCard({
    required this.streak,
    required this.days,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return BpCard(
      onTap: onTap,
      // The reference's streak card starts its bolt glyph 29 dp from the
      // card's left edge (x = 117 px on a card that starts at x = 40 px),
      // and its day circles 23 dp in.
      padding: const EdgeInsets.fromLTRB(29, 29, 23, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The reference draws a bare outlined bolt glyph, not a filled
              // blue disc.
              Icon(
                Icons.bolt_outlined,
                size: 30,
                color: bp.ink,
              ),
              const SizedBox(width: 21),
              Expanded(
                child: Text(
                  streak > 0 ? '$streak-Day Streak' : 'Start your streak',
                  style: context.title.copyWith(fontSize: 17.5),
                ),
              ),
              Icon(Icons.chevron_right, size: 22, color: bp.ink),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            streak > 0
                ? 'Next badge in ${7 - (streak % 7)} days, great work!'
                : 'Reclaim your time and focus.',
            style: context.body.copyWith(fontSize: 17.1),
          ),
          const SizedBox(height: 14),
          _DayStrip(days: days),
        ],
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  final List<bool> days;

  const _DayStrip({required this.days});

  static const _letters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final now = DateTime.now();
    // Sunday-first week, so the strip always ends on today.
    final start = now.subtract(Duration(days: now.weekday % 7));
    // The reference draws seven 39 dp circles on a 49 dp pitch, spanning
    // x = 101..979 px on the 1080 px screen.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final date = start.add(Duration(days: i));
              final isToday = i == now.weekday % 7;
              final done = i < days.length ? days[i] : false;
              return SizedBox(
                width: 39,
                child: Column(
                  children: [
                    Container(
                      width: 39,
                      height: 39,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday ? bp.primary : bp.card,
                        border: Border.all(
                          color: isToday ? bp.primary : bp.ink,
                          width: 1.6,
                        ),
                      ),
                      child: done && !isToday
                          ? Icon(Icons.check, size: 22, color: bp.primary)
                          : Text(
                              '${date.day}',
                              style: BpType.small.copyWith(
                                color: isToday ? Colors.white : bp.ink,
                                fontSize: 18.2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _letters[date.weekday % 7],
                      style: BpType.small.copyWith(
                        color: isToday ? bp.primary : bp.muted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// The dashboard's settings card, matching the reference row order.
class _SettingsCard extends StatelessWidget {
  final bool deviceAdmin;
  final ValueChanged<bool> onUninstall;
  final BlurEngine engine;
  final VoidCallback onAccountability;
  final VoidCallback onAffirmations;
  final VoidCallback onAdvanced;
  final VoidCallback onProtection;
  final VoidCallback onCalm;

  const _SettingsCard({
    required this.deviceAdmin,
    required this.onUninstall,
    required this.engine,
    required this.onAccountability,
    required this.onAffirmations,
    required this.onAdvanced,
    required this.onProtection,
    required this.onCalm,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return BpCard(
      child: Column(
        children: [
          BpRow.withIcon(
            Icons.lock_outline,
            title: 'Prevent Uninstall',
            description: deviceAdmin
                ? 'The Uninstalling of Basirah was blocked.'
                : 'Stop yourself from removing the app',
            trailing: BpSwitch(value: deviceAdmin, onChanged: onUninstall),
          ),
          BpRow.withIcon(
            Icons.download_outlined,
            title: 'Block Newly Installed Apps',
            description: 'Apps in the future',
            trailing: BpSwitch(
              value: engine.blockNewApps,
              onChanged: (value) => engine.setAdvanced(blockNewApps: value),
            ),
          ),
          BpRow.withIcon(
            Icons.public_outlined,
            title: 'Block Newly Installed Browsers',
            description: 'Browsers in the future',
            trailing: BpSwitch(
              value: engine.blockNewBrowsers,
              onChanged: (value) => engine.setAdvanced(blockNewBrowsers: value),
            ),
          ),
          BpRow(
            icon: BpAbstractIcon(
              BpAbstractIcon.bond,
              size: 24,
              color: bp.ink,
            ),
            title: 'Accountability partner',
            description:
                'You have chosen a trusted person to help you stay on track.',
            onTap: onAccountability,
          ),
          BpRow.withIcon(
            Icons.wb_sunny_outlined,
            title: 'Daily Affirmations',
            description:
                'Your phone will be locked every morning, until affirmations '
                'are spoken',
            onTap: onAffirmations,
          ),
          BpRow.withIcon(
            Icons.filter_hdr_outlined,
            title: 'Calm Mode',
            description: 'Lock every app but the essentials for a while',
            onTap: onCalm,
          ),
          // The dashboard is the protection summary; this row opens the full
          // report, the two modes and the device controls.
          BpRow.withIcon(
            Icons.shield_outlined,
            title: 'Protection & device controls',
            description: 'Modes, device restrictions, restart and turn off',
            onTap: onProtection,
          ),
          BpRow.withIcon(
            Icons.tune,
            title: 'Advanced Settings',
            description: 'Blocking layers, sensitivity and data',
            onTap: onAdvanced,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}
