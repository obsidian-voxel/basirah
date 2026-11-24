import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/blur_event.dart';
import '../services/blur_engine.dart';
import '../services/export_service.dart';
import 'theme.dart';
import 'widgets.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static const _palette = [
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
    AppColors.danger,
    AppColors.accent,
  ];

  Future<void> _export() async {
    try {
      final file = await exportHistoryToFile();
      await Clipboard.setData(ClipboardData(text: file.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Exported to ${file.path} (path copied)')),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: blurEngine,
      builder: (context, _) {
        final counts = blurEngine.countsByApp;
        final days = blurEngine.countsForLastDays(7);
        final today = blurEngine.todayCount;
        final total = blurEngine.totalCount;
        final events = blurEngine.recentEvents;

        return RefreshIndicator(
          onRefresh: blurEngine.refreshStatus,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 16,
              20,
              32,
            ),
            children: [
              Text(
                'Analytics',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: context.paletteInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Blur events recorded on this device. Nothing leaves your phone.',
                style: TextStyle(fontSize: 13, color: context.paletteMuted),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Blurs today',
                      value: '$today',
                      icon: Icons.visibility_off_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'All time',
                      value: '$total',
                      icon: Icons.history,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StatTile(
                label: 'Most blurred app',
                value: counts.isEmpty
                    ? 'None yet'
                    : shortPackage(
                        (counts.entries.toList()
                              ..sort((a, b) => b.value.compareTo(a.value)))
                            .first
                            .key,
                      ),
                icon: Icons.apps,
                color: AppColors.warning,
              ),
              const SizedBox(height: 24),

              const SectionTitle('Last 7 days'),
              AppCard(
                child: SizedBox(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      maxY: max(4, (days.reduce(max) * 1.25).ceilToDouble()),
                      alignment: BarChartAlignment.spaceAround,
                      barGroups: [
                        for (var i = 0; i < days.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: days[i].toDouble(),
                                width: 18,
                                color: context.palettePrimary,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5),
                                ),
                              ),
                            ],
                          ),
                      ],
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= days.length) {
                                return const SizedBox.shrink();
                              }
                              final day = DateTime.now().subtract(
                                Duration(days: days.length - 1 - index),
                              );
                              const labels = [
                                'Mon',
                                'Tue',
                                'Wed',
                                'Thu',
                                'Fri',
                                'Sat',
                                'Sun',
                              ];
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  labels[day.weekday - 1],
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.paletteMuted,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: max(
                          1,
                          (days.reduce(max) * 1.25 / 4).ceilToDouble(),
                        ),
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: context.paletteBorder,
                          strokeWidth: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const SectionTitle('Apps triggering most blurs'),
              if (counts.isEmpty)
                const EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: 'No blur events yet',
                  message:
                      'Turn protection on, or run an image through Image lab, '
                      'and per-app statistics will appear here.',
                )
              else
                AppCard(
                  child: SizedBox(
                    height: 220,
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 44,
                        sectionsSpace: 2,
                        sections: _sections(counts),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              const SectionTitle(
                'Blocks by reason',
                subtitle:
                    'What stopped each screen: the app blocklist, keywords, '
                    'URLs, schedules, daily limits or the visual model.',
              ),
              if (events.isEmpty)
                const EmptyState(
                  icon: Icons.rule,
                  title: 'No blocks recorded',
                  message: 'Reasons appear here once something is blocked.',
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final entry in _reasonCounts(events).entries)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            _reasonIcon(entry.key),
                            size: 20,
                            color: context.palettePrimary,
                          ),
                          title: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.paletteInk,
                            ),
                          ),
                          trailing: Text(
                            '${entry.value}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.paletteInk,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              const SectionTitle('Recent events'),
              if (events.isEmpty)
                const EmptyState(
                  icon: Icons.timeline,
                  title: 'Nothing recorded',
                  message: 'Event history is stored only on this device.',
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < min(events.length, 15); i++)
                        _EventRow(
                          event: events[i],
                          showDivider: i < min(events.length, 15) - 1,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: events.isEmpty ? null : _export,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export JSON'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Counts per human-readable block reason, largest first.
  Map<String, int> _reasonCounts(List<BlurEvent> events) {
    final counts = <String, int>{};
    for (final event in events) {
      final label = event.reasonLabel;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final entry in entries) entry.key: entry.value};
  }

  IconData _reasonIcon(String label) => switch (label) {
        'Blocked app' => Icons.block,
        'Blocked keyword' => Icons.text_fields,
        'Blocked URL' => Icons.link_off,
        'Outside allowed hours' => Icons.schedule,
        'Daily limit reached' => Icons.hourglass_bottom,
        'Private mode' => Icons.visibility_off,
        'Asked for support' => Icons.self_improvement,
        _ => Icons.blur_on,
      };

  List<PieChartSectionData> _sections(Map<String, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    final rest = entries.skip(5).fold<int>(0, (sum, e) => sum + e.value);
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < top.length; i++) {
      final percent = (top[i].value / total * 100).round();
      sections.add(PieChartSectionData(
        value: top[i].value.toDouble(),
        color: _palette[i % _palette.length],
        radius: 62,
        title: '$percent%',
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ));
    }
    if (rest > 0) {
      sections.add(PieChartSectionData(
        value: rest.toDouble(),
        color: _palette.last,
        radius: 62,
        title: '${(rest / total * 100).round()}%',
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ));
    }
    return sections;
  }
}

class _EventRow extends StatelessWidget {
  final BlurEvent event;
  final bool showDivider;

  const _EventRow({required this.event, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    final isImageLab = event.packageName == 'com.haramblur.haram_blur';
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            isImageLab ? Icons.photo_outlined : Icons.apps,
            size: 20,
            color: context.palettePrimary,
          ),
          title: Text(
            isImageLab ? 'Image lab' : shortPackage(event.packageName),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.paletteInk,
            ),
          ),
          subtitle: Text(
            event.metric == null
                ? '${event.reasonLabel} · ${(event.confidence * 100).round()}% '
                    'confidence'
                : '${event.reasonLabel} · '
                    '${(event.confidence * 100).round()}% confidence · '
                    '${(event.metric! * 100).round()}% score',
            style: TextStyle(fontSize: 12, color: context.paletteMuted),
          ),
          trailing: Text(
            event.timeLabel,
            style: TextStyle(fontSize: 12, color: context.paletteMuted),
          ),
        ),
        if (showDivider) Divider(height: 1, color: context.paletteBorder),
      ],
    );
  }
}
