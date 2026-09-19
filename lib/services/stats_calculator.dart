import '../models/monthly_stats.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/date_utils.dart' as du;

/// 统计聚合（纯函数，不持有任何状态）。
///
/// 从 StoreService 里抽出来单独成文件，原因有两个：
/// 1. StoreService 曾是 900+ 行的 god object，统计是最容易独立的一块；
/// 2. 纯函数可以直接喂数据测试，不必先构造一个完整的 store。
///
/// 三种口径共用同一套聚合内核 [_aggregate]：
/// - [monthly]：某个月
/// - [range]：任意起止日期（含首尾）
/// - [yearly]：某一年（12 个月完整列出）
abstract final class StatsCalculator {
  /// 某月统计（环比对象 = 上一个月）
  static MonthlyStats monthly({
    required Map<String, DailyRecord> sales,
    required List<Product> products,
    required String yearMonth,
  }) {
    final agg = _aggregate(sales, products, '$yearMonth-01', '$yearMonth-31');
    return _toStats(
      agg,
      yearMonth: yearMonth,
      label: du.monthLabel(yearMonth),
      prevLabel: '上月',
      prevRevenue: revenueBetween(sales, '${du.prevMonth(yearMonth)}-01',
          '${du.prevMonth(yearMonth)}-31'),
    );
  }

