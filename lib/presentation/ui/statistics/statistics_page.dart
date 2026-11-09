import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../mobile/mobile_breakpoints.dart';
import '../../mobile/mobile_scaffold.dart';
import '../kit/ui_colors.dart';
import '../kit/ui_controls.dart';
import '../kit/ui_text.dart';
import 'statistics_calendar.dart';
import 'statistics_cards.dart';
import 'statistics_contract.dart';
import 'statistics_header.dart';
import 'statistics_kpis.dart';
import 'statistics_layout.dart';
import 'statistics_production.dart';
import 'statistics_states.dart';

/// 统计页（新界面）。只吃 [StatsViewData]、只调 [StatsActions]，见 `statistics_contract.dart`。
///
/// 从上到下：顶栏 → 总数行 → 创作日历 → 产量与模型 → 什么时候画 · Anlas · 画幅 →
/// 参数习惯 · 常用画师 · 存储 → 页脚。按可用宽度三列 / 两列 / 一列。
class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key, required this.data, required this.actions});

  final StatsViewData data;
  final StatsActions actions;

  @override
  Widget build(BuildContext context) {
    final snapshot = data.snapshot;
    final Widget body;
    if (snapshot == null) {
      body = data.errorMessage == null
          ? const StatsLoadingBody()
          : StatsErrorBody(message: data.errorMessage!, actions: actions);
    } else if (snapshot.libraryTotal == 0) {
      body = StatsEmptyBody(actions: actions);
    } else {
      body = _FadeIn(
        child: _Report(data: data, snapshot: snapshot, actions: actions),
      );
    }
    if (usesMobileLayout) {
      return MobilePageScaffold(
        key: const Key('stats-mobile-page'),
        title: context.l10n.stats_title,
        showBack: false,
        backgroundColor: context.ui.page,
        actions: [
          MobileHeaderAction(
            key: const Key('stats-mobile-refresh'),
            icon: Icons.refresh_rounded,
            tooltip: context.l10n.stats_refresh,
            onTap: actions.onRefresh,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatsMobileFilters(data: data, actions: actions),
            Expanded(child: body),
          ],
        ),
      );
    }
    return ColoredBox(
      color: context.ui.page,
      child: Column(
        children: [
          StatsHeader(data: data, actions: actions),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// 手机端顶栏下的筛选条：时间范围与「仅 NAI」改成横向可滚动的一行，
/// 不再挤在标题右侧；桌面顶栏（[StatsHeader]）保持原样。
class _StatsMobileFilters extends StatelessWidget {
  const _StatsMobileFilters({required this.data, required this.actions});

  final StatsViewData data;
  final StatsActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: SizedBox(
        height: 52,
        child: SingleChildScrollView(
          key: const Key('stats-mobile-filters'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              UiSegmented<StatsRange>(
                key: const Key('stats-range'),
                height: 40,
                itemPadding: 12,
                values: StatsRange.values,
                selected: data.range,
                labelOf: (r) => switch (r) {
                  StatsRange.thisYear => l10n.stats_rangeThisYear,
                  StatsRange.all => l10n.stats_rangeAll,
                  _ => l10n.stats_rangeDays('${r.days}'),
                },
                onChanged: actions.onRangeChanged,
              ),
              const SizedBox(width: 10),
              UiChipButton(
                key: const Key('stats-nai-only'),
                height: 40,
                semanticLabel: l10n.stats_naiOnly,
                onPressed: () => actions.onNaiOnlyChanged(!data.naiOnly),
                children: [
                  Text(l10n.stats_naiOnly),
                  UiSwitch(value: data.naiOnly),
                ],
              ),
              if (data.sync == StatsSyncState.updating) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({
    required this.data,
    required this.snapshot,
    required this.actions,
  });

  final StatsViewData data;
  final StatsSnapshot snapshot;
  final StatsActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    return StatsPageFrame(
      footer: Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 4),
        child: Text(
          context.l10n.stats_footer,
          textAlign: TextAlign.center,
          style: UiText.sans(11.5, color: c.faint),
        ),
      ),
      builder: (layout) => [
        StatsKpiRow(data: data, snapshot: snapshot, layout: layout),
        StatsCalendarCard(
          data: data,
          snapshot: snapshot,
          actions: actions,
          layout: layout,
        ),
        StatsProductionCard(
          data: data,
          snapshot: snapshot,
          actions: actions,
          layout: layout,
        ),
        StatsCardGrid(
          columns: layout.columns,
          children: [
            StatsPunchCard(snapshot: snapshot),
            StatsAnlasCard(snapshot: snapshot, today: data.today),
            StatsAspectCard(snapshot: snapshot, actions: actions),
            StatsParamsCard(snapshot: snapshot, actions: actions),
            StatsArtistsCard(
              snapshot: snapshot,
              actions: actions,
              layout: layout,
            ),
            StatsStorageCard(
              snapshot: snapshot,
              today: data.today,
              actions: actions,
            ),
          ],
        ),
      ],
    );
  }
}

/// 结果第一次出现时 300ms 淡入；减少动态效果时直接显示。
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: child,
    );
  }
}
