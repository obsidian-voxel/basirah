import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/filter_store.dart';
import '../services/native_bridge.dart';
import '../src/block_rules.dart';
import 'blockp_theme.dart';
import 'lock_gate.dart';

/// Block list tab: apps, websites and keywords the user added, plus the
/// allowlist, laid out like the reference app's block-list tab.
///
/// Every row writes back to [FilterStore], which pushes the whole policy to
/// the accessibility service, so a change is enforced even with the UI closed.
class BlockListScreen extends StatefulWidget {
  const BlockListScreen({super.key});

  @override
  State<BlockListScreen> createState() => _BlockListScreenState();
}

class _BlockListScreenState extends State<BlockListScreen> {
  int _tab = 0;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Guarded edits: with a sentence password set, changing the list needs it.
  Future<bool> _ensureUnlocked() async {
    if (!blurEngine.hasLongSentencePassword) return true;
    return requireLongSentencePassword(context);
  }

  Future<void> _addItems() async {
    if (!await _ensureUnlocked()) return;
    if (!mounted) return;
    final kind = await showBpDialog<int>(
      context: context,
      title: 'Add to your block list',
      showActions: false,
      content: Column(
        children: [
          for (final entry in _tab == 0
              ? const [
                  (0, Icons.public_off_outlined, 'Website'),
                  (1, Icons.apps, 'App'),
                  (2, Icons.key_outlined, 'Keyword'),
                ]
              : const [
                  (3, Icons.public_outlined, 'Trusted website'),
                  (1, Icons.apps, 'Trusted app'),
                ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BpOutlineButton(
                label: entry.$3,
                icon: entry.$2,
                onPressed: () => Navigator.of(context).pop(entry.$1),
              ),
            ),
        ],
      ),
    );
    if (kind == null || !mounted) return;
    switch (kind) {
      case 0:
        await _addWebsite();
      case 1:
        await _addApps(allowList: _tab == 1);
      case 2:
        await _addKeyword();
      case 3:
        await _addWebsite(trusted: true);
    }
  }

  Future<void> _addWebsite({bool trusted = false}) async {
    final controller = TextEditingController();
    final value = await showBpDialog<String>(
      context: context,
      title: trusted ? 'Trust a website' : 'Block a website',
      showActions: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'example.com'),
          ),
          const SizedBox(height: 12),
          Text(
            'Matched as a host suffix, so every subdomain is covered.',
            style: context.small,
          ),
          const SizedBox(height: 16),
          BpButton(
            label: 'Confirm',
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final domain = _normaliseDomain(value);
    if (domain == null) {
      _snack('Enter a domain like example.com');
      return;
    }
    if (trusted) {
      await blurEngine.addAllowlistedDomain(domain);
      _snack('$domain is trusted and never blocked');
      return;
    }
    await blurEngine.addBlockedDomain(domain);
    _snack('$domain will be blocked');
  }

  static String _count(int items) => items == 1 ? '1 item' : '$items items';

  static String? _normaliseDomain(String raw) {
    var value = raw.trim().toLowerCase();
    value = value.replaceFirst(RegExp(r'^https?://'), '');
    value = value.split('/').first;
    value = value.replaceFirst(RegExp(r'^www\.'), '');
    if (!value.contains('.') || value.length < 4) return null;
    if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(value)) return null;
    return value;
  }

