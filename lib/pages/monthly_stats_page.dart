import 'package:flutter/material.dart';

import '../models/monthly_stats.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart' as du;
import '../utils/format.dart';
import '../widgets/monthly_chart.dart';
import '../widgets/stat_card.dart';

/// 统计口径：按月 / 自定义区间 / 按年
enum StatsMode { month, range, year }

/// 统计页：汇总卡 + 环比 + 柱状图 + 商品排行 + 估算毛利。
///
/// 三种口径共用同一套展示：
/// - **按月**：看单月表现，点柱子跳当日明细
/// - **自定义区间**：看「这批货卖完这段时间」的表现，环比对象是上一等长区间
/// - **按年**：12 根柱子看全年节奏，点柱子直接下钻到那个月
///
/// 内嵌于营业额首页的内部 Tab。
class MonthlyStatsPage extends StatefulWidget {
  const MonthlyStatsPage({
    super.key,
    required this.initialMonth,
    required this.onJumpToDate,
  });

  final String initialMonth; // 'YYYY-MM'

  /// 点击柱子跳当日明细（父层切回明细 Tab 并切日期）
  final ValueChanged<String> onJumpToDate;

  @override
  State<MonthlyStatsPage> createState() => _MonthlyStatsPageState();
}

class _MonthlyStatsPageState extends State<MonthlyStatsPage> {
  final store = StoreService.instance;

  StatsMode _mode = StatsMode.month;
  late String _month = widget.initialMonth;
  late String _year = widget.initialMonth.substring(0, 4);
  late String _start;
  late String _end;

  @override
  void initState() {
    super.initState();
    _start = '$_month-01';
    _end = _lastDayOf(_month);
  }

  /// 'YYYY-MM' → 'YYYY-MM-31'（自动适配大小月）
  static String _lastDayOf(String yearMonth) {
    final p = yearMonth.split('-');
    final y = int.parse(p[0]);
    final m = int.parse(p[1]);
    final last = DateTime(y, m + 1, 0); // 下月第 0 天 = 本月最后一天
    return du.dateKey(last);
  }

  // ==================== 期间切换 ====================

  void _shiftMonth(int delta) {
    final next = delta < 0 ? du.prevMonth(_month) : du.nextMonth(_month);
    setState(() {
      _month = next;
      _year = next.substring(0, 4);
      _start = '$next-01';
      _end = _lastDayOf(next);
    });
  }

  void _shiftYear(int delta) {
    setState(() {
      final y = int.parse(_year) + delta;
      _year = y.toString();
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: du.parseDateKey(_start),
        end: du.parseDateKey(_end),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = du.dateKey(picked.start);
      _end = du.dateKey(picked.end);
    });
  }

