/// 月度统计数据模型。
library;

/// 某一天（有记录）的聚合数据。
class MonthlyDayData {
  MonthlyDayData({
    required this.date,
    required this.revenue,
    required this.productCount,
    required this.totalQuantity,
  });

  final String date; // 'YYYY-MM-DD'
  final double revenue; // 当日营业额
  final int productCount; // 当日明细行数（商品种类数）
  final int totalQuantity; // 当日总件数
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

/// 月度统计汇总。
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
  });

  final String yearMonth; // 'YYYY-MM'
  final List<MonthlyDayData> dailyData; // 按日期升序（仅有记录的天）
  final double totalRevenue; // 月总营收
  final double averageRevenue; // 日均（按有记录天数）
  final double maxRevenue; // 最高日营收
  final String? maxRevenueDate; // 最高日（同日取最早一天）
  final int totalItems; // 总件数
  final int recordCount; // 有记录天数
  final double prevMonthRevenue; // 上月营收（环比）
  final double estimatedProfit; // 估算毛利（售出时进价快照口径，亏本计负）
  /// 未计入毛利的明细行数（手输行 / 当时没填进价）。> 0 时 UI 要提示，
  /// 否则用户会以为「毛利」是全量的，实际漏了一部分。
  final int profitMissingCostLines;
  final List<ProductRank> productRanking; // 商品维度排行（按营收降序）

  /// 环比增长率（上月为 0 → null 表示不可比）
  double? get momGrowth => prevMonthRevenue > 0
      ? (totalRevenue - prevMonthRevenue) / prevMonthRevenue
      : null;
}