  Future<void> _addKeyword() async {
    final controller = TextEditingController();
    var wholeWord = false;
    final value = await showBpDialog<(String, bool)>(
      context: context,
      title: 'Block a keyword',
      showActions: false,
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'keyword or xxx*'),
            ),
            const SizedBox(height: 12),
            Text(
              'Matched against visible page text and the address bar. `*` '
              'matches any ending.',
              style: context.small,
            ),
            const SizedBox(height: 8),
            BpSwitch(
              value: wholeWord,
              onChanged: (next) => setLocal(() => wholeWord = next),
            ),
            Text(
              wholeWord
                  ? 'Whole word only: “porn” will not match “pornhub”.'
                  : 'Substring: the word can appear inside a longer word.',
              style: context.small,
            ),
            const SizedBox(height: 16),
            BpButton(
              label: 'Confirm',
              onPressed: () =>
                  Navigator.of(context).pop((controller.text, wholeWord)),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null) return;
    final keyword = value.$1.trim();
    if (!KeywordValidation.isValid(keyword)) {
      _snack('Enter a word of at least 2 characters');
      return;
    }
    if (value.$2) {
      await blurEngine.addWholeWordKeyword(keyword);
      _snack('“$keyword” will be blocked as a whole word');
      return;
    }
    await blurEngine.addBlockedKeyword(keyword);
    _snack('$keyword will be blocked');
  }

  Future<void> _addApps({required bool allowList}) async {
    final installed = await nativeBridge.listApps();
    if (!mounted) return;
    if (installed.isEmpty) {
      _snack(nativeBridge.isSupported
          ? 'Android did not report any launchable apps.'
          : 'Installed-app picking is Android only.');
      return;
    }
    final already = allowList
        ? blurEngine.whitelistedApps.toSet()
        : blurEngine.filters.blockedApps.toSet();
    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AppPickerDialog(
        apps: installed
            .where((app) => !already.contains(app.packageName))
            .toList(growable: false),
        title: allowList ? 'Allow apps' : 'Block apps',
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    for (final package in chosen) {
      if (allowList) {
        await blurEngine.addWhitelistedApp(package);
      } else {
        await blurEngine.addBlockedApp(package);
      }
    }
    _snack('${chosen.length} app(s) updated');
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
        final apps = blurEngine.filters.blockedApps;
        final sites = blurEngine.filters.customDomains;
        final keywords = blurEngine.filters.keywords;
        final wholeWords = blurEngine.wholeWordKeywords;
        final allowed = blurEngine.whitelistedApps;
        final trustedSites = blurEngine.allowlistedDomains;

        return BpPage(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            BpHeader(
              title: 'Your block list',
              subtitle:
                  '${_count(apps.length + sites.length + keywords.length + wholeWords.length)} '
                  '· enforced when protection is on',
            ),
            if (missing > 0) ...[
              BpWarningBanner(
                title: missing == 1
                    ? 'One essential permission is off'
                    : '$missing essential permissions are off',
                message: '',
                onTap: null,
              ),
              const SizedBox(height: 12),
            ],
            BpSegmented(
              labels: const ['Blocklist', 'Whitelist'],
              index: _tab,
              onChanged: (index) => setState(() => _tab = index),
            ),
            const SizedBox(height: 14),
            if (_tab == 0)
              _BlocklistBody(
                apps: apps,
                sites: sites,
                keywords: keywords,
                wholeWords: wholeWords,
                schedules: blurEngine.filters.schedules,
                limits: blurEngine.filters.dailyLimits,
                onEditRules: _editAppRules,
                onRemoveApp: (package) async {
                  if (!await _ensureUnlocked()) return;
                  await blurEngine.removeBlockedApp(package);
                },
                onRemoveSite: (domain) async {
                  if (!await _ensureUnlocked()) return;
                  await blurEngine.removeBlockedDomain(domain);
                },
                onRemoveKeyword: (keyword) async {
                  if (!await _ensureUnlocked()) return;
                  await blurEngine.removeBlockedKeyword(keyword);
                },
                onRemoveWholeWord: (keyword) async {
                  if (!await _ensureUnlocked()) return;
                  await blurEngine.removeWholeWordKeyword(keyword);
                },
                onOpenPresets: () async {
                  await _addPreset();
                },
              )
            else
              _WhitelistBody(
                packages: allowed,
                sites: trustedSites,
                onRemove: (package) async {
                  if (!await _ensureUnlocked()) return;
                  await blurEngine.removeWhitelistedApp(package);
                },
                onRemoveSite: (domain) async {
                  if (!await _ensureUnlocked()) return;
                  await blurEngine.removeAllowlistedDomain(domain);
                },
              ),
            const SizedBox(height: 18),
            BpButton(
              label: _tab == 0 ? 'Add Items' : 'Trust an app or site',
              icon: Icons.add,
              onPressed: _addItems,
            ),
            if (_tab == 0) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Blocked words: ${keywords.length} · blocked apps: '
                  '${apps.length}',
                  style: context.small.copyWith(color: bp.muted),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Per-app allowed hours and daily limit, the rules the reference app keeps
  /// on its block-list rows. Both are enforced by the native service.
  Future<void> _editAppRules(String package) async {
    if (!await _ensureUnlocked()) return;
    if (!mounted) return;
    final existing = blurEngine.filters.schedules[package];
    var window = existing;
    var limit = blurEngine.filters.dailyLimits[package] ?? 0;
    final saved = await showBpDialog<bool>(
      context: context,
      title: 'Hours & daily limit',
      showActions: false,
      content: StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> pick({required bool start}) async {
            final current = window;
            final initial = start
                ? TimeOfDay(
                    hour: (current?.startMinute ?? 480) ~/ 60,
                    minute: (current?.startMinute ?? 480) % 60,
                  )
                : TimeOfDay(
                    hour: (current?.endMinute ?? 1320) ~/ 60,
                    minute: (current?.endMinute ?? 1320) % 60,
                  );
            final picked = await showTimePicker(
              context: context,
              initialTime: initial,
            );
            if (picked == null) return;
            final minute = picked.hour * 60 + picked.minute;
            setLocal(() {
              window = ScheduleWindow(
                start ? minute : (current?.startMinute ?? 480),
                start ? (current?.endMinute ?? 1320) : minute,
              );
            });
          }

          String clock(int minute) =>
              '${(minute ~/ 60).toString().padLeft(2, '0')}:'
              '${(minute % 60).toString().padLeft(2, '0')}';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _BlocklistBody._prettyPackage(package),
                style: context.rowTitle.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 14),
              Text('Allowed hours', style: context.rowTitle),
              const SizedBox(height: 6),
              Text(
                'Outside this window the app is blocked. Both ends the same '
                'means no hour restriction.',
                style: context.small,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: BpOutlineButton(
                      label: window == null
                          ? 'From 08:00'
                          : 'From ${clock(window!.startMinute)}',
                      onPressed: () => pick(start: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BpOutlineButton(
                      label: window == null
                          ? 'To 22:00'
                          : 'To ${clock(window!.endMinute)}',
                      onPressed: () => pick(start: false),
                    ),
                  ),
                ],
              ),
              if (window != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setLocal(() => window = null),
                    child: const Text('Remove hours'),
                  ),
                ),
              const SizedBox(height: 10),
              Text('Daily limit', style: context.rowTitle),
              Slider(
                value: limit.toDouble(),
                max: 240,
                divisions: 16,
                label: limit == 0 ? 'No limit' : '$limit min',
                onChanged: (value) =>
                    setLocal(() => limit = (value / 15).round() * 15),
              ),
              Text(
                limit == 0
                    ? 'No daily limit set.'
                    : '$limit minutes a day; blocked after that until '
                        'midnight.',
                style: context.small,
              ),
              const SizedBox(height: 16),
              BpButton(
                label: 'Save',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    await blurEngine.setAppSchedule(package, window);
    await blurEngine.setDailyLimit(package, limit);
    if (!mounted) return;
    _snack(
      window == null && limit == 0
          ? 'Rules cleared for ${_BlocklistBody._prettyPackage(package)}'
          : 'Rules saved for ${_BlocklistBody._prettyPackage(package)}',
    );
  }

  Future<void> _addPreset() async {
    if (!await _ensureUnlocked()) return;
    if (!mounted) return;
    final preset = await showBpDialog<int>(
      context: context,
      title: 'Keyword presets',
      showActions: false,
      content: Column(
        children: [
          for (var i = 0; i < DefaultBlocklists.presets.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BpOutlineButton(
                label:
                    '${DefaultBlocklists.presets[i].name} '
                    '(${DefaultBlocklists.presets[i].keywords.length})',
                onPressed: () => Navigator.of(context).pop(i),
              ),
            ),
        ],
      ),
    );
    if (preset == null) return;
    await blurEngine.addKeywordPreset(DefaultBlocklists.presets[preset]);
    _snack('${DefaultBlocklists.presets[preset].name} pack added');
  }
}

class _BlocklistBody extends StatelessWidget {
  final List<String> apps;
  final List<String> sites;
  final List<String> keywords;
  final List<String> wholeWords;
  final Map<String, ScheduleWindow> schedules;
  final Map<String, int> limits;
  final Future<void> Function(String) onEditRules;
  final Future<void> Function(String) onRemoveApp;
  final Future<void> Function(String) onRemoveSite;
  final Future<void> Function(String) onRemoveKeyword;
  final Future<void> Function(String) onRemoveWholeWord;
  final VoidCallback onOpenPresets;

  const _BlocklistBody({
    required this.apps,
    required this.sites,
    required this.keywords,
    required this.wholeWords,
    required this.schedules,
    required this.limits,
    required this.onEditRules,
    required this.onRemoveApp,
    required this.onRemoveSite,
    required this.onRemoveKeyword,
    required this.onRemoveWholeWord,
    required this.onOpenPresets,
  });

  /// The one line under an app row: the rules that apply, or none.
  String _appSubtitle(String package) {
    final window = schedules[package];
    final limit = limits[package] ?? 0;
    if (window == null && limit == 0) return 'No limits set';
    final parts = <String>[];
    if (window != null) parts.add('Allowed ${window.label}');
    if (limit > 0) parts.add('$limit min a day');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final empty =
        apps.isEmpty && sites.isEmpty && keywords.isEmpty && wholeWords.isEmpty;
    if (empty) {
      return BpCard(
        child: BpEmpty(
          icon: Icons.filter_alt_off_outlined,
          title: 'Nothing blocked yet',
          message:
              'Add a website, an app or a keyword. Every match is enforced '
              'whenever protection is on.',
        ),
      );
    }
    final keywordsAndWords = <(String, bool)>[
      for (final keyword in keywords) (keyword, false),
      for (final keyword in wholeWords) (keyword, true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (apps.isNotEmpty) ...[
          const _GroupLabel('Apps'),
          BpCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < apps.length; i++)
                  _ItemRow(
                    icon: Icons.apps,
                    title: _prettyPackage(apps[i]),
                    subtitle: _appSubtitle(apps[i]),
                    onTap: () => onEditRules(apps[i]),
                    onRemove: () => onRemoveApp(apps[i]),
                    showDivider: i != apps.length - 1,
                  ),
              ],
            ),
          ),
        ],
        if (sites.isNotEmpty) ...[
          const _GroupLabel('Websites'),
          BpCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < sites.length; i++)
                  _ItemRow(
                    icon: Icons.public_off_outlined,
                    title: sites[i],
                    subtitle: 'Every subdomain is covered',
                    onRemove: () => onRemoveSite(sites[i]),
                    showDivider: i != sites.length - 1,
                  ),
              ],
            ),
          ),
        ],
        if (keywordsAndWords.isNotEmpty) ...[
          const _GroupLabel('Keywords'),
          BpCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < keywordsAndWords.length; i++)
                  _ItemRow(
                    icon: Icons.key_outlined,
                    title: keywordsAndWords[i].$1,
                    subtitle: keywordsAndWords[i].$2
                        ? 'Whole word only'
                        : 'Anywhere in visible text',
                    onRemove: () => keywordsAndWords[i].$2
                        ? onRemoveWholeWord(keywordsAndWords[i].$1)
                        : onRemoveKeyword(keywordsAndWords[i].$1),
                    showDivider: i != keywordsAndWords.length - 1,
                  ),
              ],
            ),
          ),
        ],
        const _GroupLabel('Presets'),
        BpCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: BpRow.withIcon(
            Icons.auto_stories_outlined,
            title: 'Keyword presets',
            description: 'Add a ready-made pack of terms',
            onTap: onOpenPresets,
            showDivider: false,
          ),
        ),
      ],
    );
  }

  /// Turns `com.twitter.android` into `Twitter` by dropping the namespace and
  /// platform suffixes, so the list reads like a name and not a package id.
  static String _prettyPackage(String package) {
    const prefixes = {'com', 'org', 'net', 'io', 'co', 'me', 'app'};
    const suffixes = {
      'android',
      'app',
      'mobile',
      'client',
      'frontpage',
      'free',
      'lite',
    };
    var parts = package.split('.').where((p) => p.isNotEmpty).toList();
    parts = parts.where((p) => !prefixes.contains(p)).toList();
    while (parts.length > 1 && suffixes.contains(parts.last)) {
      parts = parts.sublist(0, parts.length - 1);
    }
    if (parts.isEmpty) return package;
    final name = parts.join(' ');
    return name[0].toUpperCase() + name.substring(1);
  }
}

