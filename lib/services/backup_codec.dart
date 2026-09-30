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
    required this.version,
    required this.skipped,
    this.exportedAt,
  });

  final List<Product> products;
  final List<String> categories;
  final Map<String, DailyRecord> sales;
  final List<Credit> credits;
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
        needsCreditConfirm = false,
        reason = '';

  RestoreResult.fail(this.reason)
      : ok = false,
        needsCreditConfirm = false,
        productCount = 0,
        dayCount = 0,
        skipped = 0,
        creditCount = 0;

  /// v2 老备份没有欠账（credits）字段，直接恢复会把现有欠账整体清空。
  /// 这不算「失败」，而是要调用方先向用户确认；确认后带
  /// `allowCreditLoss: true` 再来一次。
  RestoreResult.needsCreditConfirm(int existingCreditCount)
      : ok = false,
        needsCreditConfirm = true,
        reason = '这份备份是旧版本（v2），不含欠账数据。'
            '继续恢复会清空现有的 $existingCreditCount 笔欠账记录。',
        productCount = 0,
        dayCount = 0,
        skipped = 0,
        creditCount = 0;

  final bool ok;

  /// true 表示「需要用户确认会丢失欠账」，见 [RestoreResult.needsCreditConfirm]
  final bool needsCreditConfirm;
  final String reason; // 失败原因（面向用户的一句话）
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

  /// 日期键必须是严格的 `YYYY-MM-DD`
  static bool _isDateKey(String s) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

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

    // ---- 欠账：v2 没有 credits 字段 ----
    final credits = <Credit>[];
    final seenCreditIds = <String>{};
    final creditsRaw = map['credits'];
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
