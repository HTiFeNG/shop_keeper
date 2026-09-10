/// 导出门面（conditional import 分发）：
/// - 非 Web（Android/iOS）：excel 包生成 xlsx 双 Sheet → 临时文件 → share_plus 分享
/// - Web：CSV 文本 → Blob → <a download> 触发浏览器下载
///
/// 页面一律调用本门面，禁止直接 import excel / dart:html。
library;

import '../models/monthly_stats.dart';

import 'export_stub.dart'
    if (dart.library.io) 'export_io.dart'
    if (dart.library.html) 'export_web.dart' as impl;

abstract final class ExportService {
  /// 导出营业额：当日明细 + 月度汇总。
  /// [date] 当日日期键（YYYY-MM-DD）；[dayRows] 当日明细行 [名称, 数量, 单价, 总价]；[stats] 当月统计。
  static Future<void> exportSales({
    required String date,
    required List<List<String>> dayRows,
    required MonthlyStats stats,
  }) =>
      impl.exportSales(date: date, dayRows: dayRows, stats: stats);

  /// 导出商品 CSV。
  static Future<void> exportProducts(String csv) => impl.exportProducts(csv);

  /// 导出备份 JSON 文件。
  static Future<void> exportBackup(String jsonText) =>
      impl.exportBackup(jsonText);
}
