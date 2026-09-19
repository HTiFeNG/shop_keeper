/// 统计数据模型。
///
/// 三种统计口径共用一套模型：
/// - 按**月**（`2026-07`）
/// - 按**自定义区间**（`2026-07-01` ~ `2026-07-20`）
/// - 按**年**（`2026`，用 [YearlyStats]）
library;

/// 某一天（有记录）的聚合数据。
class MonthlyDayData {
  MonthlyDayData({
    required this.date,
    required this.revenue,
    required this.productCount,
    required this.totalQuantity,
    this.label,
    this.tooltipLabel,
  });

  final String date; // 'YYYY-MM-DD'；按年统计时是 'YYYY-MM'
  final double revenue; // 当日营业额
  final int productCount; // 当日明细行数（商品种类数）
  final int totalQuantity; // 当日总件数

  /// 图表横轴短标签（null → 由图表按日期自行截取）。
  ///
  /// 按年统计时这里是 `1月`…`12月`：那时 [date] 是 `YYYY-MM`，
  /// 图表若继续取 `date.substring(8)` 会直接越界。
  final String? label;

  /// 点柱子时气泡里的标题（null → 用 [date]）。
  /// 按年统计时是 `2026年1月`，比 `2026-01` 好读。
  final String? tooltipLabel;
}

/// 商品维度排行项。
class ProductRank {
  ProductRank({
    required this.name,
    required this.quantity,
    required this.revenue,
    this.productId,
  });

  final String? productId; // 可能悬空（商品已删）
  final String name;
  final int quantity; // 售出件数
  final double revenue; // 贡献营收
}

/// 区间统计汇总（月 / 自定义区间通用）。
class MonthlyStats {
  MonthlyStats({
    required this.yearMonth,
    required this.dailyData,
    required this.totalRevenue,
    required this.averageRevenue,
    required this.maxRevenue,
    required this.maxRevenueDate,
    required this.totalItems,
    required this.recordCount,
    required this.prevMonthRevenue,
    required this.estimatedProfit,
    required this.profitMissingCostLines,
    required this.productRanking,
    this.label = '',
    this.prevLabel = '',
  });

  final String yearMonth; // 机器可读的区间标识（月统计为 'YYYY-MM'）
  final List<MonthlyDayData> dailyData; // 按日期升序（仅有记录的天）
  final double totalRevenue; // 区间总营收
  final double averageRevenue; // 日均（按有记录天数）
  final double maxRevenue; // 最高日营收
  final String? maxRevenueDate; // 最高日（同日取最早一天）
  final int totalItems; // 总件数
  final int recordCount; // 有记录天数
  final double prevMonthRevenue; // 上一等长区间营收（环比）
  final double estimatedProfit; // 估算毛利（售出时进价快照口径，亏本计负）
  /// 未计入毛利的明细行数（手输行 / 当时没填进价）。> 0 时 UI 要提示，
  /// 否则用户会以为「毛利」是全量的，实际漏了一部分。
  final int profitMissingCostLines;
  final List<ProductRank> productRanking; // 商品维度排行（按营收降序）

  /// 展示用区间标签（如 `2026年7月` / `7月1日 – 7月20日`）。
  /// 为空时调用方退回 [yearMonth]。
  final String label;

  /// 对比区间的展示标签（如 `上月` / `上一区间`）。
  final String prevLabel;

  /// 环比增长率（上期为 0 → null 表示不可比）
  double? get momGrowth => prevMonthRevenue > 0
      ? (totalRevenue - prevMonthRevenue) / prevMonthRevenue
      : null;
}

/// 年度统计里的一个月。
class MonthPoint {
  MonthPoint({
    required this.yearMonth,
    required this.revenue,
    required this.quantity,
    required this.productCount,
  });

  final String yearMonth; // 'YYYY-MM'
  final double revenue;
  final int quantity; // 件数
  final int productCount; // 明细行数
}

/// 年度统计汇总（12 个月完整列出，没有账的月补 0）。
class YearlyStats {
  YearlyStats({
    required this.year,
    required this.months,
    required this.totalRevenue,
    required this.bestMonthRevenue,
    required this.bestMonth,
    required this.totalItems,
    required this.recordCount,
    required this.activeMonths,
    required this.estimatedProfit,
    required this.profitMissingCostLines,
    required this.productRanking,
  });

  final String year; // 'YYYY'
  final List<MonthPoint> months; // 固定 12 项，1 月起
  final double totalRevenue;
  final double bestMonthRevenue;
  final String? bestMonth; // 'YYYY-MM'，全 0 时为 null
  final int totalItems;
  final int recordCount; // 有记录的天数
  final int activeMonths; // 有账的月份数
  final double estimatedProfit;
  final int profitMissingCostLines;
  final List<ProductRank> productRanking;

  /// 月均（按有账的月份算，避免把没开门的日子拉低平均值）
  double get averageRevenue => activeMonths > 0 ? totalRevenue / activeMonths : 0;

  /// 换算成图表能用的日维度数据结构（12 根柱子，标签 `1月`…`12月`）
  List<MonthlyDayData> get chartData => [
        for (final m in months)
          MonthlyDayData(
            date: m.yearMonth,
            revenue: m.revenue,
            productCount: m.productCount,
            totalQuantity: m.quantity,
            label: '${int.parse(m.yearMonth.split('-')[1])}月',
            tooltipLabel:
                '${m.yearMonth.split('-')[0]}年${int.parse(m.yearMonth.split('-')[1])}月',
          ),
      ];
}