  /// 任意区间统计（含起止两天）。环比对象 = 紧邻其前的**等长区间**。
  static MonthlyStats range({
    required Map<String, DailyRecord> sales,
    required List<Product> products,
    required String startKey,
    required String endKey,
    required String label,
  }) {
    final agg = _aggregate(sales, products, startKey, endKey);

    // 上一等长区间：以「起始日的前一天」为终点，往前推同样多的天数
    final start = du.parseDateKey(startKey);
    final end = du.parseDateKey(endKey);
    final span = end.difference(start).inDays; // >= 0
    final prevEnd = start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: span));
    final prevRevenue = revenueBetween(
        sales, du.dateKey(prevStart), du.dateKey(prevEnd));

    return _toStats(
      agg,
      yearMonth: '$startKey~$endKey',
      label: label,
      prevLabel: '上一区间',
      prevRevenue: prevRevenue,
    );
  }

  /// 年度统计：12 个月完整列出（没有账的月补 0），并合并全年商品排行与毛利。
  static YearlyStats yearly({
    required Map<String, DailyRecord> sales,
    required List<Product> products,
    required String year,
  }) {
    final months = <MonthPoint>[];
    final rankMap = <String, ProductRank>{};
    double total = 0;
    int items = 0;
    int recordCount = 0;
    int activeMonths = 0;
    double profit = 0;
    int missing = 0;

    for (var m = 1; m <= 12; m++) {
      final ym = '$year-${m.toString().padLeft(2, '0')}';
      final agg = _aggregate(sales, products, '$ym-01', '$ym-31');
      months.add(MonthPoint(
        yearMonth: ym,
        revenue: agg.revenue,
        quantity: agg.quantity,
        productCount: agg.daily.fold(0, (s, d) => s + d.productCount),
      ));
      total += agg.revenue;
      items += agg.quantity;
      recordCount += agg.daily.length;
      profit += agg.profit;
      missing += agg.missingCost;
      if (agg.revenue > 0) activeMonths++;

      for (final r in agg.rankMap.values) {
        final key = r.productId ?? 'name:${r.name}';
        final prev = rankMap[key];
        rankMap[key] = ProductRank(
          productId: r.productId,
          name: prev?.name ?? r.name,
          quantity: (prev?.quantity ?? 0) + r.quantity,
          revenue: (prev?.revenue ?? 0) + r.revenue,
        );
      }
    }

    double bestRevenue = 0;
    String? bestMonth;
    for (final m in months) {
      // 严格大于：并列时保留最早的月份
      if (m.revenue > bestRevenue) {
        bestRevenue = m.revenue;
        bestMonth = m.yearMonth;
      }
    }

    final ranking = rankMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return YearlyStats(
      year: year,
      months: months,
      totalRevenue: total,
      bestMonthRevenue: bestRevenue,
      bestMonth: bestMonth,
      totalItems: items,
      recordCount: recordCount,
      activeMonths: activeMonths,
      estimatedProfit: profit,
      profitMissingCostLines: missing,
      productRanking: ranking,
    );
  }

  /// [startKey, endKey] 闭区间内的总营收（环比 / 汇总用）
  static double revenueBetween(
      Map<String, DailyRecord> sales, String startKey, String endKey) {
    double sum = 0;
    for (final e in sales.entries) {
      if (e.key.compareTo(startKey) >= 0 && e.key.compareTo(endKey) <= 0) {
        sum += e.value.total;
      }
    }
    return sum;
  }

  // ==================== 内核 ====================

  static _Agg _aggregate(Map<String, DailyRecord> sales, List<Product> products,
      String startKey, String endKey) {
    final agg = _Agg();
    // 一次性建索引：旧实现每行都线性扫一遍 products，
    // 「几百个商品 × 一个月几千行」会在 UI 线程上明显卡顿。
    final byId = {for (final p in products) p.id: p};

    final records = sales.entries
        .where((e) =>
            e.key.compareTo(startKey) >= 0 &&
            e.key.compareTo(endKey) <= 0 &&
            e.value.items.isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (final entry in records) {
      final record = entry.value;
      double revenue = 0;
      int quantity = 0;

      for (final item in record.items) {
        revenue += item.totalPrice;
        quantity += item.quantity;

        // 商品维度聚合：key = productId 或 'name:名称'（悬空 / 手输行按名称聚合）
        final key = item.productId ?? 'name:${item.name}';
        final prev = agg.rankMap[key];
        agg.rankMap[key] = ProductRank(
          productId: item.productId,
          name: prev?.name ?? item.name,
          quantity: (prev?.quantity ?? 0) + item.quantity,
          revenue: (prev?.revenue ?? 0) + item.totalPrice,
        );

        // 估算毛利：营收取 totalPrice（与上面完全同口径），成本取**售出时快照**。
        // 快照缺失（升级前的老数据、或当时没填进价）才退回商品库当前进价。
        // 刻意不再用 margin > 0 过滤：亏本清仓必须记成负数，否则毛利被高估。
        final cost = item.costPrice ??
            (item.productId == null
                ? null
                : byId[item.productId!]?.purchasePrice);
        if (cost != null && cost > 0) {
          agg.profit += item.totalPrice - cost * item.quantity;
        } else {
          agg.missingCost++;
        }
      }

      agg.revenue += revenue;
      agg.quantity += quantity;
      agg.daily.add(MonthlyDayData(
        date: entry.key,
        revenue: revenue,
        productCount: record.items.length,
        totalQuantity: quantity,
      ));
    }
    return agg;
  }

  static MonthlyStats _toStats(
    _Agg agg, {
    required String yearMonth,
    required String label,
    required String prevLabel,
    required double prevRevenue,
  }) {
    final daily = agg.daily;
    final recordCount = daily.length;
    final average = recordCount > 0 ? agg.revenue / recordCount : 0.0;

    // 最高日：初始化为第一天，营收并列时保留最早日期
    double maxRevenue = daily.isNotEmpty ? daily.first.revenue : 0;
    String? maxRevenueDate = daily.isNotEmpty ? daily.first.date : null;
    for (var i = 1; i < daily.length; i++) {
      if (daily[i].revenue > maxRevenue) {
        maxRevenue = daily[i].revenue;
        maxRevenueDate = daily[i].date;
      }
    }

    final ranking = agg.rankMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return MonthlyStats(
      yearMonth: yearMonth,
      dailyData: daily,
      totalRevenue: agg.revenue,
      averageRevenue: average,
      maxRevenue: maxRevenue,
      maxRevenueDate: maxRevenueDate,
      totalItems: agg.quantity,
      recordCount: recordCount,
      prevMonthRevenue: prevRevenue,
      estimatedProfit: agg.profit,
      profitMissingCostLines: agg.missingCost,
      productRanking: ranking,
      label: label,
      prevLabel: prevLabel,
    );
  }
}

class _Agg {
  final List<MonthlyDayData> daily = [];
  final Map<String, ProductRank> rankMap = {};
  double revenue = 0;
  int quantity = 0;
  double profit = 0;
  int missingCost = 0;
}
