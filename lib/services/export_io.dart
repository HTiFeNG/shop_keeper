/// Android/iOS（非 Web）导出实现：
/// - 营业额：excel 包生成 xlsx 双 Sheet「当日明细」+「月度汇总」→ 临时文件 → share_plus
/// - 商品 CSV / 备份 JSON：临时文件 → share_plus
library;

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/monthly_stats.dart';
import '../utils/format.dart';

String _stamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
}

/// 导出营业额 xlsx（双 Sheet）并调起系统分享。
Future<void> exportSales({
  required String date,
  required List<List<String>> dayRows,
  required MonthlyStats stats,
}) async {
  final excel = Excel.createExcel();

  // ---- Sheet1：当日明细 ----
  final sheetDay = excel['当日明细'];
  excel.setDefaultSheet('当日明细');
  sheetDay.appendRow([TextCellValue('日期'), TextCellValue(date)]);
  sheetDay.appendRow([
    TextCellValue('序号'),
    TextCellValue('商品'),
    TextCellValue('数量'),
    TextCellValue('单价'),
    TextCellValue('总价'),
  ]);
  double dayTotal = 0;
  for (var i = 0; i < dayRows.length; i++) {
    final r = dayRows[i];
    sheetDay.appendRow([
      IntCellValue(i + 1),
      TextCellValue(r[0]),
      IntCellValue(int.tryParse(r[1]) ?? 0),
      DoubleCellValue(double.tryParse(r[2]) ?? 0),
      DoubleCellValue(double.tryParse(r[3]) ?? 0),
    ]);
    dayTotal += double.tryParse(r[3]) ?? 0;
  }
  sheetDay.appendRow([
    TextCellValue(''),
    TextCellValue('合计'),
    TextCellValue(''),
    TextCellValue(''),
    DoubleCellValue(dayTotal),
  ]);

  // ---- Sheet2：月度汇总 ----
  final sheetMonth = excel['月度汇总'];
  sheetMonth.appendRow([TextCellValue('月份'), TextCellValue(stats.yearMonth)]);
  sheetMonth.appendRow([
    TextCellValue('日期'),
    TextCellValue('商品种类数'),
    TextCellValue('总件数'),
    TextCellValue('营业额'),
  ]);
  for (final d in stats.dailyData) {
    sheetMonth.appendRow([
      TextCellValue(d.date),
      IntCellValue(d.productCount),
      IntCellValue(d.totalQuantity),
      DoubleCellValue(d.revenue),
    ]);
  }
  sheetMonth.appendRow([TextCellValue('')]);
  sheetMonth.appendRow([
    TextCellValue('月总营收'),
    TextCellValue(formatCurrency(stats.totalRevenue)),
  ]);
  sheetMonth.appendRow([
    TextCellValue('日均营收'),
    TextCellValue(formatCurrency(stats.averageRevenue)),
  ]);
  sheetMonth.appendRow([
    TextCellValue('最高日营收'),
    TextCellValue(
        '${formatCurrency(stats.maxRevenue)}（${stats.maxRevenueDate ?? '—'}）'),
  ]);
  sheetMonth.appendRow([
    TextCellValue('总件数'),
    IntCellValue(stats.totalItems),
  ]);

  // 删除默认 Sheet
  if (excel.sheets.containsKey('Sheet1')) {
    excel.delete('Sheet1');
  }

  final bytes = excel.encode();
  if (bytes == null) return;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/营业额_${date}_${_stamp()}.xlsx');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    title: '营业额导出',
  ));
}

/// 导出商品 CSV（加 BOM 保证 Excel 打开中文不乱码）。
Future<void> exportProducts(String csv) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/商品数据_${_stamp()}.csv');
  await file.writeAsString('﻿$csv', flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    title: '商品数据导出',
  ));
}

/// 导出备份 JSON。
Future<void> exportBackup(String jsonText) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/店铺管家备份_${_stamp()}.json');
  await file.writeAsString(jsonText, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    title: '数据备份',
  ));
}