  void _onBarTap(String key) {
    if (_mode == StatsMode.year) {
      // 年视图的柱子代表月份 → 直接下钻到那个月
      setState(() {
        _mode = StatsMode.month;
        _month = key;
        _start = '$key-01';
        _end = _lastDayOf(key);
      });
    } else {
      widget.onJumpToDate(key);
    }
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _modeSwitcher(),
        const SizedBox(height: 10),
        _periodBar(),
        const SizedBox(height: 12),
        ..._body(),
      ],
    );
  }

  Widget _modeSwitcher() => SegmentedButton<StatsMode>(
        segments: const [
          ButtonSegment(value: StatsMode.month, label: Text('按月')),
          ButtonSegment(value: StatsMode.range, label: Text('自定义区间')),
          ButtonSegment(value: StatsMode.year, label: Text('按年')),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      );

  Widget _periodBar() {
    final String title;
    Widget? onTap;
    switch (_mode) {
      case StatsMode.month:
        title = du.monthLabel(_month);
        break;
      case StatsMode.range:
        title = '${du.dayLabel(_start)} – ${du.dayLabel(_end)}';
        onTap = const Icon(Icons.edit_calendar_outlined,
            size: 20, color: AppTheme.primaryText);
        break;
      case StatsMode.year:
        title = '$_year年';
        break;
    }

    final left = _mode == StatsMode.range
        ? null
        : () => _mode == StatsMode.month ? _shiftMonth(-1) : _shiftYear(-1);
    final right = _mode == StatsMode.range
        ? null
        : () => _mode == StatsMode.month ? _shiftMonth(1) : _shiftYear(1);

    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          if (left != null)
            IconButton(
              tooltip: _mode == StatsMode.month ? '上一月' : '上一年',
              icon: const Icon(Icons.chevron_left, size: 26),
              onPressed: left,
            ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              onTap: _mode == StatsMode.range ? _pickRange : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.sectionTitle),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 6),
                      onTap,
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (right != null)
            IconButton(
              tooltip: _mode == StatsMode.month ? '下一月' : '下一年',
              icon: const Icon(Icons.chevron_right, size: 26),
              onPressed: right,
            ),
        ],
      ),
    );
  }

  List<Widget> _body() {
    switch (_mode) {
      case StatsMode.month:
        return _monthBody();
      case StatsMode.range:
        return _rangeBody();
      case StatsMode.year:
        return _yearBody();
    }
  }

  // ==================== 按月 ====================

  List<Widget> _monthBody() {
    final stats = store.monthlyStats(_month);
    if (stats.recordCount == 0) {
      return [_empty('${du.monthLabel(_month)} 暂无营业记录')];
    }
    return [
      _cards(
        totalLabel: '当月总营业额',
        total: stats.totalRevenue,
        avgLabel: '日均营业额',
        avg: stats.averageRevenue,
        maxTitle: '最高营业额日',
        maxValue: stats.maxRevenue,
        maxLabel: stats.maxRevenueDate == null
            ? null
            : du.dayLabel(stats.maxRevenueDate!),
        items: stats.totalItems,
        recordLabel: '有记录 ${stats.recordCount} 天',
      ),
      const SizedBox(height: 12),
      _momBar(stats.totalRevenue, stats.prevMonthRevenue, '上月'),
      const SizedBox(height: 10),
      _profitBar(stats.estimatedProfit, stats.profitMissingCostLines),
      const SizedBox(height: 12),
      _chartCard(
        title: '每日营业额',
        caption: '橙色为当月最高日，点柱子可跳到当天明细',
        data: stats.dailyData,
      ),
      if (stats.productRanking.isNotEmpty) ...[
        const SizedBox(height: 12),
        _rankingCard(stats.productRanking),
      ],
    ];
  }

  // ==================== 自定义区间 ====================

  List<Widget> _rangeBody() {
    final stats = store.statsForRange(
      _start,
      _end,
      label: '${du.dayLabel(_start)} – ${du.dayLabel(_end)}',
    );
    if (stats.recordCount == 0) {
      return [_empty('这段时间暂无营业记录')];
    }
    return [
      _cards(
        totalLabel: '区间总营业额',
        total: stats.totalRevenue,
        avgLabel: '日均营业额',
        avg: stats.averageRevenue,
        maxTitle: '区间最高日',
        maxValue: stats.maxRevenue,
        maxLabel: stats.maxRevenueDate == null
            ? null
            : du.dayLabel(stats.maxRevenueDate!),
        items: stats.totalItems,
        recordLabel: '有记录 ${stats.recordCount} 天',
      ),
      const SizedBox(height: 12),
      _momBar(stats.totalRevenue, stats.prevMonthRevenue, '上一区间'),
      const SizedBox(height: 10),
      _profitBar(stats.estimatedProfit, stats.profitMissingCostLines),
      const SizedBox(height: 12),
      _chartCard(
        title: '每日营业额',
        caption: '橙色为区间内最高日，点柱子可跳到当天明细',
        data: stats.dailyData,
      ),
      if (stats.productRanking.isNotEmpty) ...[
        const SizedBox(height: 12),
        _rankingCard(stats.productRanking),
      ],
    ];
  }

  // ==================== 按年 ====================

  List<Widget> _yearBody() {
    final stats = store.yearlyStats(_year);
    if (stats.totalRevenue <= 0) {
      return [_empty('$_year年 暂无营业记录')];
    }
    return [
      _cards(
        totalLabel: '全年总营业额',
        total: stats.totalRevenue,
        avgLabel: '月均营业额',
        avg: stats.averageRevenue,
        maxTitle: '最高营业额月',
        maxValue: stats.bestMonthRevenue,
        maxLabel: stats.bestMonth == null
            ? null
            : du.monthLabel(stats.bestMonth!),
        items: stats.totalItems,
        recordLabel: '有账 ${stats.activeMonths} 个月 · ${stats.recordCount} 天',
      ),
      const SizedBox(height: 12),
      _profitBar(stats.estimatedProfit, stats.profitMissingCostLines),
      const SizedBox(height: 12),
      _chartCard(
        title: '每月营业额',
        caption: '橙色为全年最高月，点柱子可下钻到那个月',
        data: stats.chartData,
      ),
      if (stats.productRanking.isNotEmpty) ...[
        const SizedBox(height: 12),
        _rankingCard(stats.productRanking, title: '全年商品排行（按营业额）'),
      ],
    ];
  }

  // ==================== 公共组件 ====================

  Widget _empty(String text) => Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: AppTheme.cardDecoration,
        child: Column(
          children: [
            Icon(Icons.bar_chart,
                size: 56,
                color: AppTheme.textSecondary.withValues(alpha: 0.45)),
            const SizedBox(height: 12),
            Text(text, style: AppTheme.body),
            const SizedBox(height: 6),
            const Text('回到「明细记录」记几笔，再回来看看统计',
                style: AppTheme.caption),
          ],
        ),
      );

  /// 四宫格汇总卡（宽屏 4 列 / 窄屏 2 列）
  Widget _cards({
    required String totalLabel,
    required double total,
    required String avgLabel,
    required double avg,
    required String maxTitle,
    required double maxValue,
    required String? maxLabel,
    required int items,
    required String recordLabel,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 900 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cols == 4 ? 2.8 : 2.1,
          children: [
            StatCard(
              label: totalLabel,
              value: formatCurrency(total),
              color: AppTheme.primary,
            ),
            StatCard(
              label: avgLabel,
              value: formatCurrency(avg),
              color: AppTheme.success,
            ),
            StatCard(
              label: maxTitle,
              value: formatCurrency(maxValue),
              subLabel: maxLabel,
              color: AppTheme.chartPeak,
            ),
            StatCard(
              label: '销售总件数',
              value: '$items 件',
              subLabel: recordLabel,
              color: AppTheme.primaryText,
            ),
          ],
        );
      },
    );
  }

  /// 环比条：本期 vs 上一等长期间
  Widget _momBar(double current, double prev, String prevLabel) {
    final growth = prev > 0 ? (current - prev) / prev : null;
    final String text;
    final Color color;
    final IconData icon;
    if (growth == null) {
      text = prev > 0
          ? '$prevLabel ${formatCurrency(prev)}'
          : '$prevLabel没有记录，这是第一个有账的期间';
      color = AppTheme.textSecondary;
      icon = Icons.info_outline;
    } else if (growth >= 0) {
      text =
          '比$prevLabel ${formatCurrency(prev)} 多卖 ${(growth * 100).toStringAsFixed(0)}%';
      color = AppTheme.success;
      icon = Icons.trending_up;
    } else {
      text =
          '比$prevLabel ${formatCurrency(prev)} 少卖 ${(-growth * 100).toStringAsFixed(0)}%';
      color = AppTheme.priceRed;
      icon = Icons.trending_down;
    }
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// 估算毛利条
  ///
  /// 毛利按「售出时的进价快照」计算，所以之后修改商品进价**不会**改写已经
  /// 过去月份的毛利；亏本销售也如实显示为负数（旧实现用 margin > 0 过滤，
  /// 会把亏损当 0，等于高估利润）。
  Widget _profitBar(double profit, int missing) {
    final negative = profit < 0;
    final color = negative ? AppTheme.negativeStockRed : AppTheme.success;
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(negative ? Icons.trending_down : Icons.savings_outlined,
                  color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${negative ? '估算亏损约' : '估算毛利约'} '
                  '${formatCurrency(profit.abs())}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('按「售出价 − 售出时的参考进价」估算，之后改进价不会改写历史',
              style: AppTheme.caption),
          if (missing > 0) ...[
            const SizedBox(height: 2),
            Text('有 $missing 条明细没填进价，未计入毛利',
                style: const TextStyle(
                    fontSize: AppTheme.fontCaption,
                    color: AppTheme.primaryText)),
          ],
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required String caption,
    required List<MonthlyDayData> data,
  }) {
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.sectionTitle),
          const SizedBox(height: 4),
          Text(caption, style: AppTheme.caption),
          const SizedBox(height: 12),
          MonthlyChart(dailyData: data, onBarTap: _onBarTap),
        ],
      ),
    );
  }

  /// 商品维度排行（前 10）：卖得最多 / 贡献最大
  Widget _rankingCard(List<ProductRank> ranking,
      {String title = '商品排行（按营业额）'}) {
    final top = ranking.take(10).toList();
    final maxRevenue = top.isEmpty ? 1.0 : top.first.revenue;
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.sectionTitle),
          const SizedBox(height: 4),
          const Text('看看哪些货最走量，进货心里有数', style: AppTheme.caption),
          const SizedBox(height: 10),
          for (var i = 0; i < top.length; i++) ...[
            _rankRow(top[i], i + 1, maxRevenue),
            if (i < top.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _rankRow(ProductRank rank, int order, double maxRevenue) {
    final fraction = maxRevenue > 0 ? rank.revenue / maxRevenue : 0.0;
    // 名次配色：原来第 1 名用 #FFB300，在白底上只有 1.79:1，数字几乎看不见
    final medalColor = switch (order) {
      1 => const Color(0xFF8D5300),
      2 => const Color(0xFF4E5A61),
      3 => const Color(0xFF6B4A33),
      _ => AppTheme.textSecondary,
    };
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: medalColor.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$order',
            style: TextStyle(
                fontSize: AppTheme.fontCaption,
                fontWeight: FontWeight.w700,
                color: medalColor),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rank.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                  Text(
                    formatCurrency(rank.revenue),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.priceRed),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 6,
                        backgroundColor: AppTheme.divider,
                        valueColor: const AlwaysStoppedAnimation(
                            AppTheme.chartOrange),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${rank.quantity} 件', style: AppTheme.caption),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
