/// 极简 CSV 编解码（支持含逗号 / 引号 / 换行的字段）。
///
/// 从 store_service.dart 拆出：商品 CSV 导入导出与备份恢复共用。
library;

class CsvCodec {
  const CsvCodec();

  String encode(List<List<String>> rows) => rows.map(encodeRow).join('\r\n');

  String encodeRow(List<String> fields) => fields.map((f) {
        if (f.contains(',') ||
            f.contains('"') ||
            f.contains('\n') ||
            f.contains('\r')) {
          return '"${f.replaceAll('"', '""')}"';
        }
        return f;
      }).join(',');

  /// 解析整个 CSV 文本（自动去除 UTF-8 BOM，忽略空行）
  List<List<String>> decode(String text) {
    var t = text;
    if (t.startsWith('﻿')) t = t.substring(1);
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < t.length && t[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          row.add(field.toString());
          field = StringBuffer();
        } else if (c == '\n' || c == '\r') {
          if (c == '\r' && i + 1 < t.length && t[i + 1] == '\n') i++;
          row.add(field.toString());
          field = StringBuffer();
          if (row.any((f) => f.isNotEmpty)) rows.add(row);
          row = <String>[];
        } else {
          field.write(c);
        }
      }
    }
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
    return rows;
  }
}
