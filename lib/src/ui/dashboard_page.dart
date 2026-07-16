import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../analytics/analytics_engine.dart';
import '../data/codex_data_source.dart';
import '../models/analytics.dart';
import 'app_theme.dart';
import 'widgets/dashboard_components.dart';

String _formatDashboardRange(DateTime start, DateTime end) {
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (sameDay) return DateFormat('MMM d, y').format(start);
  return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, y').format(end)}';
}

enum _CustomPeriodMode { singleDay, dateRange }

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.dataSource = const CodexDataSource(),
    this.initialDataset,
  });

  final CodexDataSource dataSource;
  final CodexDataset? initialDataset;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const _engine = AnalyticsEngine();

  DatePreset _preset = DatePreset.thirtyDays;
  DashboardDateRange? _customRange;
  CodexDataset? _dataset;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _dataset = widget.initialDataset;
    if (_dataset == null) unawaited(_refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dataset = await widget.dataSource.load(forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _dataset = dataset;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _changePreset(DatePreset value) {
    if (value == DatePreset.custom) {
      unawaited(_pickCustomRange());
      return;
    }
    setState(() => _preset = value);
  }

  Future<void> _pickCustomRange() async {
    final dataset = _dataset;
    if (dataset == null) return;
    final today = _dateOnly(DateTime.now());
    final earliest = dataset.prompts.isEmpty
        ? today
        : dataset.prompts
              .map((prompt) => _dateOnly(prompt.timestamp.toLocal()))
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final suggestedStart = today.subtract(const Duration(days: 6));
    final initial =
        _customRange ??
        DashboardDateRange(
          start: suggestedStart.isBefore(earliest) ? earliest : suggestedStart,
          end: today,
        );
    final mode = await showDialog<_CustomPeriodMode>(
      context: context,
      builder: (context) =>
          _CustomPeriodDialog(rangeAvailable: earliest.isBefore(today)),
    );
    if (mode == null || !mounted) return;

    DashboardDateRange? selected;
    if (mode == _CustomPeriodMode.singleDay) {
      final day = await showDatePicker(
        context: context,
        firstDate: earliest,
        lastDate: today,
        initialDate: _dateOnly(initial.start),
        helpText: 'Choose one day',
        confirmText: 'Use day',
        builder: _datePickerBuilder,
      );
      if (day != null) {
        selected = DashboardDateRange(start: day, end: day);
      }
    } else {
      final range = await showDateRangePicker(
        context: context,
        firstDate: earliest,
        lastDate: today,
        initialDateRange: DateTimeRange(
          start: _dateOnly(initial.start),
          end: _dateOnly(initial.end),
        ),
        helpText: 'Choose a Codex activity window',
        saveText: 'Apply range',
        builder: _datePickerBuilder,
      );
      if (range != null) {
        selected = DashboardDateRange(start: range.start, end: range.end);
      }
    }
    if (selected == null || !mounted) return;
    setState(() {
      _customRange = selected;
      _preset = DatePreset.custom;
    });
  }

  Widget _datePickerBuilder(BuildContext context, Widget? child) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: Theme.of(
        context,
      ).colorScheme.copyWith(primary: AppColors.primary),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    ),
    child: child!,
  );

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  Widget build(BuildContext context) {
    final dataset = _dataset;
    if (dataset == null && _loading) return const _LoadingPage();
    if (dataset == null && _error != null) {
      return _ErrorPage(error: _error!, onRetry: _refresh);
    }
    if (dataset == null) return const SizedBox.shrink();

    final slice = _engine.slice(dataset, _preset, customRange: _customRange);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidebar = constraints.maxWidth >= 1180;
          return Row(
            children: [
              if (showSidebar)
                _Sidebar(
                  preset: _preset,
                  onPresetChanged: _changePreset,
                  dataset: dataset,
                ),
              Expanded(
                child: Stack(
                  children: [
                    _DashboardBody(
                      slice: slice,
                      dataset: dataset,
                      preset: _preset,
                      showBrand: !showSidebar,
                      onPresetChanged: _changePreset,
                      onRefresh: () => _refresh(force: true),
                    ),
                    if (_loading)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(minHeight: 2),
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.slice,
    required this.dataset,
    required this.preset,
    required this.showBrand,
    required this.onPresetChanged,
    required this.onRefresh,
  });

  final DashboardSlice slice;
  final CodexDataset dataset;
  final DatePreset preset;
  final bool showBrand;
  final ValueChanged<DatePreset> onPresetChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 42),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  slice: slice,
                  dataset: dataset,
                  preset: preset,
                  showBrand: showBrand,
                  onPresetChanged: onPresetChanged,
                  onRefresh: onRefresh,
                ),
                const SizedBox(height: 24),
                _InsightBanner(slice: slice),
                const SizedBox(height: 18),
                _MetricGrid(slice: slice),
                const SizedBox(height: 18),
                _PrimaryCharts(slice: slice),
                const SizedBox(height: 18),
                _SecondaryCharts(slice: slice),
                const SizedBox(height: 18),
                _DetailCharts(slice: slice),
                const SizedBox(height: 18),
                _DataFooter(dataset: dataset, slice: slice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.slice,
    required this.dataset,
    required this.preset,
    required this.showBrand,
    required this.onPresetChanged,
    required this.onRefresh,
  });

  final DashboardSlice slice;
  final CodexDataset dataset;
  final DatePreset preset;
  final bool showBrand;
  final ValueChanged<DatePreset> onPresetChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Codex rhythm',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${_formatDashboardRange(slice.start, slice.end)} · local time',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _RangeSelector(value: preset, onChanged: onPresetChanged),
        const SizedBox(width: 12),
        Tooltip(
          message: 'Refresh the local analytics index',
          child: IconButton.outlined(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 19),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.border),
              backgroundColor: AppColors.surface,
              minimumSize: const Size.square(48),
              maximumSize: const Size.square(48),
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBrand) ...[
          const _Brand(dark: false),
          const SizedBox(height: 28),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1000) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 24),
                  controls,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 18), controls],
            );
          },
        ),
      ],
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.value, required this.onChanged});

  final DatePreset value;
  final ValueChanged<DatePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final preset in DatePreset.values)
              Padding(
                padding: EdgeInsets.only(
                  right: preset == DatePreset.values.last ? 0 : 2,
                ),
                child: InkWell(
                  key: ValueKey(
                    'range-${preset.name}-${value == preset ? 'selected' : 'idle'}',
                  ),
                  onTap: () => onChanged(preset),
                  borderRadius: BorderRadius.circular(9),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 38,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: value == preset
                          ? AppColors.sidebar
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      preset.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: value == preset ? Colors.white : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomPeriodDialog extends StatelessWidget {
  const _CustomPeriodDialog({required this.rangeAvailable});

  final bool rangeAvailable;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom period'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose one historical day or a longer date range.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _CustomPeriodOption(
                    icon: Icons.today_rounded,
                    title: 'Single day',
                    detail: 'Focus on one calendar day',
                    emphasized: true,
                    onTap: () =>
                        Navigator.pop(context, _CustomPeriodMode.singleDay),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CustomPeriodOption(
                    icon: Icons.date_range_rounded,
                    title: 'Date range',
                    detail: rangeAvailable
                        ? 'Choose a start and end date'
                        : 'Only one day is available',
                    onTap: rangeAvailable
                        ? () => Navigator.pop(
                            context,
                            _CustomPeriodMode.dateRange,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _CustomPeriodOption extends StatelessWidget {
  const _CustomPeriodOption({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: emphasized ? AppColors.primarySoft : AppColors.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: emphasized
                ? AppColors.primary.withValues(alpha: 0.25)
                : AppColors.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 112,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: emphasized ? AppColors.primary : AppColors.muted,
                  ),
                  const Spacer(),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightBanner extends StatelessWidget {
  const _InsightBanner({required this.slice});

  final DashboardSlice slice;

  @override
  Widget build(BuildContext context) {
    final primaryModel = slice.modelMix.isEmpty ? null : slice.modelMix.first;
    final hour = slice.busiestHour;
    final title = slice.promptCount == 0
        ? 'A quiet stretch for Codex.'
        : '${formatCompact(slice.promptCount)} prompts across ${slice.activeDays} active day${slice.activeDays == 1 ? '' : 's'}.';
    final details = <String>[
      if (hour != null) 'Your busiest hour starts around ${formatHour(hour)}.',
      if (primaryModel != null)
        '${primaryModel.label} handled ${formatPercent(primaryModel.value / math.max(1, slice.turns.length))} of matched runs.',
      if (slice.currentStreak > 1)
        'You are on a ${slice.currentStreak}-day streak.',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.slice});

  final DashboardSlice slice;

  @override
  Widget build(BuildContext context) {
    final cachedShare = slice.totalTokens == 0
        ? null
        : slice.cachedInputTokens / slice.totalTokens;
    final cards = <Widget>[
      MetricCard(
        key: const ValueKey('metric-prompts'),
        label: 'Prompts sent',
        value: formatCompact(slice.promptCount),
        detail:
            '${formatCompact(slice.previousPromptCount)} in the prior window',
        icon: Icons.arrow_upward_rounded,
        change: slice.promptChange,
      ),
      MetricCard(
        label: 'Active days',
        value: formatCompact(slice.activeDays),
        detail: slice.currentStreak == 0
            ? 'No current streak'
            : '${slice.currentStreak}-day current streak',
        icon: Icons.calendar_today_rounded,
        accent: AppColors.olive,
      ),
      MetricCard(
        key: const ValueKey('metric-mean-completion'),
        label: 'Mean completion',
        value: formatDuration(slice.averageCompletionMs),
        detail:
            'Median ${formatDuration(slice.medianCompletionMs)} · p90 ${formatDuration(slice.p90CompletionMs)}',
        icon: Icons.timer_outlined,
        accent: AppColors.orange,
      ),
      MetricCard(
        label: 'First response',
        value: formatDuration(slice.averageFirstResponseMs),
        detail: '${formatPercent(slice.latencyCoverage)} timing coverage',
        icon: Icons.bolt_rounded,
        accent: AppColors.pink,
      ),
      MetricCard(
        label: 'Tokens processed',
        value: formatCompact(slice.totalTokens),
        detail: cachedShare == null
            ? 'No token records'
            : '${formatPercent(cachedShare)} cached input',
        icon: Icons.data_usage_rounded,
        accent: const Color(0xFF6D91A8),
      ),
      MetricCard(
        label: 'Sessions',
        value: formatCompact(slice.sessions),
        detail: slice.sessions == 0
            ? 'No sessions'
            : '${(slice.promptCount / slice.sessions).toStringAsFixed(1)} prompts per session',
        icon: Icons.forum_outlined,
        accent: const Color(0xFF9B82BF),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 2;
        const gap = 18.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _PrimaryCharts extends StatelessWidget {
  const _PrimaryCharts({required this.slice});

  final DashboardSlice slice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 940;
        final activity = DashboardCard(
          key: const ValueKey('prompt-activity-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Prompt activity',
                subtitle: 'Messages you explicitly sent, grouped by local day',
                trailing: _Pill(
                  label: '${formatCompact(slice.promptCount)} total',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              PromptTrendChart(data: slice.dailyPrompts),
            ],
          ),
        );
        final models = DashboardCard(
          key: const ValueKey('model-mix-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Model mix',
                subtitle: 'Matched runs grouped by model',
                trailing: _Pill(
                  label: '${slice.modelMix.length} models',
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 20),
              RankedBars(data: slice.modelMix, showSecondary: true),
            ],
          ),
        );
        final reasoning = DashboardCard(
          key: const ValueKey('reasoning-mix-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Reasoning mix',
                subtitle: 'Matched runs grouped by reasoning effort',
                trailing: _Pill(
                  label: '${slice.reasoningMix.length} levels',
                  color: AppColors.pink,
                ),
              ),
              const SizedBox(height: 20),
              RankedBars(data: slice.reasoningMix, valueSuffix: 'runs'),
            ],
          ),
        );
        if (!sideBySide) {
          return Column(
            children: [
              activity,
              const SizedBox(height: 18),
              models,
              const SizedBox(height: 18),
              reasoning,
            ],
          );
        }
        const gap = 18.0;
        final columnWidth = (constraints.maxWidth - gap * 2) / 3;
        final activityWidth = columnWidth * 2 + gap;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: activityWidth, child: activity),
              const SizedBox(width: gap),
              SizedBox(
                width: columnWidth,
                child: Column(
                  children: [
                    models,
                    const SizedBox(height: gap),
                    Expanded(child: reasoning),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SecondaryCharts extends StatelessWidget {
  const _SecondaryCharts({required this.slice});

  final DashboardSlice slice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 940;
        final heatmap = DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Weekly rhythm',
                subtitle:
                    'Prompt concentration by weekday, 6am–10pm local time',
              ),
              const SizedBox(height: 20),
              WeeklyHeatmap(values: slice.hourlyHeatmap),
            ],
          ),
        );
        final latency = DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Completion time',
                subtitle: 'Distribution of completed Codex runs',
                trailing: _Pill(
                  label: '${formatPercent(slice.latencyCoverage)} coverage',
                  color: AppColors.pink,
                ),
              ),
              const SizedBox(height: 20),
              LatencyChart(data: slice.latencyDistribution),
            ],
          ),
        );
        if (!sideBySide) {
          return Column(
            children: [heatmap, const SizedBox(height: 18), latency],
          );
        }
        const gap = 18.0;
        final columnWidth = (constraints.maxWidth - gap * 2) / 3;
        final heatmapWidth = columnWidth * 2 + gap;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: heatmapWidth, child: heatmap),
            const SizedBox(width: gap),
            SizedBox(width: columnWidth, child: latency),
          ],
        );
      },
    );
  }
}

