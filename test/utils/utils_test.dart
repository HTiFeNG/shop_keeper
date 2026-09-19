// 工具函数测试：金额解析/格式化、日期工具、CSV 编解码。
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/utils/csv_codec.dart';
import 'package:shop_keeper/utils/date_utils.dart' as du;
import 'package:shop_keeper/utils/format.dart';

void main() {
  group('parsePrice', () {
    test('挡住非有限数（否则会让持久化永久静默失效）', () {
      // double.tryParse 接受 "Infinity"/"1e400"/"NaN"，它们不小于 0，
      // 能绕过旧判断；而 jsonEncode 遇到非有限数会抛异常 —— 一旦进了商品库，
      // 之后每次保存商品都会失败，且因为不 await，用户看不到任何报错。
      expect(parsePrice('Infinity'), 0);
      expect(parsePrice('1e400'), 0);
      expect(parsePrice('NaN'), 0);
      expect(parsePrice('1.2.3'), 0);
      expect(parsePrice('12元'), 0);
      expect(parsePrice('-5'), 0);
      expect(parsePrice(''), 0);
      expect(parsePrice('3.5'), 3.5);
      expect(parsePrice(' 2 '), 2);
    });
  });

  group('金额格式化', () {
    test('formatCurrency 对非有限数不产生乱码', () {
      expect(formatCurrency(1234.5), '¥1,234.50');
      expect(formatCurrency(0), '¥0.00');
      expect(formatCurrency(-12.5), '-¥12.50');
      expect(formatCurrency(double.infinity), '¥—');
      expect(formatCurrency(double.nan), '¥—');
    });

    test('fmtPrice 去尾零', () {
      expect(fmtPrice(2), '2');
      expect(fmtPrice(2.5), '2.50');
      expect(fmtPrice(0), '0');
    });
  });

  group('日期工具', () {
    test('日期 / 月份键格式', () {
      expect(du.dateKey(DateTime(2026, 7, 26)), '2026-07-26');
      expect(du.monthKey(DateTime(2026, 7, 26)), '2026-07');
    });

    test('跨年切月', () {
      expect(du.prevMonth('2026-01'), '2025-12');
      expect(du.nextMonth('2026-12'), '2027-01');
      expect(du.prevMonth('2026-07'), '2026-06');
      expect(du.nextMonth('2026-07'), '2026-08');
    });

    test('展示标签', () {
      expect(du.monthLabel('2026-07'), '2026年7月');
      expect(du.dayLabel('2026-07-26'), '7月26日');
      expect(du.weekdayLabel(DateTime(2026, 7, 26)), '周日');
    });

    test('parseDateKey 容错：非法输入回退今天而不是崩', () {
      expect(du.parseDateKey('2026-07-26'), DateTime(2026, 7, 26));
      final fallback = du.parseDateKey('坏日期');
      expect(fallback.year, DateTime.now().year);
    });
  });

  group('CsvCodec', () {
    test('往返一致（含逗号 / 引号 / 换行）', () {
      const codec = CsvCodec();
      final rows = [
        ['a,b', 'c"d', 'e\nf'],
        ['plain', '', 'x'],
      ];
      expect(codec.decode(codec.encode(rows)), rows);
    });

    test('空输入 / 纯空白行安全', () {
      const codec = CsvCodec();
      expect(codec.decode(''), isEmpty);
      expect(codec.decode('\n\n'), isEmpty);
      expect(codec.decode('\r\n'), isEmpty);
    });
  });
}