class _ItemRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  final bool showDivider;

  const _ItemRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRemove,
    this.onTap,
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
            padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bp.primarySoft.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: bp.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.rowTitle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: Icon(Icons.close, size: 20, color: bp.muted),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 64, endIndent: 14, color: bp.divider),
      ],
    );
  }
}

/// Small caps label above a group of blocked items.
class _GroupLabel extends StatelessWidget {
  final String text;

  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: BpType.eyebrow.copyWith(color: context.bp.muted),
      ),
    );
  }
}

class _WhitelistBody extends StatelessWidget {
  final List<String> packages;
  final List<String> sites;
  final Future<void> Function(String) onRemove;
  final Future<void> Function(String) onRemoveSite;

  const _WhitelistBody({
    required this.packages,
    required this.sites,
    required this.onRemove,
    required this.onRemoveSite,
  });

  @override
  Widget build(BuildContext context) {
    final empty = packages.isEmpty && sites.isEmpty;
    if (empty) {
      return BpCard(
        child: BpEmpty(
          icon: Icons.verified_user_outlined,
          title: 'Nothing trusted yet',
          message:
              'Apps and sites on this list are never blocked, even during a '
              'calm session. A trusted site also overrides the bundled '
              'adult-site list, which is how a false positive is repaired.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (packages.isNotEmpty) ...[
          const _GroupLabel('Trusted apps'),
          BpCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < packages.length; i++)
                  _ItemRow(
                    icon: Icons.check_circle_outline,
                    title: _BlocklistBody._prettyPackage(packages[i]),
                    subtitle: packages[i],
                    onRemove: () => onRemove(packages[i]),
                    showDivider: i != packages.length - 1,
                  ),
              ],
            ),
          ),
        ],
        if (sites.isNotEmpty) ...[
          const _GroupLabel('Trusted websites'),
          BpCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < sites.length; i++)
                  _ItemRow(
                    icon: Icons.verified_outlined,
                    title: sites[i],
                    subtitle: 'Never blocked',
                    onRemove: () => onRemoveSite(sites[i]),
                    showDivider: i != sites.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AppPickerDialog extends StatefulWidget {
  final List<InstalledApp> apps;
  final String title;

  const _AppPickerDialog({required this.apps, required this.title});

  @override
  State<_AppPickerDialog> createState() => _AppPickerDialogState();
}

class _AppPickerDialogState extends State<_AppPickerDialog> {
  final Set<String> _selected = {};
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
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.toList()),
          child: Text('Save ${_selected.length}'),
        ),
      ],
    );
  }
}
