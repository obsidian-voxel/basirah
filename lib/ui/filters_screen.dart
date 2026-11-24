import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import '../src/block_rules.dart';
import 'theme.dart';
import 'widgets.dart';

/// Defense-in-depth filters: what the accessibility service blocks from the
/// window's package, URL and text, before any pixels are analysed.
class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  final TextEditingController _appController = TextEditingController();
  final TextEditingController _keywordController = TextEditingController();
  String? _appError;
  String? _keywordError;

  @override
  void dispose() {
    _appController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addApp() async {
    final package = _appController.text.trim();
    if (!package.contains('.') || package.length < 5) {
      setState(() => _appError = 'Enter a package like com.example.app');
      return;
    }
    await blurEngine.addBlockedApp(package);
    _appController.clear();
    if (!mounted) return;
    setState(() => _appError = null);
    _snack('$package will be blocked');
  }

  Future<void> _addKeyword() async {
    final keyword = _keywordController.text.trim();
    if (!RegExp(r'[a-z0-9]', caseSensitive: false).hasMatch(keyword) ||
        keyword.length < 2) {
      setState(() => _keywordError = 'Enter a word of at least 2 characters');
      return;
    }
    await blurEngine.addBlockedKeyword(keyword);
    _keywordController.clear();
    if (!mounted) return;
    setState(() => _keywordError = null);
    _snack('"$keyword" will be blocked');
  }

  Future<void> _pickInstalledApps() async {
    final installed = await nativeBridge.listApps();
    if (!mounted) return;
    if (installed.isEmpty) {
      _snack(nativeBridge.isSupported
          ? 'No launchable apps were reported by Android.'
          : 'Installed-app picking is Android only.');
      return;
    }
    final blocked = blurEngine.filters.blockedApps.toSet();
    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (context) => _AppPickerDialog(
        apps: installed.where((app) => !blocked.contains(app.packageName)).toList(),
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    for (final package in chosen) {
      await blurEngine.addBlockedApp(package);
    }
    _snack('${chosen.length} app(s) blocked');
  }

  Future<void> _editSchedule(String package) async {
    final current = blurEngine.filters.schedules[package];
    final start = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 18, minute: 0)
          : TimeOfDay(hour: current.startMinute ~/ 60, minute: current.startMinute % 60),
      helpText: 'Allowed from',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 20, minute: 0)
          : TimeOfDay(hour: current.endMinute ~/ 60, minute: current.endMinute % 60),
      helpText: 'Allowed until',
    );
    if (end == null) return;
    await blurEngine.setAppSchedule(
      package,
      ScheduleWindow(start.hour * 60 + start.minute, end.hour * 60 + end.minute),
    );
    _snack('$package is only allowed inside that window');
  }

  Future<void> _editLimit(String package) async {
    final current = blurEngine.filters.dailyLimits[package] ?? 0;
    var minutes = current;
    final saved = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Daily limit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                minutes <= 0
                    ? 'No limit for this app.'
                    : '$minutes minutes per day',
                style: const TextStyle(fontSize: 14),
              ),
              Slider(
                value: minutes.toDouble(),
                min: 0,
                max: 180,
                divisions: 12,
                label: minutes <= 0 ? 'Off' : '${minutes}m',
                onChanged: (value) =>
                    setDialogState(() => minutes = value.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, minutes),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await blurEngine.setDailyLimit(package, saved);
    _snack(saved <= 0 ? 'Limit removed' : '$package limited to $saved min/day');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Filters & Blocklists')),
      body: ListenableBuilder(
        listenable: blurEngine,
        builder: (context, _) {
          final apps = blurEngine.filters.blockedApps;
          final keywords = blurEngine.filters.keywords;
          final schedules = blurEngine.filters.schedules;
          final limits = blurEngine.filters.dailyLimits;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Text(
                'These rules run before anything is on screen: the app, the URL '
                'and the visible text are checked by the accessibility service, '
                'so they work even when visual detection would not.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.paletteMuted,
                ),
              ),
              const SizedBox(height: 20),

              SectionTitle(
                'Blocked apps',
                subtitle:
                    'Blocked the moment they open — no detection, no keyword '
                    'needed. ${apps.length} app(s).',
              ),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < apps.length; i++) ...[
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.block, size: 20),
                        title: Text(
                          apps[i],
                          style: TextStyle(
                            fontSize: 13,
                            color: context.paletteInk,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => blurEngine.removeBlockedApp(apps[i]),
                        ),
                      ),
                      if (i < apps.length - 1)
                        Divider(height: 1, color: context.paletteBorder),
                    ],
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.apps, size: 20),
                      title: const Text('Choose installed apps'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickInstalledApps,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _appController,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: 'com.example.app',
                        errorText: _appError,
                      ),
                      onSubmitted: (_) => _addApp(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _addApp,
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              SectionTitle(
                'Blocked keywords',
                subtitle:
                    'Matched against the URL, page title and visible text. '
                    'Wildcards work: xxx* . ${keywords.length} keyword(s).',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final keyword in keywords)
                    _ItemChip(
                      label: keyword,
                      onDelete: () => blurEngine.removeBlockedKeyword(keyword),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in DefaultBlocklists.presets)
                    ActionChip(
                      avatar: const Icon(Icons.playlist_add, size: 16),
                      label: Text(preset.name),
                      onPressed: () async {
                        await blurEngine.addKeywordPreset(preset);
                        _snack('${preset.name} pack added');
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keywordController,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: 'keyword or xxx*',
                        errorText: _keywordError,
                      ),
                      onSubmitted: (_) => _addKeyword(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _addKeyword,
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              SectionTitle(
                'Schedules & daily limits',
                subtitle:
                    'Schedules allow an app only inside the chosen hours; the '
                    'daily limit blocks it once the cap is used up until '
                    'midnight.',
              ),
              if (apps.isEmpty)
                const EmptyState(
                  icon: Icons.schedule,
                  title: 'No apps to schedule',
                  message: 'Add a blocked app first, then set its hours.',
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < apps.length; i++) ...[
                        ListTile(
                          leading: const Icon(Icons.schedule, size: 20),
                          title: Text(
                            shortPackage(apps[i]),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.paletteInk,
                            ),
                          ),
                          subtitle: Text(
                            'Allowed ${schedules[apps[i]]?.label ?? 'any time'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.paletteMuted,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Set allowed hours',
                                icon: const Icon(Icons.access_time, size: 20),
                                onPressed: () => _editSchedule(apps[i]),
                              ),
                              if (schedules.containsKey(apps[i]))
                                IconButton(
                                  tooltip: 'Clear hours',
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () async {
                                    await blurEngine.setAppSchedule(apps[i], null);
                                    _snack('Hours cleared');
                                  },
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                          child: Row(
                            children: [
                              Text(
                                limits.containsKey(apps[i])
                                    ? '${limits[apps[i]]} min/day'
                                    : 'No daily limit',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.paletteMuted,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => _editLimit(apps[i]),
                                child: const Text('Set limit'),
                              ),
                            ],
                          ),
                        ),
                        if (i < apps.length - 1)
                          Divider(height: 1, color: context.paletteBorder),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: context.paletteMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Private-mode detection is conservative on purpose: it '
                        'fires only when a browser shows an incognito/private '
                        'label, never from a guess. Bypass protection cannot '
                        'stop a force-stop or a safe-mode boot; Android gives '
                        'no app that power.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: context.paletteMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  final String label;
  final VoidCallback onDelete;

  const _ItemChip({required this.label, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: context.paletteInk),
      ),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onDelete,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: StadiumBorder(side: BorderSide(color: context.paletteBorder)),
      backgroundColor: context.paletteSurface,
    );
  }
}

/// Installed-app picker. Loaded once by the caller so the dialog itself has no
/// async work to do.
class _AppPickerDialog extends StatefulWidget {
  final List<InstalledApp> apps;

  const _AppPickerDialog({required this.apps});

  @override
  State<_AppPickerDialog> createState() => _AppPickerDialogState();
}

class _AppPickerDialogState extends State<_AppPickerDialog> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final apps = widget.apps
        .where((app) =>
            _query.isEmpty ||
            app.label.toLowerCase().contains(_query.toLowerCase()) ||
            app.packageName.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return AlertDialog(
      title: const Text('Choose apps'),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(hintText: 'Search apps'),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: apps.isEmpty
                  ? const Center(child: Text('No matching apps'))
                  : ListView.builder(
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final app = apps[index];
                        final selected = _selected.contains(app.packageName);
                        return CheckboxListTile(
                          dense: true,
                          value: selected,
                          title: Text(
                            app.label.isEmpty ? app.packageName : app.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            app.packageName,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _selected.add(app.packageName);
                            } else {
                              _selected.remove(app.packageName);
                            }
                          }),
                        );
                      },
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
          child: Text('Block ${_selected.length}'),
        ),
      ],
    );
  }
}
