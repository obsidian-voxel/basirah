import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import '../services/settings_store.dart';
import '../src/policy.dart';
import 'blockp_theme.dart';
import 'blockp_icons.dart';
import 'image_lab_screen.dart';
import 'lock_gate.dart';
import 'permissions_screen.dart';
import 'protection_screen.dart';

/// Advanced Settings, matching the reference's grouped rows and switches.
///
/// Only controls that drive the real engine are shown; anything the native
/// layer cannot enforce is named as unavailable instead of being faked.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _social = <(String, String, String)>[
    ('Instagram', 'com.instagram.android', 'Blocks the app entirely'),
    ('TikTok', 'com.zhiliaoapp.musically', 'Blocks the app entirely'),
    ('X (Twitter)', 'com.twitter.android', 'Blocks the app entirely'),
    ('Snapchat', 'com.snapchat.android', 'Blocks the app entirely'),
    ('Facebook', 'com.facebook.katana', 'Blocks the app entirely'),
    ('YouTube', 'com.google.android.youtube', 'Blocks the app entirely'),
    ('WhatsApp', 'com.whatsapp', 'Blocks the app entirely'),
    ('Telegram', 'org.telegram.messenger', 'Blocks the app entirely'),
  ];

  final TextEditingController _exclusionController = TextEditingController();

  /// Settings stay hidden behind the sentence until it is typed once per
  /// visit, which is what the lock advertises.
  bool _unlocked = false;

  @override
  void dispose() {
    _exclusionController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _sensitivityLabel(int value) {
    if (value <= 5) return 'Level $value · explicit content only';
    if (value == 6) return 'Level $value · balanced, recommended';
    if (value < 10) return 'Level $value · more exposure is blurred';
    return 'Level $value · strictest';
  }

  Future<void> _pickMode() async {
    final chosen = await showBpDialog<int>(
      context: context,
      title: 'Protection mode',
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
    if (chosen == null) return;
    await blurEngine.setMode(ProtectionMode.values[chosen]);
  }

  Future<void> _pickSensitivity() async {
    var value = blurEngine.sensitivity;
    final result = await showBpDialog<int>(
      context: context,
      title: 'Detection sensitivity',
      showActions: false,
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
          children: [
            Slider(
              value: value.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '$value',
              onChanged: (next) => setLocal(() => value = next.round()),
            ),
            Text(
              _sensitivityLabel(value),
              textAlign: TextAlign.center,
              style: context.body,
            ),
            const SizedBox(height: 16),
            BpButton(
              label: 'Save',
              onPressed: () => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await blurEngine.setSensitivity(result);
  }

  Future<void> _pickBlurStrength() async {
    final values = BlurStrength.values;
    final chosen = await showBpDialog<int>(
      context: context,
      title: 'Blur strength',
      showActions: false,
      content: Column(
        children: [
          for (var i = 0; i < values.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BpOutlineButton(
                label: values[i].name,
                onPressed: () => Navigator.of(context).pop(i),
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await blurEngine.setBlurStrength(values[chosen]);
  }

  Future<void> _toggleUninstall(bool value) async {
    if (!value) {
      _snack('Uninstall protection cannot be turned off from inside the app.');
      return;
    }
    final error = await nativeBridge.openDeviceAdmin();
    if (!mounted) return;
    if (error != null) {
      _snack(error);
      return;
    }
    await blurEngine.refreshStatus();
  }

  Future<void> _setBlockScreenCopy() async {
    final titleController = TextEditingController(text: blurEngine.blockScreenTitle);
    final bodyController =
        TextEditingController(text: blurEngine.blockScreenMessage);
    final saved = await showBpDialog<bool>(
      context: context,
      title: 'Custom block screen text',
      showActions: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: titleController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Content blocked',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bodyController,
            maxLines: 4,
            maxLength: 280,
            decoration: const InputDecoration(
              labelText: 'Message',
              hintText: 'Leave empty for the default wording',
            ),
          ),
          Text(
            'Shown on the block screen over any blocked app. Empty fields '
            'restore the shipped text.',
            style: context.small,
          ),
          const SizedBox(height: 16),
          BpButton(
            label: 'Save',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    final title = titleController.text;
    final body = bodyController.text;
    titleController.dispose();
    bodyController.dispose();
    if (saved != true) return;
    await blurEngine.setBlockScreen(title: title, message: body);
    if (!mounted) return;
    _snack(
      title.trim().isEmpty && body.trim().isEmpty
          ? 'Block screen text reset to default'
          : 'Block screen text saved',
    );
  }

  Future<void> _setLongSentencePassword() async {
    // Changing or removing an existing sentence requires knowing it.
    if (blurEngine.hasLongSentencePassword &&
        !await requireLongSentencePassword(context)) {
      return;
    }
    if (!mounted) return;
    final controller =
        TextEditingController(text: blurEngine.longSentencePassword);
    final saved = await showBpDialog<String>(
      context: context,
      title: 'Long sentence password',
      showActions: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'A random sentence of at least 20 characters',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Required before a protection guard can be switched off. Leave it '
            'empty to remove the lock.',
            style: context.small,
          ),
          const SizedBox(height: 16),
          BpButton(
            label: 'Save',
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    final value = saved.trim();
    if (value.isNotEmpty && value.length < 20) {
      _snack('Use at least 20 characters.');
      return;
    }
    await blurEngine.setLongSentencePassword(value);
    _snack(value.isEmpty ? 'Password removed' : 'Password saved');
  }

  Future<void> _manageExclusions() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final custom = blurEngine.settings.customExclusions;
          return AlertDialog(
            title: const Text('No awrah blur'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListenableBuilder(
                listenable: blurEngine,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Nudity is still blocked in these apps; only the '
                      'exposed-skin blur is skipped.',
                      style: context.body,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Always excluded: ${SettingsStore.defaultExclusions.join(', ')}',
                      style: context.small,
                    ),
                    const SizedBox(height: 8),
                    for (final package in custom)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              package,
                              style: context.small.copyWith(
                                color: context.bp.ink,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              await blurEngine.removeExclusion(package);
                              setLocal(() {});
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _exclusionController,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: 'com.example.app',
                      ),
                    ),
                    const SizedBox(height: 10),
                    BpButton(
                      label: 'Add exclusion',
                      onPressed: () async {
                        final value = _exclusionController.text.trim();
                        if (!value.contains('.') || value.length < 4) {
                          _snack('Enter a package name like com.example.app');
                          return;
                        }
                        await blurEngine.addExclusion(value);
                        _exclusionController.clear();
                        setLocal(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm({
    required String title,
    required String message,
    required String action,
    required Future<void> Function() run,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await run();
    if (!mounted) return;
    _snack('$action complete');
  }

  /// Password + countdown before protection is switched off anywhere in this
  /// screen. Returns false when the user backs out.
  Future<bool> _confirmDisableProtection() async {
    if (!await requireLongSentencePassword(context)) return false;
    if (!mounted) return false;
    return confirmWithDelay(
      context,
      title: 'Switch protection off?',
      message: 'Nothing is blocked until you switch it back on.',
      action: 'Turn off',
      seconds: 15,
    );
  }

  Future<void> _toggleLock(bool value) async {
    if (value) {
      await _setLongSentencePassword();
      return;
    }
    // Turning the lock off is a guard change, so it needs the sentence.
    if (!await requireLongSentencePassword(context)) return;
    if (!mounted) return;
    final ok = await confirmWithDelay(
      context,
      title: 'Remove the lock?',
      message:
          'Anyone holding the phone will be able to switch guards off after '
          'this.',
      action: 'Remove lock',
      seconds: 10,
    );
    if (!ok) return;
    await blurEngine.setLongSentencePassword('');
    if (!mounted) return;
    _snack('Lock removed');
  }

  /// Prayer windows are computed natively from these coordinates, so the
  /// block survives the Flutter engine being gone.
  Future<void> _configurePrayer() async {
    var enabled = blurEngine.prayerBlocking;
    var minutes = blurEngine.prayerMinutesAfter;
    var method = blurEngine.prayerMethod;
    const methods = <(String, String)>[
      ('MuslimWorldLeague', 'Muslim World League'),
      ('Egyptian', 'Egyptian'),
      ('Karachi', 'Karachi'),
      ('Isna', 'ISNA'),
      ('UmmAlQura', 'Umm al-Qura'),
    ];
    final latitude = TextEditingController(
      text: blurEngine.prayerLatitude?.toStringAsFixed(4) ?? '',
    );
    final longitude = TextEditingController(
      text: blurEngine.prayerLongitude?.toStringAsFixed(4) ?? '',
    );
    final preview = await blurEngine.prayerTimes();
    if (!mounted) {
      latitude.dispose();
      longitude.dispose();
      return;
    }
    final saved = await showBpDialog<bool>(
      context: context,
      title: 'Prayer-time blocking',
      showActions: false,
      content: StatefulBuilder(
        builder: (context, setLocal) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Times are computed on this device from the coordinates you '
                'enter. No location permission and no network are used.',
                style: context.small,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: latitude,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  hintText: '30.0444',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: longitude,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  hintText: '31.2357',
                ),
              ),
              const SizedBox(height: 12),
              BpOutlineButton(
                label: methods.firstWhere(
                  (entry) => entry.$1 == method,
                  orElse: () => methods.first,
                ).$2,
                onPressed: () => setLocal(() {
                  final index = methods.indexWhere((entry) => entry.$1 == method);
                  method = methods[(index + 1) % methods.length].$1;
                }),
              ),
              const SizedBox(height: 8),
              Text('Block for $minutes min after each prayer', style: context.body),
              Slider(
                value: minutes.toDouble(),
                min: 5,
                max: 60,
                divisions: 11,
                label: '$minutes min',
                onChanged: (value) =>
                    setLocal(() => minutes = (value / 5).round() * 5),
              ),
              BpSwitch(
                value: enabled,
                onChanged: (value) => setLocal(() => enabled = value),
              ),
              Text(
                enabled ? 'Blocking is on.' : 'Blocking is off.',
                style: context.small,
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Today: ${preview.map((w) => '${w.name} ${w.label}').join(' · ')}',
                  style: context.small,
                ),
              ],
              const SizedBox(height: 16),
              BpButton(
                label: 'Save',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
    final lat = double.tryParse(latitude.text.trim().replaceAll(',', '.'));
    final lon = double.tryParse(longitude.text.trim().replaceAll(',', '.'));
    latitude.dispose();
    longitude.dispose();
    if (saved != true) return;
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      _snack('Enter a latitude (-90…90) and a longitude (-180…180).');
      return;
    }
    await blurEngine.setPrayerPolicy(
      enabled: enabled,
      latitude: lat,
      longitude: lon,
      minutesAfter: minutes,
      method: method,
    );
    if (!mounted) return;
    _snack(enabled ? 'Prayer blocking is on' : 'Prayer blocking is off');
  }

  /// Reads the audit the service writes: device-admin transitions, Settings
  /// escapes, installs and re-baselines. Uninstall protection is only worth
  /// claiming if its state can be observed.
  Future<void> _showSecurityAudit() async {
    final entries = await blurEngine.securityAudit();
    if (!mounted) return;
    final status = blurEngine.status;
    String label(String event) => switch (event) {
          'device_admin' => 'Uninstall protection',
          'settings_escape' => 'Settings escape',
          'package_installed' => 'App installed',
          'baseline' => 'Trusted apps',
          _ => event,
        };
    await showBpDialog<void>(
      context: context,
      title: 'Security audit',
      showActions: false,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              status.deviceAdmin
                  ? 'Uninstall protection: active in Android.'
                  : 'Uninstall protection: not active in Android.',
              style: context.body,
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text('No audit entries yet.', style: context.small)
            else
              for (final entry in entries.reversed.take(12))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_stamp(entry.at)} · ${label(entry.event)}'
                    '${entry.detail.isEmpty ? '' : ' — ${entry.detail}'}',
                    style: context.small,
                  ),
                ),
            const SizedBox(height: 12),
            BpButton(
              label: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  static String _stamp(DateTime time) =>
      '${time.day.toString().padLeft(2, '0')}/'
      '${time.month.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// Scopes the in-app browser rule to the apps that actually host the
  /// bypass, instead of forcing the user to disable it everywhere.
  Future<void> _configureInAppApps() async {
    final installed = await nativeBridge.listApps();
    if (!mounted) return;
    if (installed.isEmpty) {
      _snack('Android did not report any launchable apps.');
      return;
    }
    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (_) => _InAppScopeDialog(
        apps: installed,
        selected: blurEngine.inAppBrowserApps.toSet(),
      ),
    );
    if (chosen == null) return;
    await blurEngine.setInAppBrowserApps(chosen);
    if (!mounted) return;
    _snack(
      chosen.isEmpty
          ? 'The rule applies to every app'
          : 'The rule applies to ${chosen.length} app(s)',
    );
  }

  /// Re-snapshots installed apps and browsers after a deliberate install.
  Future<void> _rebaseline() async {
    if (blurEngine.hasLongSentencePassword &&
        !await requireLongSentencePassword(context)) {
      return;
    }
    await blurEngine.rebaselineNewApps();
    if (!mounted) return;
    _snack('Every app installed right now is trusted.');
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    if (blurEngine.hasLongSentencePassword && !_unlocked) {
      return SettingsLockPanel(
        onUnlocked: () => setState(() => _unlocked = true),
      );
    }
    return Scaffold(
      backgroundColor: bp.canvas,
      body: DecoratedBox(
        decoration: context.bpCanvas,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: blurEngine,
            builder: (context, _) {
              final status = blurEngine.status;
              final blocked = blurEngine.filters.blockedApps.toSet();
              final mode = blurEngine.mode;
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
                            'Advanced Settings',
                            style: context.title.copyWith(fontSize: 22),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    BpSectionCard(
                      icon: Icons.shield_outlined,
                      title: 'Blocking',
                      children: [
                        BpRow.withIcon(
                          Icons.power_settings_new,
                          title: 'Protection',
                          description: mode == ProtectionMode.off
                              ? 'Off'
                              : status.isActive
                                  ? 'Active · ${mode.label}'
                                  : 'On, waiting for the accessibility service',
                          onTap: _pickMode,
                        ),
                        BpRow(
                          icon: BpAbstractIcon(
                            BpAbstractIcon.onDevice,
                            size: 24,
                            color: bp.ink,
                          ),
                          title: 'Visual AI Blocking',
                          description: 'On-device detection of explicit frames',
                          trailing: BpSwitch(
                            value: status.protectionEnabled,
                            onChanged: (value) async {
                              if (!value &&
                                  status.protectionEnabled &&
                                  !await _confirmDisableProtection()) {
                                return;
                              }
                              await blurEngine.setEnabled(value);
                            },
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.tune,
                          title: 'Sensitivity',
                          description: _sensitivityLabel(blurEngine.sensitivity),
                          onTap: _pickSensitivity,
                        ),
                        BpRow.withIcon(
                          Icons.blur_on_outlined,
                          title: 'Blur strength',
                          description: blurEngine.blurStrength.name,
                          onTap: _pickBlurStrength,
                        ),
                        BpRow.withIcon(
                          Icons.public_off_outlined,
                          title: 'Block unsupported Browsers',
                          description:
                              'Only Chrome, Edge, Brave, Opera and Firefox',
                          trailing: BpSwitch(
                            value: blurEngine.blockUnsupportedBrowsers,
                            onChanged: (value) => blurEngine.setAdvanced(
                              blockUnsupportedBrowsers: value,
                            ),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.image_not_supported_outlined,
                          title: 'Block image and video results',
                          description:
                              'Search result grids with explicit thumbnails',
                          trailing: BpSwitch(
                            value: blurEngine.blockImageSearch,
                            onChanged: (value) => blurEngine
                                .setAdvanced(blockImageSearch: value),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.visibility_off_outlined,
                          title: 'Block private browsing',
                          description: 'Incognito windows are blocked',
                          trailing: BpSwitch(
                            value: blurEngine.blockIncognito,
                            onChanged: (value) =>
                                blurEngine.setAdvanced(blockIncognito: value),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.splitscreen_outlined,
                          title: 'Block split screen',
                          description: 'A blocked app cannot sit beside another',
                          trailing: BpSwitch(
                            value: blurEngine.blockSplitScreen,
                            onChanged: (value) =>
                                blurEngine.setAdvanced(blockSplitScreen: value),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.web_outlined,
                          title: 'Block in-app browsers',
                          description: 'Links inside social apps open in your '
                              'browser instead',
                          trailing: BpSwitch(
                            value: blurEngine.blockInAppBrowsers,
                            onChanged: (value) => mode == ProtectionMode.off
                                ? _snack('Turn protection on first.')
                                : blurEngine
                                    .setAdvanced(blockInAppBrowsers: value),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.apps_outage,
                          title: 'In-app browser apps',
                          description: blurEngine.inAppBrowserApps.isEmpty
                              ? 'Every app'
                              : '${blurEngine.inAppBrowserApps.length} app(s) '
                                  'selected',
                          onTap: _configureInAppApps,
                        ),
                        BpRow.withIcon(
                          Icons.timer_outlined,
                          title: 'Cross block screen limit',
                          description:
                              '5 blocks in 2 min lock the screen for 5 min',
                          trailing: BpSwitch(
                            value: blurEngine.crossBlockLimit,
                            onChanged: (value) => blurEngine
                                .setAdvanced(crossBlockLimit: value),
                          ),
                        ),
                        BpRow(
                          icon: BpAbstractIcon(
                            BpAbstractIcon.scheduled,
                            size: 24,
                            color: bp.ink,
                          ),
                          title: 'Prayer-time blocking',
                          description: blurEngine.prayerBlocking
                              ? 'Locks apps for '
                                  '${blurEngine.prayerMinutesAfter} min after '
                                  'each prayer'
                              : 'Off — compute times on this device',
                          onTap: _configurePrayer,
                        ),
                        BpRow.withIcon(
                          Icons.settings_suggest_outlined,
                          title: 'Guard protection settings',
                          description:
                              'Leaves Android screens that could switch guards '
                              'off',
                          trailing: BpSwitch(
                            value: blurEngine.guardSettings,
                            onChanged: (value) => blurEngine
                                .setAdvanced(guardSettings: value),
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    BpSectionCard(
                      icon: Icons.build_outlined,
                      title: 'General',
                      children: [
                        BpRow(
                          icon: BpAbstractIcon(
                            BpAbstractIcon.system,
                            size: 24,
                            color: bp.ink,
                          ),
                          title: 'Permissions',
                          description: status.accessibilityEnabled
                              ? 'Accessibility granted'
                              : 'Accessibility required',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PermissionsScreen(),
                            ),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.image_search_outlined,
                          title: 'Image check',
                          description: 'Run the detector on a photo, on device',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ImageLabScreen(),
                            ),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.remove_red_eye_outlined,
                          title: 'No awrah blur',
                          description: 'Apps where only nudity is blocked',
                          onTap: _manageExclusions,
                        ),
                        BpRow.withIcon(
                          Icons.password_outlined,
                          title: 'Long sentence password',
                          description: blurEngine.hasLongSentencePassword
                              ? 'Set — required before a guard can be turned off'
                              : 'Not set',
                          onTap: _setLongSentencePassword,
                        ),
                        BpRow.withIcon(
                          Icons.lock_outline,
                          title: 'Uninstall protection',
                          description: status.deviceAdmin
                              ? 'Active — Android asks before removal'
                              : 'Not active in Android',
                          trailing: BpSwitch(
                            value: status.deviceAdmin,
                            onChanged: _toggleUninstall,
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.shield_outlined,
                          title: 'Protection & device controls',
                          description:
                              'Standard and hardened modes, restrictions, restart',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ProtectionScreen(),
                            ),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.receipt_long_outlined,
                          title: 'Security audit',
                          description:
                              'Device admin, Settings escapes and installs, '
                              'on this device',
                          onTap: _showSecurityAudit,
                        ),
                        BpRow.withIcon(
                          Icons.restart_alt,
                          title: 'Re-check installed apps',
                          description: 'Trust every app installed right now',
                          onTap: _rebaseline,
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    BpSectionCard(
                      icon: Icons.favorite_border,
                      title: 'Social Media Blocking',
                      children: [
                        for (var i = 0; i < _social.length; i++)
                          BpRow.withIcon(
                            Icons.block,
                            title: _social[i].$1,
                            description: _social[i].$3,
                            trailing: BpSwitch(
                              value: blocked.contains(_social[i].$2),
                              onChanged: (value) async {
                                if (value) {
                                  await blurEngine.addBlockedApp(_social[i].$2);
                                } else {
                                  await blurEngine
                                      .removeBlockedApp(_social[i].$2);
                                }
                              },
                            ),
                            showDivider: i != _social.length - 1,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    BpSectionCard(
                      icon: Icons.tune,
                      title: 'Custom Blocking',
                      children: [
                        BpRow.withIcon(
                          Icons.shield_moon_outlined,
                          title: 'Lock Basirah',
                          description: blurEngine.hasLongSentencePassword
                              ? 'On — a sentence is needed to change guards'
                              : 'A sentence is needed to change guards',
                          trailing: BpSwitch(
                            value: blurEngine.hasLongSentencePassword,
                            onChanged: _toggleLock,
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.chat_bubble_outline,
                          title: 'Custom block screen text',
                          description:
                              blurEngine.blockScreenMessage.isEmpty &&
                                      blurEngine.blockScreenTitle.isEmpty
                                  ? 'Default wording'
                                  : [
                                      if (blurEngine.blockScreenTitle.isNotEmpty)
                                        '“${blurEngine.blockScreenTitle}”',
                                      if (blurEngine.blockScreenMessage.isNotEmpty)
                                        '“${blurEngine.blockScreenMessage}”',
                                    ].join(' · '),
                          onTap: _setBlockScreenCopy,
                        ),
                        BpRow.withIcon(
                          Icons.apps,
                          title: 'Blocked apps',
                          description:
                              '${blurEngine.filters.blockedApps.length} app(s)',
                          onTap: () => _snack(
                            'Use the Block list tab to add or remove apps.',
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.rotate_left,
                          title: 'Reset all blocking rules',
                          description: 'Keeps your history and password',
                          onTap: () => _confirm(
                            title: 'Reset blocking rules?',
                            message:
                                'The app list goes back to the shipped '
                                'defaults and your own sites and keywords are '
                                'removed.',
                            action: 'Reset',
                            run: blurEngine.filters.clearAll,
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    BpSectionCard(
                      icon: Icons.storage_outlined,
                      title: 'Data',
                      children: [
                        BpRow.withIcon(
                          Icons.ios_share_outlined,
                          title: 'Export history',
                          description: '${blurEngine.totalCount} events as JSON',
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: blurEngine.exportJson()),
                            );
                            _snack('Copied to clipboard');
                          },
                        ),
                        BpRow.withIcon(
                          Icons.delete_sweep_outlined,
                          title: 'Clear detection history',
                          description: 'Keeps your settings',
                          onTap: () => _confirm(
                            title: 'Clear detection history?',
                            message:
                                'This removes every recorded blur event from '
                                'this device.',
                            action: 'Clear',
                            run: blurEngine.clearHistory,
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.delete_forever_outlined,
                          title: 'Reset everything',
                          description: 'History, lists, partner and settings',
                          onTap: () => _confirm(
                            title: 'Reset everything?',
                            message:
                                'This clears every setting on this device.',
                            action: 'Reset',
                            run: blurEngine.clearEverything,
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        'Basirah 1.0.0 · fully offline · no INTERNET '
                        'permission',
                        style: context.small.copyWith(fontSize: 11),
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

/// Picks the apps where the in-app browser rule applies. An empty selection
/// means every app, which is the rule's behaviour without configuration.
class _InAppScopeDialog extends StatefulWidget {
  final List<InstalledApp> apps;
  final Set<String> selected;

  const _InAppScopeDialog({required this.apps, required this.selected});

  @override
  State<_InAppScopeDialog> createState() => _InAppScopeDialogState();
}

class _InAppScopeDialogState extends State<_InAppScopeDialog> {
  late final Set<String> _selected = {...widget.selected};
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
      title: const Text('In-app browser apps'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            Text('Nothing selected means every app.', style: context.small),
            const SizedBox(height: 8),
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
              child: apps.isEmpty
                  ? Center(
                      child: Text('No matching apps', style: context.small),
                    )
                  : ListView(
                      children: [
                        for (final app in apps)
                          CheckboxListTile(
                            dense: true,
                            value: _selected.contains(app.packageName),
                            title: Text(
                              app.label.isEmpty
                                  ? app.packageName
                                  : app.label,
                              style: context.rowTitle.copyWith(fontSize: 15),
                            ),
                            subtitle:
                                Text(app.packageName, style: context.small),
                            onChanged: (value) => setState(() {
                              if (value == true) {
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
          onPressed: () => Navigator.pop(context, <String>[]),
          child: const Text('Every app'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: Text('Save (${_selected.length})'),
        ),
      ],
    );
  }
}
