/// 导出实现占位（VM 测试等无 io/html 库环境兜底，理论上不会被用到）。
library;

import '../models/monthly_stats.dart';

Future<void> exportSales({
  required String date,
  required List<List<String>> dayRows,
  required MonthlyStats stats,
}) async {
  throw UnsupportedError('当前平台不支持导出');
}

Future<void> exportProducts(String csv) async {
  throw UnsupportedError('当前平台不支持导出');
}

Future<void> exportBackup(String jsonText) async {
  throw UnsupportedError('当前平台不支持导出');
}
