import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/monthly_stats.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 月度营收柱状图（fl_chart 封装）：
/// - Y 轴万位缩写；
/// - 峰值柱深橙高亮；
/// - 点击柱子回调（跳当日明细）。
class MonthlyChart extends StatelessWidget {
  const MonthlyChart({
    super.key,
    required this.dailyData,
    required this.onBarTap,
  });

  final List<MonthlyDayData> dailyData;

  /// 点击柱子 → 当日日期键
  final ValueChanged<String> onBarTap;

  @override
  Widget build(BuildContext context) {
    if (dailyData.isEmpty) return const SizedBox.shrink();

    double maxY = 0;
    var peakIndex = -1;
    for (var i = 0; i < dailyData.length; i++) {
      if (dailyData[i].revenue > maxY) {
        maxY = dailyData[i].revenue;
        peakIndex = i;
      }
    }
    final chartMaxY = maxY <= 0 ? 100.0 : maxY * 1.2;

    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          maxY: chartMaxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: chartMaxY / 4,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppTheme.divider, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: chartMaxY / 4,
                getTitlesWidget: (v, _) => Text(
                  v >= 10000
                      ? '${(v / 10000).toStringAsFixed(1)}万'
                      : v.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= dailyData.length) {
                    return const SizedBox.shrink();
                  }
                  // 数据多时稀疏显示日期标签
                  final step = dailyData.length > 12 ? 3 : 1;
                  if (i % step != 0) return const SizedBox.shrink();
                  final day = dailyData[i].date.substring(8);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      day,
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textSecondary),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.white,
              tooltipBorder: const BorderSide(color: AppTheme.divider),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final d = dailyData[group.x.toInt()];
                return BarTooltipItem(
                  '${d.date}\n营业额 ${formatCurrency(d.revenue)}\n${d.productCount} 种 · ${d.totalQuantity} 件',
                  const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                final i = response!.spot!.touchedBarGroupIndex;
                if (i >= 0 && i < dailyData.length) {
                  onBarTap(dailyData[i].date);
                }
              }
            },
          ),
          barGroups: [
            for (var i = 0; i < dailyData.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: dailyData[i].revenue,
                    width: dailyData.length > 20 ? 8 : 14,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                    color: i == peakIndex
                        ? AppTheme.chartPeak
                        : AppTheme.chartOrange,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
