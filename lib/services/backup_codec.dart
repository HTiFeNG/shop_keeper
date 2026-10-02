/// 备份文件编解码（纯函数，不依赖 StoreService）。
///
/// 版本历史：
/// - v1：旧 product_store 时代的格式，**不再支持**
/// - v2：商品 + 分类 + 销售记录（3.0.x 之前）
/// - v3：在 v2 基础上增加**赊账台账**（credits）
///
/// 编码一律输出最新版本；解码同时接受 v2 / v3，保证老备份文件永远能恢复。
library;

import 'dart:convert';

import '../models/credit.dart';
import '../models/product.dart';
import '../models/sale.dart';
import 'store_constants.dart';

/// 当前导出的备份版本
const int kBackupVersion = 3;

/// 解码结果：解析成功但内容可能为空（是否采用由调用方决定）
class BackupPayload {
  BackupPayload({
    required this.products,
    required this.categories,
    required this.sales,
    required this.credits,
    required this.hasCredits,
    required this.version,
    required this.skipped,
    this.exportedAt,
  });

  final List<Product> products;
  final List<String> categories;
  final Map<String, DailyRecord> sales;
  final List<Credit> credits;

  /// 备份里**是否带了可用的 credits 字段**（是个数组才算 true）。
  ///
  /// v2 备份没有这个字段；v3 备份也可能因被工具裁剪、手工编辑、传输截断而
  /// 缺失、或类型不对。这两种情况下 [credits] 都是空列表，但语义完全不同 ——
  /// 「备份里没有欠账数据」不能当成「备份说欠账是空的」，否则恢复时会静默
  /// 清空本机的欠账本。由调用方据此决定要不要向用户二次确认。
  final bool hasCredits;

  final int version;
  final int skipped; // 解析失败被跳过的坏行数
  final String? exportedAt;
}

/// 恢复前预览（只统计数量，不构造模型、不改动任何状态）
class BackupPreview {
  BackupPreview({
    required this.productCount,
    required this.dayCount,
    required this.itemCount,
    this.creditCount = 0,
    this.exportedAt,
  });

  final int productCount;
  final int dayCount;
  final int itemCount;
  final int creditCount; // 赊账笔数
  final String? exportedAt; // 备份文件的导出时间（ISO 字符串，可能为 null）
}

/// 恢复备份的结果
class RestoreResult {
  RestoreResult.ok({
    required this.productCount,
    required this.dayCount,
    required this.skipped,
    this.creditCount = 0,
  })  : ok = true,
        lossWarning = null,
        reason = '';

  RestoreResult.fail(this.reason)
      : ok = false,
        lossWarning = null,
        productCount = 0,
        dayCount = 0,
        skipped = 0,
        creditCount = 0;

  /// 恢复会把本机现有数据清空，必须先向用户确认。
  ///
  /// [warning] 是一句面向用户的人话说明（差多少条）。这不算「失败」，
  /// 而是要调用方先确认；确认后带 `allowDataLoss: true` 再来一次。
  RestoreResult.needsConfirm(String warning)
      : ok = false,
        reason = warning,
        lossWarning = warning,
        productCount = 0,
        dayCount = 0,
        skipped = 0,
        creditCount = 0;

  /// 备份里没有可用的欠账数据（v2 无该字段，或 v3 的字段缺失/类型不对），
  /// 继续恢复会清空本机现有的欠账记录。
  factory RestoreResult.needsCreditConfirm(int existingCreditCount) =>
      RestoreResult.needsConfirm('这份备份不含欠账数据，继续恢复会清空现有的 '
          '$existingCreditCount 笔欠账记录。');

  /// 备份里没有任何营业额记录，而本机有 —— 多半是文件被裁剪或选错了，
  /// 继续恢复会清空本机全部营业额。
  factory RestoreResult.needsSalesConfirm(int existingDayCount) =>
      RestoreResult.needsConfirm('这份备份里没有任何营业额记录，继续恢复会清空'
          '本机现有的 $existingDayCount 天记账数据。');

  final bool ok;

  /// 失败原因 / 需要确认时的一句话说明（面向用户）
  final String reason;

  /// 需要用户确认的「会清空现有数据」说明；null 表示不需要确认
  final String? lossWarning;

  /// 是否需要「恢复会清空现有数据」的二次确认 —— UI 据此弹确认框。
  /// 覆盖两类场景：备份缺欠账字段、备份缺营业额记录。
  bool get needsConfirm => lossWarning != null;

  final int productCount; // 恢复后的商品数
  final int dayCount; // 恢复后的记账天数
  final int skipped; // 跳过的坏行数
  final int creditCount; // 恢复后的赊账笔数
}

