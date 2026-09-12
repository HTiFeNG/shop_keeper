import 'package:flutter/material.dart';

import '../models/monthly_stats.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart' as du;
import '../utils/format.dart';
import '../widgets/monthly_chart.dart';
import '../widgets/stat_card.dart';

/// 月度统计页：四宫格汇总卡 + 环比 + 柱状图 + 商品排行 + 估算毛利。
///
/// 内嵌于营业额首页的内部 Tab；点击柱子回调跳当日明细（由父层切换日期）。
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
  late String _month = widget.initialMonth;

  @override
  Widget build(BuildContext context) {
    final stats = store.monthlyStats(_month);
    final hasData = stats.recordCount > 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 月份切换
        Container(
          decoration: AppTheme.cardDecoration,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: '上一月',
                icon: const Icon(Icons.chevron_left, size: 26),
                onPressed: () => setState(() => _month = du.prevMonth(_month)),
              ),
              Expanded(
                child: Center(
                  child: Text(du.monthLabel(_month),
                      style: AppTheme.sectionTitle),
                ),
              ),
              IconButton(
                tooltip: '下一月',
                icon: const Icon(Icons.chevron_right, size: 26),
                onPressed: () => setState(() => _month = du.nextMonth(_month)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!hasData) _emptyState() else ..._statsContent(stats),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: AppTheme.cardDecoration,
      child: Column(
        children: [
          Icon(Icons.bar_chart,
              size: 56, color: AppTheme.textSecondary.withValues(alpha: 0.45)),
          const SizedBox(height: 12),
          Text('${du.monthLabel(_month)} 暂无营业记录', style: AppTheme.body),
          const SizedBox(height: 6),
          const Text('回到「明细记录」记几笔，再回来看看统计',
              style: AppTheme.caption),
        ],
      ),
    );
  }

  List<Widget> _statsContent(MonthlyStats stats) {
    return [
      // 四宫格：宽屏（平板 / 桌面）排 4 列，否则 2 列。
      // 原来固定 2 列，1280px 窗口下每张卡会被拉到近 600px 宽，很难扫读。
      LayoutBuilder(
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
                label: '当月总营业额',
                value: formatCurrency(stats.totalRevenue),
                color: AppTheme.primary,
              ),
              StatCard(
                label: '日均营业额',
                value: formatCurrency(stats.averageRevenue),
                color: AppTheme.success,
              ),
              StatCard(
                label: '最高营业额日',
                value: formatCurrency(stats.maxRevenue),
                subLabel: stats.maxRevenueDate != null
                    ? du.dayLabel(stats.maxRevenueDate!)
                    : null,
                color: AppTheme.chartPeak,
              ),
              StatCard(
                label: '销售总件数',
                value: '${stats.totalItems} 件',
                subLabel: '有记录 ${stats.recordCount} 天',
                // 原来是全 App 唯一一处紫色，已并入暖色系
                color: AppTheme.primaryText,
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      // 环比条
      _momBar(stats),
      // 估算毛利：亏本时也要显示（旧实现 > 0 才显示，等于把亏损藏起来）
      const SizedBox(height: 10),
      _profitBar(stats),
      const SizedBox(height: 12),
      // 柱状图
      Container(
        decoration: AppTheme.cardDecoration,
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('每日营业额', style: AppTheme.sectionTitle),
            const SizedBox(height: 4),
            const Text('橙色为当月最高日，点柱子可跳到当天明细',
                style: AppTheme.caption),
            const SizedBox(height: 12),
            MonthlyChart(
              dailyData: stats.dailyData,
              onBarTap: widget.onJumpToDate,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // 商品排行
      if (stats.productRanking.isNotEmpty) _rankingCard(stats),
    ];
  }

  /// 本月 vs 上月环比条
  Widget _momBar(MonthlyStats stats) {
    final growth = stats.momGrowth;
    final String text;
    final Color color;
    final IconData icon;
    if (growth == null) {
      text = stats.prevMonthRevenue > 0
          ? '上月 ${formatCurrency(stats.prevMonthRevenue)}'
          : '上月没有记录，这是第一个有账的月份';
      color = AppTheme.textSecondary;
      icon = Icons.info_outline;
    } else if (growth >= 0) {
      text =
          '比上月 ${formatCurrency(stats.prevMonthRevenue)} 多卖 ${(growth * 100).toStringAsFixed(0)}%';
      color = AppTheme.success;
      icon = Icons.trending_up;
    } else {
      text =
          '比上月 ${formatCurrency(stats.prevMonthRevenue)} 少卖 ${(-growth * 100).toStringAsFixed(0)}%';
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
  Widget _profitBar(MonthlyStats stats) {
    final profit = stats.estimatedProfit;
    final negative = profit < 0;
    final color = negative ? AppTheme.negativeStockRed : AppTheme.success;
    final missing = stats.profitMissingCostLines;
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
          // 口径说明单独一行：原来和 14px 正文挤在同一 Row，大字号下会被压没
          const Text('按「零售价 − 售出时的参考进价」估算，之后改进价不会改写历史',
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

  /// 商品维度排行（前 10）：卖得最多 / 贡献最大
  Widget _rankingCard(MonthlyStats stats) {
    final top = stats.productRanking.take(10).toList();
    final maxRevenue = top.isEmpty ? 1.0 : top.first.revenue;
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('商品排行（按营业额）', style: AppTheme.sectionTitle),
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
