/// 金额 / 价格格式化工具（全局统一来源）。
library;

/// 完整金额格式：`¥1,234.50`（千分位 + 两位小数）。
String formatCurrency(num value) {
  // 非有限数（Infinity / NaN）没有合理显示形式，旧实现会算出「¥In,fin.ty」
  if (!value.isFinite) return '¥—';
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

/// 解析价格文本：非法 / 负数 / 非有限数 / 过大值一律归 0。
///
/// 必须挡住 `Infinity` / `NaN`：`double.tryParse` 会接受 "Infinity"、"1e400"
/// 这类输入（它们不小于 0，能绕过旧判断），而 `jsonEncode` 遇到非有限数会
/// 直接抛异常 —— 一旦这种值进了商品库，之后**所有商品改动都无法落盘**，
/// 且因为持久化是发射后不管的，用户看不到任何报错。
double parsePrice(String s) {
  final v = double.tryParse(s.trim());
  if (v == null || !v.isFinite || v < 0 || v > 999999999) return 0;
  return v;
}
