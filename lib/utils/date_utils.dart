/// 日期工具（全局统一来源）。
///
/// 约定：全部本地时区字符串 —— 日期 `YYYY-MM-DD`、月份 `YYYY-MM`。
/// 禁止页面手写日期字符串拼接。
library;

/// 日期 → `YYYY-MM-DD`
String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 日期 → `YYYY-MM`
String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// 今天
String todayKey() => dateKey(DateTime.now());

/// 解析 `YYYY-MM-DD` → DateTime（本地时区，非法输入回退今天）
DateTime parseDateKey(String key) {
  final p = key.split('-');
  if (p.length != 3) return DateTime.now();
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return DateTime.now();
  return DateTime(y, m, d);
}

/// 前一月（处理跨年）：`YYYY-MM`
String prevMonth(String yearMonth) {
  var y = int.parse(yearMonth.split('-')[0]);
  var m = int.parse(yearMonth.split('-')[1]) - 1;
  if (m < 1) {
    m = 12;
    y -= 1;
  }
  return '$y-${m.toString().padLeft(2, '0')}';
}

/// 后一月（处理跨年）：`YYYY-MM`
String nextMonth(String yearMonth) {
  var y = int.parse(yearMonth.split('-')[0]);
  var m = int.parse(yearMonth.split('-')[1]) + 1;
  if (m > 12) {
    m = 1;
    y += 1;
  }
  return '$y-${m.toString().padLeft(2, '0')}';
}

/// 月份展示标签：`2026年7月`
String monthLabel(String yearMonth) {
  final p = yearMonth.split('-');
  return '${int.parse(p[0])}年${int.parse(p[1])}月';
}

/// 日期展示标签：`7月26日`
String dayLabel(String dateKeyStr) {
  final d = parseDateKey(dateKeyStr);
  return '${d.month}月${d.day}日';
}

/// 星期标签：`周三`
String weekdayLabel(DateTime d) =>
    ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][d.weekday - 1];