class _DetailCharts extends StatelessWidget {
  const _DetailCharts({required this.slice});

  final DashboardSlice slice;

  @override
  Widget build(BuildContext context) {
    final panels = <Widget>[
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Top workspaces',
              subtitle: 'Projects receiving the most matched runs',
            ),
            const SizedBox(height: 20),
            RankedBars(data: slice.workspaceMix, valueSuffix: 'runs'),
          ],
        ),
      ),
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Source mix',
              subtitle: 'Where your matched Codex runs were started',
            ),
            const SizedBox(height: 20),
            RankedBars(data: slice.sourceMix, valueSuffix: 'runs'),
          ],
        ),
      ),
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Codex in motion',
              subtitle: 'Runtime activity emitted during matched runs',
            ),
            const SizedBox(height: 20),
            _ActivityTile(
              label: 'Tool calls',
              value: slice.toolCalls,
              icon: Icons.build_circle_outlined,
              color: AppColors.primary,
            ),
            const SizedBox(height: 10),
            _ActivityTile(
              label: 'Patches applied',
              value: slice.patchApplications,
              icon: Icons.difference_outlined,
              color: AppColors.orange,
            ),
            const SizedBox(height: 10),
            _ActivityTile(
              label: 'Web searches',
              value: slice.webSearches,
              icon: Icons.travel_explore_rounded,
              color: AppColors.pink,
            ),
            const SizedBox(height: 10),
            _ActivityTile(
              label: 'Completion rate',
              valueText: formatPercent(slice.completionRate),
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.olive,
            ),
            const SizedBox(height: 10),
            _ActivityTile(
              label: 'Codex run time',
              valueText: formatDuration(slice.runTimeMs),
              icon: Icons.timelapse_rounded,
              color: const Color(0xFF6D91A8),
            ),
          ],
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050 ? 3 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 18) / columns;
        if (columns == 1) {
          return Column(
            children: [
              for (var index = 0; index < panels.length; index += 1) ...[
                panels[index],
                if (index != panels.length - 1) const SizedBox(height: 18),
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < panels.length; index += 1) ...[
                SizedBox(width: width, child: panels[index]),
                if (index != panels.length - 1) const SizedBox(width: 18),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.label,
    required this.icon,
    required this.color,
    this.value,
    this.valueText,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int? value;
  final String? valueText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Text(
            valueText ?? formatCompact(value ?? 0),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataFooter extends StatelessWidget {
  const _DataFooter({required this.dataset, required this.slice});

  final CodexDataset dataset;
  final DashboardSlice slice;

  @override
  Widget build(BuildContext context) {
    final warnings = dataset.warnings;
    return DashboardCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.olive.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.olive,
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Private by construction',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Read-only source: ${dataset.codexRoot} · ${dataset.sourceFileCount} matched session files · ${formatBytes(dataset.sourceBytes)} inspected · ${dataset.reusedFileCount} reused from the private aggregate cache. No prompt or response text is stored by Codex Pulse.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    warnings.join(' '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF9A632E),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Updated ${DateFormat('h:mm a').format(dataset.loadedAt)}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.preset,
    required this.onPresetChanged,
    required this.dataset,
  });

  final DatePreset preset;
  final ValueChanged<DatePreset> onPresetChanged;
  final CodexDataset dataset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      color: AppColors.sidebar,
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Brand(dark: true),
          const SizedBox(height: 42),
          const _SidebarLabel('OVERVIEW'),
          const SizedBox(height: 9),
          const _SidebarItem(
            icon: Icons.space_dashboard_rounded,
            label: 'Dashboard',
            selected: true,
          ),
          const SizedBox(height: 32),
          const _SidebarLabel('TIME WINDOW'),
          const SizedBox(height: 9),
          for (final value in DatePreset.values)
            _SidebarItem(
              icon: switch (value) {
                DatePreset.oneDay => Icons.today_outlined,
                DatePreset.sevenDays => Icons.looks_one_outlined,
                DatePreset.thirtyDays => Icons.calendar_view_week_outlined,
                DatePreset.ninetyDays => Icons.date_range_outlined,
                DatePreset.allTime => Icons.all_inclusive_rounded,
                DatePreset.custom => Icons.edit_calendar_outlined,
              },
              label: value.label,
              selected: preset == value,
              onTap: () => onPresetChanged(value),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: Color(0xFFB7C18B),
                      size: 17,
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Local & read-only',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatCompact(dataset.prompts.length)} prompt records. Nothing leaves this Mac.',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: dark ? double.infinity : 190,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: dark ? Colors.white : AppColors.sidebar,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              'C',
              style: TextStyle(
                color: dark ? AppColors.sidebar : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Codex Pulse',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dark ? Colors.white : AppColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarLabel extends StatelessWidget {
  const _SidebarLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : Colors.white54,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.sidebar,
                  borderRadius: BorderRadius.circular(19),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'C',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Reading your Codex rhythm…',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                'The first local index can take a moment. Future launches reuse a private aggregate cache with no chat text.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 180,
                child: LinearProgressIndicator(
                  minHeight: 4,
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: AppColors.olive,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '~/.codex stays read-only',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function({bool force}) onRetry;

  @override
  Widget build(BuildContext context) {
    final needsFolderAccess = error is CodexFolderAccessException;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DashboardCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  needsFolderAccess
                      ? Icons.folder_open_outlined
                      : Icons.folder_off_outlined,
                  size: 38,
                  color: AppColors.orange,
                ),
                const SizedBox(height: 18),
                Text(
                  needsFolderAccess
                      ? 'Choose your Codex folder'
                      : 'Codex data was not readable',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 9),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => onRetry(),
                  icon: Icon(
                    needsFolderAccess
                        ? Icons.folder_open_rounded
                        : Icons.refresh_rounded,
                    size: 17,
                  ),
                  label: Text(
                    needsFolderAccess ? 'Choose ~/.codex' : 'Try again',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
