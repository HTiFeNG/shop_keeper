/// 金额 / 价格格式化工具（全局统一来源）。
library;

/// 完整金额格式：`¥1,234.50`（千分位 + 两位小数）。
String formatCurrency(num value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final intPart = fixed.substring(0, fixed.length - 3);
  final decPart = fixed.substring(fixed.length - 2);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${negative ? '-' : ''}¥$buf.$decPart';
}

/// 紧凑价格：整数省小数（2 → "2"，2.5 → "2.50"），用于表格内展示。
String fmtPrice(num value) =>
    value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);

/// 解析价格文本：非法 / 负数归 0。
double parsePrice(String s) {
  final v = double.tryParse(s.trim());
  if (v == null || v < 0) return 0;
  return v;
}
