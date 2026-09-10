/// Web 端导出实现：CSV / 文本 → Blob → <a download> 触发浏览器下载。
///
/// 不使用 file_picker 保存（可靠性一般），零新依赖（package:web 为 Flutter SDK 自带）。
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/monthly_stats.dart';
import '../utils/csv_codec.dart';
import '../utils/format.dart';

String _stamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
}

/// 触发浏览器下载一个文本文件。
void downloadTextFile(String filename, String text) {
  final bytes = utf8.encode(text);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// 导出营业额 CSV：当日明细 + 月度汇总 两段式。
Future<void> exportSales({
  required String date,
  required List<List<String>> dayRows,
  required MonthlyStats stats,
}) async {
  const codec = CsvCodec();
  final rows = <List<String>>[];

  // 段一：当日明细
  rows.add(['当日明细', date]);
  rows.add(['序号', '商品', '数量', '单价', '总价']);
  double dayTotal = 0;
  for (var i = 0; i < dayRows.length; i++) {
    rows.add(['${i + 1}', ...dayRows[i]]);
    dayTotal += double.tryParse(dayRows[i][3]) ?? 0;
  }
  rows.add(['', '合计', '', '', fmtPrice(dayTotal)]);
  rows.add([]);

  // 段二：月度汇总
  rows.add(['月度汇总', stats.yearMonth]);
  rows.add(['日期', '商品种类数', '总件数', '营业额']);
  for (final d in stats.dailyData) {
    rows.add([
      d.date,
      '${d.productCount}',
      '${d.totalQuantity}',
      fmtPrice(d.revenue),
    ]);
  }
  rows.add([]);
  rows.add(['月总营收', formatCurrency(stats.totalRevenue)]);
  rows.add(['日均营收', formatCurrency(stats.averageRevenue)]);
  rows.add([
    '最高日营收',
    '${formatCurrency(stats.maxRevenue)}（${stats.maxRevenueDate ?? '—'}）'
  ]);
  rows.add(['总件数', '${stats.totalItems}']);

  // 加 BOM 保证 Excel 打开中文不乱码
  downloadTextFile('营业额_${date}_${_stamp()}.csv', '﻿${codec.encode(rows)}');
}

/// 导出商品 CSV。
Future<void> exportProducts(String csv) async {
  downloadTextFile('商品数据_${_stamp()}.csv', '﻿$csv');
}

/// 导出备份 JSON。
Future<void> exportBackup(String jsonText) async {
  downloadTextFile('店铺管家备份_${_stamp()}.json', jsonText);
}
