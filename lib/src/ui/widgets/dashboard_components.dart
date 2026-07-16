import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/analytics.dart';
import '../app_theme.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: padding, child: child),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.accent = AppColors.primary,
    this.change,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;
  final double? change;

  @override
  Widget build(BuildContext context) {
    final changeValue = change;
    return DashboardCard(
      child: SizedBox(
        height: 126,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 17, color: accent),
                ),
                const Spacer(),
                if (changeValue != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: changeValue >= 0
                          ? AppColors.primarySoft
                          : AppColors.orangeSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${changeValue >= 0 ? '+' : ''}${(changeValue * 100).round()}%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: changeValue >= 0
                            ? AppColors.primary
                            : const Color(0xFFB4682D),
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: Theme.of(context).textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class PromptTrendChart extends StatelessWidget {
  const PromptTrendChart({super.key, required this.data});

  final List<DayBucket> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const EmptyChart();
    final maximum = data.fold<int>(
      0,
      (max, point) => math.max(max, point.value),
    );
    final yMax = math.max(4, maximum + math.max(1, (maximum * 0.18).ceil()));
    final labelIndexes = _labelIndexes(data.length, 5);
    final spots = <FlSpot>[
      for (var index = 0; index < data.length; index += 1)
        FlSpot(index.toDouble(), data[index].value.toDouble()),
    ];
    return SizedBox(
      height: 360,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(1, data.length - 1).toDouble(),
          minY: 0,
          maxY: yMax.toDouble(),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: math.max(1, (yMax / 4).ceil()).toDouble(),
            getDrawingHorizontalLine: (_) => const FlLine(
              color: AppColors.border,
              strokeWidth: 1,
              dashArray: [4, 5],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: math.max(1, (yMax / 4).ceil()).toDouble(),
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  space: 8,
                  child: Text(
                    value.round().toString(),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (!labelIndexes.contains(index) || index >= data.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 10,
                    child: Text(
                      DateFormat(
                        data.length > 120 ? 'MMM' : 'MMM d',
                      ).format(data[index].day),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.sidebar,
              getTooltipItems: (spots) => spots.map((spot) {
                final point = data[spot.x.round()];
                return LineTooltipItem(
                  '${DateFormat('EEE, MMM d').format(point.day)}\n',
                  const TextStyle(color: Colors.white70, fontSize: 11),
                  children: [
                    TextSpan(
                      text:
                          '${point.value} prompt${point.value == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: data.length < 120,
              curveSmoothness: 0.24,
              color: AppColors.primary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: data.length <= 14,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.surface,
                  strokeWidth: 2,
                  strokeColor: AppColors.primary,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
      ),
    );
  }

  Set<int> _labelIndexes(int length, int count) {
    if (length <= count) {
      return {for (var index = 0; index < length; index++) index};
    }
    return {
      for (var index = 0; index < count; index++)
        ((length - 1) * index / (count - 1)).round(),
    };
  }
}

class LatencyChart extends StatelessWidget {
  const LatencyChart({super.key, required this.data});

  final List<LatencyBucket> data;

  @override
  Widget build(BuildContext context) {
    final maximum = data.fold<int>(
      0,
      (max, point) => math.max(max, point.count),
    );
    if (maximum == 0) {
      return const EmptyChart(message: 'No completion timing in this range');
    }
    final busiestIndex = data.indexWhere((point) => point.count == maximum);
    return SizedBox(
      height: 254,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: (maximum * 1.22).ceilToDouble(),
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= data.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 9,
                    child: Text(
                      data[index].label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.sidebar,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${data[group.x].label}\n${rod.toY.round()} runs',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          barGroups: [
            for (var index = 0; index < data.length; index += 1)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: data[index].count.toDouble(),
                    width: 30,
                    color: index == busiestIndex
                        ? AppColors.primary
                        : AppColors.primarySoft,
                    borderSide: BorderSide(
                      color: index == busiestIndex
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.22),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class WeeklyHeatmap extends StatelessWidget {
  const WeeklyHeatmap({super.key, required this.values});

  final List<List<int>> values;

  static const _firstHour = 6;
  static const _endHour = 22;

  static const _days = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    final visibleHours = List.generate(
      _endHour - _firstHour,
      (index) => _firstHour + index,
    );
    final maximum = values
        .expand((row) => visibleHours.map((hour) => row[hour]))
        .fold<int>(0, math.max);
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 48.0;
        final cellWidth = math.max(
          18.0,
          (constraints.maxWidth - labelWidth) / visibleHours.length,
        );
        final contentWidth = labelWidth + cellWidth * visibleHours.length;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: labelWidth, bottom: 8),
                  child: Row(
                    children: [
                      for (final hour in visibleHours)
                        SizedBox(
                          width: cellWidth,
                          child: (hour - _firstHour) % 4 == 0
                              ? Text(
                                  formatHour(hour),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
                for (var day = 0; day < 7; day += 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: labelWidth,
                          child: Text(
                            _days[day],
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        for (final hour in visibleHours)
                          Tooltip(
                            message:
                                '${_days[day]} ${formatHour(hour)} · ${values[day][hour]} prompt${values[day][hour] == 1 ? '' : 's'}',
                            child: Container(
                              width: cellWidth - 3,
                              height: 25,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: _heatColor(values[day][hour], maximum),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: values[day][hour] == 0
                                      ? AppColors.border
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Quiet',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(width: 7),
                    for (final level in const [0.08, 0.28, 0.5, 0.72, 1.0])
                      Container(
                        width: 16,
                        height: 8,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            AppColors.primarySoft,
                            AppColors.primary,
                            level,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    const SizedBox(width: 5),
                    Text(
                      'Busy',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _heatColor(int value, int maximum) {
    if (value == 0 || maximum == 0) return AppColors.canvas;
    final intensity = math.sqrt(value / maximum).clamp(0.12, 1.0);
    return Color.lerp(AppColors.primarySoft, AppColors.primary, intensity)!;
  }
}

class RankedBars extends StatelessWidget {
  const RankedBars({
    super.key,
    required this.data,
    this.limit = 6,
    this.valueSuffix = 'runs',
    this.showSecondary = false,
  });

  final List<CategoryMetric> data;
  final int limit;
  final String valueSuffix;
  final bool showSecondary;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const EmptyChart(message: 'No matched turn data');
    final visible = data.take(limit).toList(growable: false);
    final maximum = visible.first.value;
    const palette = <Color>[
      AppColors.primary,
      AppColors.orange,
      AppColors.pink,
      AppColors.olive,
      Color(0xFF6D91A8),
      Color(0xFF9B82BF),
    ];
    return Column(
      children: [
        for (var index = 0; index < visible.length; index += 1)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == visible.length - 1 ? 0 : 15,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        visible[index].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${formatCompact(visible[index].value)} $valueSuffix',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (showSecondary &&
                        visible[index].secondaryValue != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· ${formatCompact(visible[index].secondaryValue!)} tok',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: maximum == 0 ? 0 : visible[index].value / maximum,
                    minHeight: 7,
                    color: palette[index % palette.length],
                    backgroundColor: AppColors.canvas,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class EmptyChart extends StatelessWidget {
  const EmptyChart({super.key, this.message = 'No activity in this range'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

String formatCompact(int value) {
  if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return NumberFormat.decimalPattern().format(value);
}

String formatDuration(int? milliseconds) {
  if (milliseconds == null) return '—';
  final seconds = milliseconds / 1000;
  if (seconds < 1) return '${milliseconds}ms';
  if (seconds < 60) return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)}s';
  final minutes = seconds / 60;
  if (minutes < 60) return '${minutes.toStringAsFixed(minutes < 10 ? 1 : 0)}m';
  final hours = minutes / 60;
  return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)}h';
}

String formatHour(int hour) {
  final suffix = hour < 12 ? 'a' : 'p';
  final twelveHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelveHour$suffix';
}

String formatPercent(double? value) =>
    value == null ? '—' : '${(value * 100).round()}%';

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}
