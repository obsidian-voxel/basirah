import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import 'accountability_screen.dart';
import 'affirmations_screen.dart';
import 'blockp_theme.dart';
import 'brand_art.dart';
import 'lock_gate.dart';
import 'permissions_screen.dart';
import 'protection_screen.dart';
import 'settings_screen.dart';

/// Dashboard: what protection is doing right now, this week's streak, and the
/// switches that decide what Basirah is allowed to enforce.
///
/// The reference app spent the top half of this screen on a mascot slot. There
/// is no mascot here, and an empty stage around a logo was the least useful
/// thing on the page — so the mode lives in a real card the user can change
/// without leaving the tab.
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

  /// Applies a mode from the segmented control, with the same two guards the
  /// old mode picker used: the sentence password, and a deliberate wait before
  /// protection is switched off.
  Future<void> _applyMode(ProtectionMode next) async {
    if (next == blurEngine.mode) return;
    if (next == ProtectionMode.off &&
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
    await blurEngine.setMode(next);
    if (!mounted) return;
    if (next != ProtectionMode.off && !blurEngine.status.accessibilityEnabled) {
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
      MaterialPageRoute<void>(builder: (_) => const PermissionsScreen()),
    );
    if (!mounted) return;
    await blurEngine.refreshStatus();
  }

  void _push(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: blurEngine,
      builder: (context, _) {
        final bp = context.bp;
        final status = blurEngine.status;
        final missing = [
          if (!status.accessibilityEnabled) 1,
          if (!status.notificationsEnabled) 1,
          if (!status.batteryOptimizationIgnored) 1,
        ].length;
        final mode = blurEngine.mode;

        return BpPage(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            const _BrandBar(),
            const SizedBox(height: 18),
            _StatusCard(
              mode: mode,
              missing: missing,
              accessibility: status.accessibilityEnabled,
              onModeChanged: _applyMode,
            ),
            if (missing > 0) ...[
              const SizedBox(height: 12),
              _SetupBanner(
                onTap: _openSetup,
                label: missing == 1
                    ? 'One permission left to finish setup'
                    : '$missing permissions left to finish setup',
              ),
            ],
            const BpSectionLabel('This week'),
            _StreakCard(
              streak: blurEngine.currentStreak,
              days: blurEngine.weekEventFree,
              onTap: () => widget.onOpenTab?.call(4),
            ),
            const BpSectionLabel('Bypass prevention'),
            BpCard(
              child: Column(
                children: [
                  BpRow.withIcon(
                    Icons.gpp_bad_outlined,
                    title: 'Prevent Uninstall',
                    description: status.deviceAdmin
                        ? 'Device admin is active, so Basirah cannot be removed '
                              'from Settings.'
                        : 'Stop yourself from removing the app',
                    trailing: BpSwitch(
                      value: status.deviceAdmin,
                      onChanged: _toggleUninstallProtection,
                    ),
                  ),
                  BpRow.withIcon(
                    Icons.download_for_offline_outlined,
                    title: 'Block Newly Installed Apps',
                    description: 'Anything installed from now on is blocked',
                    trailing: BpSwitch(
                      value: blurEngine.blockNewApps,
                      onChanged: (value) =>
                          blurEngine.setAdvanced(blockNewApps: value),
                    ),
                  ),
                  BpRow.withIcon(
                    Icons.travel_explore_outlined,
                    title: 'Block Newly Installed Browsers',
                    description: 'New browsers are blocked on sight',
                    trailing: BpSwitch(
                      value: blurEngine.blockNewBrowsers,
                      onChanged: (value) =>
                          blurEngine.setAdvanced(blockNewBrowsers: value),
                    ),
                    showDivider: false,
                  ),
                ],
              ),
            ),
            const BpSectionLabel('Manage'),
            BpCard(
              child: Column(
                children: [
                  BpRow.withIcon(
                    Icons.filter_alt_outlined,
                    title: 'Blocking rules',
                    description: 'Apps, websites and keywords',
                    onTap: () => widget.onOpenTab?.call(1),
                  ),
                  BpRow.withIcon(
                    Icons.link_outlined,
                    title: 'Accountability partner',
                    description: 'A trusted person and a local log',
                    onTap: () => _push(const AccountabilityScreen()),
                  ),
                  BpRow.withIcon(
                    Icons.wb_sunny_outlined,
                    title: 'Daily affirmations',
                    description: 'A short morning reflection before the phone '
                        'unlocks',
                    onTap: () => _push(const AffirmationsScreen()),
                  ),
                  BpRow.withIcon(
                    Icons.nightlight_outlined,
                    title: 'Calm mode',
                    description: 'Lock every app but the essentials for a while',
                    onTap: () => widget.onOpenTab?.call(3),
                  ),
                  BpRow.withIcon(
                    Icons.shield_outlined,
                    title: 'Protection & device controls',
                    description: 'Modes, device restrictions, restart and turn '
                        'off',
                    onTap: () => _push(const ProtectionScreen()),
                  ),
                  BpRow.withIcon(
                    Icons.tune_outlined,
                    title: 'Advanced Settings',
                    description: 'Blocking layers, sensitivity and data',
                    onTap: () => _push(const SettingsScreen()),
                    showDivider: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Row(
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
                      'Fully offline · no account · no INTERNET permission',
                      style: context.small.copyWith(
                        color: bp.muted.withValues(alpha: 0.8),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The top bar: the mark, the wordmark in both scripts, and Settings.
class _BrandBar extends StatelessWidget {
  const _BrandBar();

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bp.card,
            shape: BoxShape.circle,
            border: Border.all(color: bp.divider),
          ),
          child: BasirahMark(size: 24, color: bp.primary, strokeWidth: 2.6),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Basirah',
                style: context.title.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'بَصِيرَة',
                textDirection: TextDirection.rtl,
                style: BpType.arabic.copyWith(
                  fontSize: 12,
                  height: 1.2,
                  color: bp.muted,
                ),
              ),
            ],
          ),
        ),
        _CircleButton(
          tooltip: 'Settings',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
          child: Icon(Icons.settings_outlined, size: 21, color: bp.ink),
        ),
        const SizedBox(width: 8),
        _CircleButton(
          tooltip: 'Accountability partner',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AccountabilityScreen(),
            ),
          ),
          child: Icon(Icons.people_outline, size: 21, color: bp.ink),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  const _CircleButton({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bp.card,
        shape: CircleBorder(side: BorderSide(color: bp.divider)),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// The state of protection, and the control that changes it.
class _StatusCard extends StatelessWidget {
  final ProtectionMode mode;
  final int missing;
  final bool accessibility;
  final ValueChanged<ProtectionMode> onModeChanged;

  const _StatusCard({
    required this.mode,
    required this.missing,
    required this.accessibility,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final protected = accessibility && mode != ProtectionMode.off;
    final accent = protected
        ? const Color(0xFF12A85C)
        : (missing > 0 ? bp.warningInk : bp.muted);
    final label = protected
        ? 'Protected'
        : (missing > 0 ? 'Setup needed' : 'Not protecting');

    return BpCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PROTECTION',
                  style: BpType.eyebrow.copyWith(
                    color: bp.muted,
                    fontSize: 10.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: BpType.small.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(mode.label, style: context.display.copyWith(fontSize: 32)),
          const SizedBox(height: 4),
          Text(_lineFor(mode, accessibility), style: context.body),
          const SizedBox(height: 16),
          BpSegmented(
            labels: const ['Off', 'Normal', 'Strict'],
            index: mode.index,
            onChanged: (index) => onModeChanged(ProtectionMode.values[index]),
          ),
        ],
      ),
    );
  }

  /// One honest sentence: what the mode means, and whether it is actually
  /// running yet. Without the accessibility service nothing is enforced, so
  /// the card must not claim otherwise.
  String _lineFor(ProtectionMode mode, bool accessibility) {
    if (!accessibility) {
      return mode == ProtectionMode.off
          ? 'Switched off, and setup is not finished yet.'
          : 'Set up, but Android is not running the service yet.';
    }
    switch (mode) {
      case ProtectionMode.off:
        return 'Basirah is switched off. Nothing is blocked.';
      case ProtectionMode.normal:
        return 'Block lists, screen blur and time limits are enforcing.';
      case ProtectionMode.strict:
        return 'Maximum sensitivity, and bypass options are tightened.';
    }
  }
}

/// Blue "Finish setting up your app" strip.
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              BpSetupIcon(size: 22, color: bp.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.rowTitle,
                ),
              ),
              Icon(Icons.arrow_forward, size: 18, color: bp.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Streak card: the count, one line of context and the seven day pips.
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bp.primarySoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  size: 20,
                  color: bp.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      streak > 0 ? '$streak-Day Streak' : 'Start your streak',
                      style: context.rowTitle.copyWith(fontSize: 15.5),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      streak > 0
                          ? 'Keep going — a day without a block counts.'
                          : 'Reclaim your time and focus.',
                      style: context.small,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: bp.muted),
            ],
          ),
          const SizedBox(height: 12),
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
    final start = now.subtract(Duration(days: now.weekday % 7));
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
                width: 34,
                child: Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday ? bp.primary : bp.innerCard,
                        border: Border.all(
                          color: isToday ? bp.primary : bp.divider,
                        ),
                      ),
                      child: done && !isToday
                          ? Icon(Icons.check, size: 18, color: bp.primary)
                          : Text(
                              '${date.day}',
                              style: BpType.small.copyWith(
                                color: isToday ? Colors.white : bp.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _letters[date.weekday % 7],
                      style: BpType.small.copyWith(
                        color: isToday ? bp.primary : bp.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
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