abstract final class BackupCodec {
  /// 编码为单 JSON 字符串。
  ///
  /// 只保留**有实际意义**的数据：固定分类「全部」不落盘（它是伪分类）。
  static String encode({
    required List<Product> products,
    required List<String> categories,
    required Map<String, DailyRecord> sales,
    required List<Credit> credits,
    DateTime? now,
  }) {
    final map = {
      'version': kBackupVersion,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'products': products.map((p) => p.toJson()).toList(),
      'categories': categories.where((c) => c != kCategoryAll).toList(),
      'sales': sales.map((k, v) => MapEntry(k, v.toJson())),
      'credits': credits.map((c) => c.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// 解析 JSON，顺带剥掉 UTF-8 BOM。
  ///
  /// 备份文件如果被 Windows 记事本之类的工具另存过，开头会多一个 `\uFEFF`，
  /// `jsonDecode` 会直接报错。坚果云下载与 CSV 导入都做了这个处理，这里不能漏：
  /// 「从备份文件恢复」是灾后唯一的兜底通道，不能因为一个 BOM 就失效。
  static Object? _tryDecode(String raw) {
    var text = raw;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    try {
      return jsonDecode(text.trim());
    } catch (_) {
      return null;
    }
  }

  /// 单条商品/欠账的容错解析：字段类型不对时返回 null，不抛异常
  static Product? _tryProduct(Map<String, dynamic> json) {
    try {
      return Product.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Credit? _tryCredit(Map<String, dynamic> json) {
    try {
      return Credit.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 日期键必须是严格的 `YYYY-MM-DD`，**且那一天真的存在**。
  ///
  /// 只校验格式是不够的：`2026-02-31`、`2026-13-45` 都能通过正则，而
  /// `DateTime(2026, 2, 31)` 会被自动规范化成 3 月 3 日 —— 那天的数据会
  /// 悄悄「跑到」另一个日期上。这里回比一次规范化结果，把这类键挡掉。
  static bool _isDateKey(String s) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
    final p = s.split('-');
    final y = int.parse(p[0]);
    final m = int.parse(p[1]);
    final d = int.parse(p[2]);
    if (m < 1 || m > 12 || d < 1) return false;
    final dt = DateTime(y, m, d);
    return dt.year == y && dt.month == m && dt.day == d;
  }

  /// 解析备份文本。返回 null 表示「这不是一个受支持的备份文件」。
  ///
  /// **容错原则：逐条解析、能救多少救多少。** 任意一条记录损坏都不应该让
  /// 整份备份作废 —— 只把它计入 [BackupPayload.skipped]。
  static BackupPayload? decode(String jsonText) {
    final map = _tryDecode(jsonText);
    if (map is! Map<String, dynamic>) return null;
    final version = map['version'];
    if (version is! int || (version != 2 && version != 3)) return null;

    final productsRaw = map['products'];
    final categoriesRaw = map['categories'];
    final salesRaw = map['sales'];
    if (productsRaw is! List || categoriesRaw is! List || salesRaw is! Map) {
      return null;
    }

    var skipped = 0;

    // ---- 商品：逐条容错 + 编号去重 ----
    // 重复编号必须挡掉：明细是按 productId 关联商品的，同一编号出现两次
    // 会让老账指向「哪一个」变得不确定，排行与毛利都会算错。
    final products = <Product>[];
    final seenIds = <String>{};
    for (final e in productsRaw) {
      if (e is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final p = _tryProduct(e);
      // 编号和名称都为空的行没有意义，也编辑不了
      if (p == null || (p.id.isEmpty && p.name.isEmpty)) {
        skipped++;
        continue;
      }
      if (p.id.isNotEmpty && !seenIds.add(p.id)) {
        skipped++;
        continue;
      }
      products.add(p);
    }

    final categories = categoriesRaw
        .whereType<String>()
        .where((c) => c != kCategoryAll)
        .toList();

    // ---- 销售记录：逐条容错；丢掉负数量/负金额的脏行 ----
    // 本应用不支持退货冲账，负值只会让「当日合计」被莫名拉低。
    final sales = <String, DailyRecord>{};
    for (final entry in salesRaw.entries) {
      final k = entry.key;
      final v = entry.value;
      if (k is! String || !_isDateKey(k) || v is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final rec = DailyRecord.fromJson(v, onBadItem: () => skipped++);
      // 以键为准，避免「某天列表里看得到、月度统计里却算不到」
      rec.date = k;
      final before = rec.items.length;
      rec.items.removeWhere((it) => it.totalPrice < 0 || it.quantity < 0);
      skipped += before - rec.items.length;
      if (rec.items.isEmpty) {
        skipped++;
        continue;
      }
      sales[k] = rec;
    }

    // ---- 欠账 ----
    // v2 备份没有这个字段；v3 也可能因被裁剪 / 手工编辑 / 传输截断而缺失或
    // 类型不对。只有确实是个数组，才认为「这份备份带了欠账数据」（空数组也算）。
    final creditsRaw = map['credits'];
    final hasCredits = creditsRaw is List;
    final credits = <Credit>[];
    final seenCreditIds = <String>{};
    if (creditsRaw is List) {
      for (final e in creditsRaw) {
        if (e is! Map<String, dynamic>) {
          skipped++;
          continue;
        }
        final c = _tryCredit(e);
        if (c == null || (c.customer.isEmpty && c.amount == 0)) {
          skipped++;
          continue;
        }
        // 金额必须为正、日期必须合法：负欠款/乱日期只会污染催款列表
        if (c.amount < 0 || !_isDateKey(c.date)) {
          skipped++;
          continue;
        }
        if (c.id.isNotEmpty && !seenCreditIds.add(c.id)) {
          skipped++;
          continue;
        }
        credits.add(c);
      }
    }

    return BackupPayload(
      products: products,
      categories: categories,
      sales: sales,
      credits: credits,
      hasCredits: hasCredits,
      version: version,
      skipped: skipped,
      exportedAt: map['exportedAt'] as String?,
    );
  }

  /// 恢复前预览：只数数量，不构造模型、不改动任何状态。
  /// 返回 null 表示这不是一个可识别的备份文件。
  static BackupPreview? preview(String jsonText) {
    final map = _tryDecode(jsonText);
    if (map is! Map<String, dynamic>) return null;
    final version = map['version'];
    if (version is! int || (version != 2 && version != 3)) return null;
    final p = map['products'];
    final s = map['sales'];
    if (p is! List || s is! Map) return null;

    var items = 0;
    for (final v in s.values) {
      if (v is Map && v['items'] is List) items += (v['items'] as List).length;
    }
    final c = map['credits'];
    return BackupPreview(
      productCount: p.length,
      dayCount: s.length,
      itemCount: items,
      creditCount: c is List ? c.length : 0,
      exportedAt: map['exportedAt'] as String?,
    );
  }
}
