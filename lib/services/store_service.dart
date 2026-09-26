import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sample_products.dart';
import '../models/credit.dart';
import '../models/monthly_stats.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/csv_codec.dart';
import '../utils/date_utils.dart' as du;
import 'backup_codec.dart';
import 'nutstore_sync.dart';
import 'stats_calculator.dart';
import 'store_constants.dart';

// 分类常量与备份结果类型的历史导入路径保持不变（页面 / 测试继续从本文件取）
export 'backup_codec.dart' show BackupPreview, RestoreResult;
export 'store_constants.dart' show kCategoryAll, kCategoryNone;

/// 数据层门面：商品 / 分类 / 销售记录 / 赊账 / 云同步 的本地持久化与编排。
///
/// 存储方案：shared_preferences + JSON 字符串（Web 端自动落 localStorage）。
/// 所有键名统一 `sk_` 前缀，与旧 product_store（ps_*）/ 旧 sales-tracker 零冲突。
/// 所有修改操作立即落盘并 notifyListeners()，页面通过 ListenableBuilder 自动刷新。
///
/// 4.0.0 起本类只保留「状态容器 + 编排 + 持久化」三件事，具体算法拆到：
/// - [StatsCalculator]  统计聚合（月 / 区间 / 年）
/// - [BackupCodec]      备份文件编解码
/// - [NutstoreSync]     坚果云 WebDAV 同步
/// - `utils/search.dart` 商品检索（拼音）
class StoreService extends ChangeNotifier {
  StoreService._();

  static final StoreService instance = StoreService._();

  static const String _kProducts = 'sk_products';
  static const String _kCategories = 'sk_categories';
  static const String _kSales = 'sk_sales';
  static const String _kCredits = 'sk_credits';
  static const String _kSeeded = 'sk_seeded';
  static const String _kNextSeq = 'sk_next_seq';
  static const String _kLastBackup = 'sk_last_backup';
  static const String _kRestoreSnapshot = 'sk_restore_snapshot';
  static const String _kSyncConfig = 'sk_sync_config';
  static const String _kSyncLast = 'sk_sync_last';

  List<Product> products = [];
  List<String> categories = []; // 不含固定项「全部」「未分类」

  /// 销售记录：键为日期 `YYYY-MM-DD`
  Map<String, DailyRecord> sales = {};

  /// 赊账台账（不参与营业额统计，见 models/credit.dart 的说明）
  List<Credit> credits = [];

  bool ready = false; // 首次加载完成前为 false

  /// 是否已完成首启询问（false → UI 弹窗询问是否载入示例数据）
  bool seeded = false;

  /// 下一个商品编号序号：单调递增并持久化，**已用过的编号绝不回收**。
  ///
  /// 旧实现按「现有商品最大编号 +1」生成。删掉编号最大的商品后该编号会被
  /// 再次分配给新商品，而历史销售里指向它的 productId 仍然有效 → 老账会
  /// 静默改指到另一个商品（月度排行被合并、毛利按新商品进价重算）。
  int _nextSeq = 1;

  /// 最近一次保存失败的原因（null = 一切正常）。UI 据此提示用户尽快备份。
  String? saveError;

  /// 上次成功备份（本地导出或上传云端）的时间（null = 从未备份）
  DateTime? lastBackupAt;

  /// 上次启动时因单条数据损坏而被丢弃的条目数（> 0 时 UI 应提醒用户）
  int droppedOnLoad = 0;

  /// 顶层数据整段无法解析时的标记（null = 正常）。非 null 时说明存储已损坏，
  /// UI 必须提醒用户「立即从备份恢复」，而不是把空数据当成「暂无商品」。
  String? loadError;

  /// 是否存在「恢复前快照」（可一键撤销上一次恢复）
  bool hasRestoreSnapshot = false;

  /// 商品页「记一笔」→ 首页预填一行 的跨 Tab 通知（解耦）
  final ValueNotifier<SalePrefill?> salePrefill = ValueNotifier<SalePrefill?>(null);

  // ==================== 云同步状态 ====================

  NutstoreConfig syncConfig = const NutstoreConfig();

  /// 上次成功同步（上传 / 下载）的时间
  DateTime? lastSyncAt;

  /// 上次同步失败的原因（null = 正常）
  String? lastSyncError;

  /// 启动时发现「云端比本机新」的待处理备份（不会自动覆盖本地）
  BackupPreview? pendingRemotePreview;
  String? _pendingRemoteText;

  bool get hasPendingRemote => _pendingRemoteText != null;

  /// 解析 JSON，失败返回 null（不抛异常、不吞掉调用方的其它错误）
  Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// 商品编号 `SP0007` → 7；不匹配返回 0
  static final RegExp _idPattern = RegExp(r'^SP(\d+)$');
  static int _seqOf(String? id) {
    if (id == null) return 0;
    final m = _idPattern.firstMatch(id);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }

  /// 应用启动时调用。
  ///
  /// 容错原则是**逐条解析、能救多少救多少**。旧实现用 `as List` 配合
  /// `.map().toList()`，任意一条记录损坏都会让整个列表抛异常并被 `catch`
  /// 清空，而 `ready` 仍为 true、界面显示「暂无商品」；随后用户随便改一下
  /// 就会把空列表写回磁盘，把好数据彻底销毁。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    products = [];
    sales = {};
    credits = [];
    droppedOnLoad = 0;
    loadError = null;

    // ---- 商品 ----
    final productsRaw = prefs.getString(_kProducts);
    if (productsRaw != null && productsRaw.isNotEmpty) {
      final decoded = _tryDecode(productsRaw);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map<String, dynamic>) {
            final p = Product.fromJson(e);
            // 编号和名称都为空的行没有意义，也编辑不了
            if (p.id.isNotEmpty || p.name.isNotEmpty) {
              products.add(p);
            } else {
              droppedOnLoad++;
            }
          } else {
            droppedOnLoad++;
          }
        }
      } else {
        loadError = '商品数据已损坏，无法读取';
      }
    }

    // ---- 分类 ----
    categories = prefs.getStringList(_kCategories) ?? [];
    categories.remove(kCategoryAll);

    // ---- 首启询问语义：不再自动载入示例数据 ----
    seeded = prefs.getBool(_kSeeded) ?? false;
    lastBackupAt = DateTime.tryParse(prefs.getString(_kLastBackup) ?? '');
    hasRestoreSnapshot =
        (prefs.getString(_kRestoreSnapshot) ?? '').isNotEmpty;

    // ---- 销售记录 ----
    final salesRaw = prefs.getString(_kSales);
    if (salesRaw != null && salesRaw.isNotEmpty) {
      final decoded = _tryDecode(salesRaw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k is String && v is Map<String, dynamic>) {
            final rec = DailyRecord.fromJson(v);
            // 键与记录内 date 不一致时一律以键为准，
            // 否则会出现「某天列表里看得到、月度统计里却算不到」。
            rec.date = k;
            sales[k] = rec;
          } else {
            droppedOnLoad++;
          }
        });
      } else {
        loadError = '营业额数据已损坏，无法读取';
      }
    }

    // ---- 赊账台账 ----
    final creditsRaw = prefs.getString(_kCredits);
    if (creditsRaw != null && creditsRaw.isNotEmpty) {
      final decoded = _tryDecode(creditsRaw);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map<String, dynamic>) {
            final c = Credit.fromJson(e);
            if (c.customer.isNotEmpty || c.amount != 0) {
              credits.add(c);
            } else {
              droppedOnLoad++;
            }
          } else {
            droppedOnLoad++;
          }
        }
      } else {
        loadError = '欠账数据已损坏，无法读取';
      }
    }

    // ---- 云同步配置 ----
    final syncRaw = prefs.getString(_kSyncConfig);
    if (syncRaw != null && syncRaw.isNotEmpty) {
      final decoded = _tryDecode(syncRaw);
      if (decoded is Map<String, dynamic>) {
        syncConfig = NutstoreConfig.fromJson(decoded);
      }
    }
    lastSyncAt = DateTime.tryParse(prefs.getString(_kSyncLast) ?? '');

    // ---- 编号序列 ----
    // 必须大于「现有商品 ∪ 历史销售引用过」的最大编号，
    // 否则升级后新建商品的编号会撞上老账里的悬空引用。
    _nextSeq = prefs.getInt(_kNextSeq) ?? 1;
    _syncSeq();

    ready = true;
    notifyListeners();
  }

  /// 首启弹窗选「载入示例数据」：24 商品 + 5 分类；选「从空开始」调用 markSeeded。
  ///
  /// 已有商品时拒绝执行并返回 false，避免把用户已经录入的商品整体覆盖掉。
  bool seedSampleData() {
    if (products.isNotEmpty) return false;
    products = SampleProducts.build();
    categories = List.of(SampleProducts.defaultCategories);
    seeded = true;
    for (final p in products) {
      final n = _seqOf(p.id);
      if (n >= _nextSeq) _nextSeq = n + 1;
    }
    _persistProducts();
    _persistCategories();
    _persistSeeded();
    _persistNextSeq();
    notifyListeners();
    return true;
  }

  /// 首启弹窗选「从空开始」：仅标记已询问。
  void markSeeded() {
    seeded = true;
    _persistSeeded();
    notifyListeners();
  }

  // ==================== 商品 ====================

  /// 根据条码查找商品（扫码后判断「已有 → 编辑 / 没有 → 新建」）
  Product? findByBarcode(String barcode) {
    for (final p in products) {
      if (p.barcode == barcode && barcode.isNotEmpty) return p;
    }
    return null;
  }

  /// 根据 id 查找商品（统计聚合、扫码定位用）
  Product? findById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 明细行要显示的品牌。
  ///
  /// 优先用成交时的快照；快照为空（4.0.0 之前记的老数据、或手输行）时，
  /// 按 [SaleItem.productId] 回查商品库当前品牌兜底 —— 这样刚升级上来的用户
  /// 打开营业额页就能看到品牌，而不是要等新记录才生效。
  /// 纯手输行（productId 为 null）没有任何品牌可查，返回空串。
  String brandOf(SaleItem item) {
    if (item.brand.isNotEmpty) return item.brand;
    final id = item.productId;
    if (id == null) return '';
    return findById(id)?.brand ?? '';
  }

  /// 改单个商品的分类（商品列表里直接点分类标签就能改）。
  void setCategory(String productId, String category) {
    final p = findById(productId);
    if (p == null) return;
    if (p.category == category) return;
    p.category = category;
    _persistProducts();
    notifyListeners();
  }

  /// 分配一个编号但不立即落盘（批量导入时用，避免每行写一次存储）
  String _allocId() => 'SP${(_nextSeq++).toString().padLeft(4, '0')}';

  /// 把编号序列推进到「不小于现有商品与历史销售里出现过的最大编号 + 1」。
  /// 导入 / 恢复后调用，保证新编号不会撞上已有编号。
  void _syncSeq() {
    var seq = _nextSeq;
    for (final p in products) {
      final n = _seqOf(p.id);
      if (n >= seq) seq = n + 1;
    }
    for (final r in sales.values) {
      for (final it in r.items) {
        final n = _seqOf(it.productId);
        if (n >= seq) seq = n + 1;
      }
    }
    _nextSeq = seq;
  }

  /// 生成下一个编号：SP0001、SP0002 ……（单调递增，已用过的编号不回收）
  String nextId() {
    final id = _allocId();
    _persistNextSeq();
    return id;
  }

  /// 该条码是否已被**其它**商品占用（空条码不参与判断）
  bool barcodeTaken(String barcode, {String? ignoreId}) {
    if (barcode.isEmpty) return false;
    return products.any((p) => p.barcode == barcode && p.id != ignoreId);
  }

  /// 新增商品。返回 false 表示条码已被其它商品占用（调用方需提示用户）。
  bool addProduct(Product p) {
    if (barcodeTaken(p.barcode)) return false;
    products.add(p);
    // 若带进来的编号比当前序列大（导入/恢复/测试），把序列顶上去，
    // 保证之后生成的编号不会和它撞车
    final n = _seqOf(p.id);
    if (n >= _nextSeq) _nextSeq = n + 1;
    _persistProducts();
    _persistNextSeq();
    notifyListeners();
    return true;
  }

  /// 更新商品。返回 false 表示条码已被其它商品占用。
  bool updateProduct(Product p) {
    if (barcodeTaken(p.barcode, ignoreId: p.id)) return false;
    final i = products.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      // 编辑页不带 isFavorite 时以内存现值为准，避免误清
      p.isFavorite = products[i].isFavorite;
      products[i] = p;
    }
    _persistProducts();
    notifyListeners();
    return true;
  }

  void deleteProduct(String id) {
    products.removeWhere((e) => e.id == id);
    _persistProducts();
    notifyListeners();
  }

  /// 批量修改商品类别
  void batchSetCategory(List<String> ids, String category) {
    final idSet = ids.toSet();
    for (final p in products) {
      if (idSet.contains(p.id)) p.category = category;
    }
    _persistProducts();
    notifyListeners();
  }

  /// 批量删除商品
  void batchDelete(List<String> ids) {
    final idSet = ids.toSet();
    products.removeWhere((e) => idSet.contains(e.id));
    _persistProducts();
    notifyListeners();
  }

  /// 切换星标收藏（常用商品）
  void toggleFavorite(String id) {
    final p = findById(id);
    if (p == null) return;
    p.isFavorite = !p.isFavorite;
    _persistProducts();
    notifyListeners();
  }

  /// 常用商品列表（星标，保持商品列表顺序）
  List<Product> favoriteProducts() =>
      products.where((p) => p.isFavorite).toList();

  /// 「最近常卖」：按最近 [days] 天售出件数排序的商品。
  ///
  /// 完全由销售历史推导，不依赖手工加星 —— 新用户装上就能用上一键记账，
  /// 而不必先知道「要进编辑页把商品点亮」。
  List<Product> recentProducts({int limit = 8, int days = 30}) {
    final sinceKey =
        du.dateKey(DateTime.now().subtract(Duration(days: days)));
    final qty = <String, int>{};
    sales.forEach((date, rec) {
      if (date.compareTo(sinceKey) < 0) return;
      for (final it in rec.items) {
        final id = it.productId;
        if (id == null) continue;
        qty[id] = (qty[id] ?? 0) + it.quantity;
      }
    });
    final list = products.where((p) => (qty[p.id] ?? 0) > 0).toList()
      ..sort((a, b) => (qty[b.id] ?? 0).compareTo(qty[a.id] ?? 0));
    return list.take(limit).toList();
  }

  // ==================== 分类 ====================

  /// 新增分类。返回 false 表示重名（调用方提示「该分类已存在」）。
  bool addCategory(String name) {
    final n = name.trim();
    if (n.isEmpty) return true;
    if (_isDuplicateCategory(n)) return false;
    categories.add(n);
    _persistCategories();
    notifyListeners();
    return true;
  }

  /// 重命名分类，并联动更新商品类别。
  bool renameCategory(String oldName, String newName) {
    final n = newName.trim();
    if (n.isEmpty || n == oldName) return true;
    if (_isDuplicateCategory(n, ignore: oldName)) return false;
    categories[categories.indexOf(oldName)] = n;
    for (final p in products) {
      if (p.category == oldName) {
        p.category = n;
      } else if (p.category.startsWith('$oldName/')) {
        p.category = '$n/${p.category.substring(oldName.length + 1)}';
      }
    }
    _persistCategories();
    _persistProducts();
    notifyListeners();
    return true;
  }

  /// 删除分类，并联动调整商品类别
  void deleteCategory(String name) {
    categories.remove(name);
    for (final p in products) {
      if (p.category == name) {
        p.category = kCategoryNone;
      } else if (p.category.startsWith('$name/')) {
        p.category = p.category.substring(name.length + 1);
      }
    }
    _persistCategories();
    _persistProducts();
    notifyListeners();
  }

  /// 上移 / 下移分类（自定义顺序），delta = -1 上移、1 下移。
  ///
  /// UI 已改用 [reorderCategories]（拖拽一次到位），这里保留是为了不改动
  /// 既有公开 API 与测试。
  void moveCategory(String name, int delta) {
    final i = categories.indexOf(name);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= categories.length) return;
    final t = categories[i];
    categories[i] = categories[j];
    categories[j] = t;
    _persistCategories();
    notifyListeners();
  }

  /// 整体重排分类（分类管理面板拖拽后一次性提交），只落盘一次。
  ///
  /// 传入的顺序即目标顺序；做了两重保护，避免拖拽回调给出残缺列表时
  /// 把分类**弄丢**：
  /// 1. 只保留确实存在的分类名，并去掉重复项；
  /// 2. 原列表里没被提到的分类，按原顺序补到末尾。
  void reorderCategories(List<String> ordered) {
    final seen = <String>{};
    final next = <String>[];
    for (final name in ordered) {
      if (categories.contains(name) && seen.add(name)) next.add(name);
    }
    for (final name in categories) {
      if (!seen.contains(name)) next.add(name);
    }
    if (_sameOrder(next, categories)) return;
    categories = next;
    _persistCategories();
    notifyListeners();
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _isDuplicateCategory(String name, {String? ignore}) {
    if (name == kCategoryAll || name == kCategoryNone) return true;
    return categories.any((c) => c == name && c != ignore);
  }

  // ==================== 销售记录 ====================

  /// 某天的明细行列表（无记录返回空列表，不创建空记录）
  List<SaleItem> itemsOf(String date) => sales[date]?.items ?? [];

  /// 某天的日合计
  double dayTotal(String date) => sales[date]?.total ?? 0;

  /// [start, end] 闭区间内**有记录**的天，按日期倒序（最近的在前）。
  ///
  /// 供「查账」页使用：按关键字在历史明细里翻找，必须跨天，而不是只看某一天。
  List<DailyRecord> recordsInRange(String startKey, String endKey) {
    final list = sales.entries
        .where((e) =>
            e.key.compareTo(startKey) >= 0 &&
            e.key.compareTo(endKey) <= 0 &&
            e.value.items.isNotEmpty)
        .map((e) => e.value)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// 新增 / 更新一行销售明细。
  ///
  /// 库存联动已随「库存功能」一并移除：本应用只记营业额，不跟踪库存。
  void upsertSaleItem(String date, SaleItem newItem) {
    final record = sales.putIfAbsent(date, () => DailyRecord(date: date));
    final idx = record.items.indexWhere((e) => e.id == newItem.id);
    if (idx >= 0) {
      record.items[idx] = newItem;
    } else {
      record.items.add(newItem);
    }
    _persistSales();
    notifyListeners();
  }

  /// 记录一件商品的销售：当天已有**同商品同计价方式**的行 → 数量+1 合并，
  /// 否则新建一行。
  ///
  /// 为什么不跨计价方式合并：一行零售价、一行批发价是两笔账，
  /// 合并会把两套单价揉成一个数字，事后谁也说不清卖的是什么价。
  ///
  /// 手动改过总价的行（抹零 / 改价）合并时，把那份总价理解为**该行的实际
  /// 单价**再按新数量等比放大：1 件手动 ¥5 → 再卖 1 件 = 2 件 ¥10。
  /// 旧实现直接沿用原总价，会出现「件数 +1、营业额却一分没涨」的漏记。
  ///
  /// 返回被新增（或合并进去）的那一行 id，供 UI 滚动定位到它。
  String recordSaleFromProduct(
    String date,
    Product product, {
    SalePriceMode mode = SalePriceMode.retail,
  }) {
    final record = sales[date];
    if (record != null) {
      final idx = record.items.indexWhere(
          (e) => e.productId == product.id && e.priceMode == mode);
      if (idx >= 0) {
        final it = record.items[idx];
        final q = it.quantity + 1;
        final double total = it.isManualMode
            ? (it.quantity > 0
                ? it.totalPrice / it.quantity * q
                : q * it.unitPrice)
            : q * it.unitPrice;
        final next = it.copy()
          ..quantity = q
          ..totalPrice = total;
        // 手动价的行合并后，把单价同步成「实际单价」，让单价 × 数量 = 总价重新自洽。
        // 否则单价还停在商品原价上，用户之后一按数量加减就会用旧单价把总价改掉
        // （例如抹零成 1 件 ¥5、单价字段仍是 ¥2，再点 + 就变成 3 件 ¥6）。
        if (it.isManualMode && q > 0) {
          next.unitPrice = total / q;
        }
        upsertSaleItem(date, next);
        return it.id;
      }
    }
    final item = SaleItem.fromProduct(product, mode: mode);
    upsertSaleItem(date, item);
    return item.id;
  }

  /// 删除一行销售明细。找不到返回 null。
  SaleItem? deleteSaleItem(String date, String itemId) {
    final record = sales[date];
    if (record == null) return null;
    final idx = record.items.indexWhere((e) => e.id == itemId);
    if (idx < 0) return null;
    final item = record.items.removeAt(idx);
    if (record.items.isEmpty) {
      sales.remove(date); // 清空当天则不保留空记录
    }
    _persistSales();
    notifyListeners();
    return item;
  }

  // ==================== 统计 ====================

  /// 按**月**聚合统计（含环比、商品排行、估算毛利）
  MonthlyStats monthlyStats(String yearMonth) => StatsCalculator.monthly(
        sales: sales,
        products: products,
        yearMonth: yearMonth,
      );

  /// 按**任意区间**聚合统计（含起止两天，环比对象为上一等长区间）
  MonthlyStats statsForRange(String startKey, String endKey, {String? label}) =>
      StatsCalculator.range(
        sales: sales,
        products: products,
        startKey: startKey,
        endKey: endKey,
        label: label ?? '$startKey – $endKey',
      );

  /// 按**年**聚合统计（12 个月完整列出）
  YearlyStats yearlyStats(String year) => StatsCalculator.yearly(
        sales: sales,
        products: products,
        year: year,
      );

  /// 商品维度排行（monthlyStats 的便捷入口）
  List<ProductRank> productStats(String yearMonth) =>
      monthlyStats(yearMonth).productRanking;

  // ==================== 赊账台账 ====================

  /// 未结清的赊账，按「挂得最久的排最前」（催款优先级）
  List<Credit> unsettledCredits() {
    final list = credits.where((c) => !c.settled).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// 已结清的赊账，最近结清的排最前
  List<Credit> settledCredits() {
    final list = credits.where((c) => c.settled).toList()
      ..sort((a, b) => (b.settledDate ?? b.date).compareTo(a.settledDate ?? a.date));
    return list;
  }

  /// 全部赊账按日期倒序（列表展示用）
  List<Credit> allCredits() {
    final list = List<Credit>.of(credits)
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// 未收回的欠款合计
  double get unsettledCreditTotal => credits
      .where((c) => !c.settled)
      .fold(0.0, (sum, c) => sum + c.amount);

  /// 按客户聚合未结清欠款（「谁一共欠多少」），欠得多的排前面
  List<CreditByCustomer> creditsByCustomer() {
    final map = <String, List<Credit>>{};
    for (final c in unsettledCredits()) {
      final key = c.customer.trim().isEmpty ? '（未填写姓名）' : c.customer.trim();
      map.putIfAbsent(key, () => []).add(c);
    }
    final out = map.entries.map((e) {
      final list = e.value;
      final oldest = list
          .map((c) => c.date)
          .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
      return CreditByCustomer(
        customer: e.key,
        total: list.fold(0.0, (s, c) => s + c.amount),
        count: list.length,
        oldestDate: oldest,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  void addCredit(Credit c) {
    credits.add(c);
    _persistCredits();
    notifyListeners();
  }

  void updateCredit(Credit c) {
    final i = credits.indexWhere((e) => e.id == c.id);
    if (i >= 0) credits[i] = c;
    _persistCredits();
    notifyListeners();
  }

  void deleteCredit(String id) {
    credits.removeWhere((e) => e.id == id);
    _persistCredits();
    notifyListeners();
  }

  /// 标记结清（[date] 默认今天）
  void settleCredit(String id, {String? date}) {
    final i = credits.indexWhere((e) => e.id == id);
    if (i < 0) return;
    credits[i] = credits[i].copyWith(
      settled: true,
      settledDate: date ?? du.todayKey(),
    );
    _persistCredits();
    notifyListeners();
  }

  /// 撤销结清
  void unsettleCredit(String id) {
    final i = credits.indexWhere((e) => e.id == id);
    if (i < 0) return;
    credits[i] = credits[i].copyWith(settled: false, clearSettledDate: true);
    _persistCredits();
    notifyListeners();
  }

  // ==================== 跨 Tab 预填 ====================

  /// 商品页发起「记一笔」：RootPage 监听后切到营业额首页。
  void requestPrefill(String productId) {
    final p = findById(productId);
    if (p == null) return;
    salePrefill.value =
        SalePrefill(productId: p.id, name: p.name, unitPrice: p.retailPrice);
  }

  /// SalesPage 消费预填请求（返回后清空，避免重复入账）。
  SalePrefill? consumePrefill() {
    final v = salePrefill.value;
    salePrefill.value = null;
    return v;
  }

  // ==================== 备份 / 恢复 ====================

  /// 导出全部数据为单 JSON 字符串（v3：商品 + 分类 + 销售 + 赊账）
  String exportBackup() => BackupCodec.encode(
        products: products,
        categories: categories,
        sales: sales,
        credits: credits,
      );

  /// 记下「刚刚成功备份过」，供首页提醒使用。
  void markBackedUp() {
    lastBackupAt = DateTime.now();
    _persistLastBackup();
    notifyListeners();
  }

  /// 距上次备份的天数；从未备份返回 null
  int? get daysSinceBackup {
    final t = lastBackupAt;
    return t == null ? null : DateTime.now().difference(t).inDays;
  }

  /// 从备份 JSON 恢复。
  ///
  /// 分三阶段，关键点是**确认解析全部成功之后才替换内存**：
  /// ① 全部解析到临时变量并校验（坏行跳过并计数）；
  /// ② 把当前数据存成「恢复前快照」，再整体替换；
  /// ③ 落盘，任一步写入失败就回滚到快照。
  ///
  /// 旧实现一边赋值一边解析，中途抛异常时内存已被部分替换，界面却提示
  /// 「格式不对，恢复失败」——用户以为没动过，实际已经变成「备份的商品 +
  /// 原来的营业额」，下一次编辑就把这个半恢复状态落盘。
  Future<RestoreResult> importBackup(String jsonText) async {
    final payload = BackupCodec.decode(jsonText);
    if (payload == null) {
      return RestoreResult.fail('这不是备份文件，无法解析');
    }

    // 保护：备份里一个商品都没有，而本地有 → 多半选错了文件，宁可不动
    if (payload.products.isEmpty && products.isNotEmpty) {
      return RestoreResult.fail('备份里没有任何商品，已取消恢复以保护现有数据');
    }

    // ---- 阶段二：存快照 → 整体替换 ----
    final snapshot = exportBackup();
    // seeded / 序号不属于业务数据，不在备份里，回滚时单独还原
    final prevSeeded = seeded;
    final prevNextSeq = _nextSeq;

    products = payload.products;
    categories = payload.categories;
    sales = payload.sales;
    credits = payload.credits;
    seeded = true;
    _syncSeq();

    // ---- 阶段三：落盘；失败则**内存 + 磁盘一起回滚** ----
    try {
      await _writeAll();
      await _writeRestoreSnapshot(snapshot);
      hasRestoreSnapshot = true;
    } catch (_) {
      final rollback = BackupCodec.decode(snapshot);
      if (rollback != null) {
        products = rollback.products;
        categories = rollback.categories;
        sales = rollback.sales;
        credits = rollback.credits;
      }
      seeded = prevSeeded;
      _nextSeq = prevNextSeq;

      // 关键：必须把回滚后的内存**重新写回磁盘**。
      // 上面的多步写入里，前面几步可能已经成功提交（例如商品 / 分类已换成
      // 备份里的），此时若只回滚内存，磁盘上就留下「新商品 + 旧营业额」的
      // 撕裂状态，且快照也没写成功 —— 用户杀进程重启后原数据再也找不回来。
      try {
        await _writeAll();
      } catch (_) {
        // 磁盘彻底不可写：内存至少还是对的，下面提示用户立刻导出备份
        saveError = '保存失败，请立即导出备份';
      }
      notifyListeners();
      return RestoreResult.fail('写入失败，已回滚到恢复前的数据，请尽快导出备份确认');
    }

    notifyListeners();
    return RestoreResult.ok(
      productCount: products.length,
      dayCount: sales.length,
      skipped: payload.skipped,
      creditCount: credits.length,
    );
  }

  /// 撤销上一次恢复：把数据还原成「执行那次恢复之前」的样子。
  Future<bool> undoLastRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_kRestoreSnapshot);
    if (text == null || text.isEmpty) return false;
    final r = await importBackup(text);
    return r.ok;
  }

  /// 恢复前预览：只统计数量，不构造模型、不改动任何状态。
  /// 返回 null 表示这不是一个可识别的备份文件。
  BackupPreview? previewBackup(String jsonText) => BackupCodec.preview(jsonText);

  // ==================== 坚果云同步 ====================

  void updateSyncConfig(NutstoreConfig c) {
    syncConfig = c;
    _persistSyncConfig();
    notifyListeners();
  }

  /// 测连通性
  Future<SyncResult> testSync() => NutstoreSync.test(syncConfig);

  /// 上传：本地 → 云端
  Future<SyncResult> syncUpload() async {
    final r = await NutstoreSync.upload(syncConfig, exportBackup());
    if (r.ok) {
      lastSyncAt = DateTime.now();
      lastSyncError = null;
      markBackedUp(); // 云端有备份 = 已备份，首页提醒随之消失
    } else {
      lastSyncError = r.message;
    }
    _persistSyncLast();
    notifyListeners();
    return r;
  }

  /// 拉取远端备份文本（不落地）。远端不存在返回 null。
  /// 失败抛 [SyncException]（带一句人话）。
  Future<RemoteFile?> fetchRemote() async {
    final f = await NutstoreSync.download(syncConfig);
    if (f != null) {
      lastSyncError = null;
      _persistSyncLast();
    }
    return f;
  }

  /// 把远端文本恢复进本地（内部走 importBackup，因此自带快照 + 可撤销）
  Future<RestoreResult> applyRemote(String text) async {
    final r = await importBackup(text);
    if (r.ok) {
      lastSyncAt = DateTime.now();
      lastSyncError = null;
      _persistSyncLast();
      pendingRemotePreview = null;
      _pendingRemoteText = null;
      notifyListeners();
    }
    return r;
  }

  /// 启动时的自动同步检查。
  ///
  /// **只读比对，绝不静默覆盖本地数据**：发现云端比本机新时，把预览挂在
  /// [pendingRemotePreview] 上由 UI 提示用户，是否恢复完全由用户决定。
  /// 启动阶段网络异常一律静默（不该因为一次断网就在首页弹错误）。
  Future<void> checkRemote() async {
    if (kIsWeb || !syncConfig.autoSync || !syncConfig.isConfigured) return;
    try {
      final f = await NutstoreSync.download(syncConfig);
      if (f == null) return;
      final preview = previewBackup(f.content);
      if (preview == null) return;

      final remoteAt = preview.exportedAt == null
          ? null
          : DateTime.tryParse(preview.exportedAt!);
      // 云端导出时间晚于本机上次同步时间 → 说明另一端有新改动
      final remoteNewer = remoteAt != null &&
          (lastSyncAt == null || remoteAt.isAfter(lastSyncAt!));
      if (!remoteNewer) return;

      pendingRemotePreview = preview;
      _pendingRemoteText = f.content;
      notifyListeners();
    } catch (_) {
      // 静默
    }
  }

  void dismissPendingRemote() {
    pendingRemotePreview = null;
    _pendingRemoteText = null;
    notifyListeners();
  }

  /// 应用启动时挂起的云端备份
  Future<RestoreResult> applyPendingRemote() async {
    final text = _pendingRemoteText;
    if (text == null) {
      return RestoreResult.fail('没有待恢复的云端备份');
    }
    return applyRemote(text);
  }

  // ==================== 商品 CSV 导入 / 导出 ====================

  /// 导出全部商品为 CSV 文本（带表头）
  String exportCsv() {
    final rows = <List<String>>[Product.csvHeader];
    for (final p in products) {
      rows.add(p.toCsvRow());
    }
    return const CsvCodec().encode(rows);
  }

  /// 按条码合并导入商品。
  ///
  /// 已有条码 → 覆盖名称/分类/价格等字段，但**不碰库存字段**：库存已不再对外
  /// 使用，保留该字段只是为了避免销毁用户已有的历史数据。
  ///
  /// 价格字段为 0 时**保留原值**：CSV 里的空单元格会被解析成 0，直接覆盖会把
  /// 用户填好的零售价/进价静默清零（0 也不是合法的零售价）。
  ImportResult importProducts(List<Product> incoming) {
    int overwritten = 0, added = 0, skipped = 0;
    for (final p in incoming) {
      if (p.name.isEmpty && p.barcode.isEmpty) {
        skipped++;
        continue;
      }
      if (p.barcode.isNotEmpty) {
        final existing = findByBarcode(p.barcode);
        if (existing != null) {
          existing
            ..name = p.name
            ..category = p.category
            ..brand = p.brand
            ..barcode = p.barcode;
          if (p.wholesalePrice > 0) existing.wholesalePrice = p.wholesalePrice;
          if (p.purchasePrice > 0) existing.purchasePrice = p.purchasePrice;
          if (p.retailPrice > 0) existing.retailPrice = p.retailPrice;
          overwritten++;
          continue;
        }
      }
      products.add(Product(
        id: _allocId(),
        name: p.name,
        category: p.category,
        brand: p.brand,
        barcode: p.barcode,
        wholesalePrice: p.wholesalePrice,
        purchasePrice: p.purchasePrice,
        retailPrice: p.retailPrice,
      ));
      added++;
    }
    _persistProducts();
    _persistNextSeq();
    notifyListeners();
    return ImportResult(overwritten: overwritten, added: added, skipped: skipped);
  }

  // ==================== 持久化 ====================

  /// 统一的落盘入口：**绝不静默吞掉失败**。
  ///
  /// 旧实现所有 `_persist*` 都不 await、不捕获异常，磁盘写失败或 Web 端
  /// localStorage 配额超限时改动直接丢失，而界面早已弹出「已保存」。
  /// 这里失败会写入 [saveError] 并通知 UI，提示用户立即导出备份。
  void _save(Future<void> Function() write) {
    write().then((_) {
      if (saveError != null) {
        saveError = null;
        notifyListeners();
      }
    }, onError: (Object _) {
      saveError = '保存失败，请立即导出备份';
      notifyListeners();
    });
  }

  // 下面这组 `_persist*` 供各变更路径「发射后不管」地调用（自带失败捕获）。
  void _persistProducts() => _save(_writeProducts);
  void _persistCategories() => _save(_writeCategories);
  void _persistSales() => _save(_writeSales);
  void _persistCredits() => _save(_writeCredits);
  void _persistSeeded() => _save(_writeSeeded);
  void _persistNextSeq() => _save(_writeNextSeq);
  void _persistLastBackup() => _save(_writeLastBackup);
  void _persistSyncConfig() => _save(_writeSyncConfig);
  void _persistSyncLast() => _save(_writeSyncLast);

  // 下面这组是真正的写入实现，失败会向上抛，供需要 `await` 的流程
  // （如恢复备份）使用，以便失败时回滚。

  /// 一次性把全部业务数据写盘。
  ///
  /// 恢复流程专用：多步分开写时，中途失败会留下「一半新一半旧」的磁盘状态，
  /// 所以提交路径和回滚路径都用这一把入口，尽量收敛到「全有或全无」。
  Future<void> _writeAll() async {
    final steps = <Future<void> Function()>[
      _writeProducts,
      _writeCategories,
      _writeSales,
      _writeCredits,
      _writeSeeded,
      _writeNextSeq,
    ];
    for (var i = 0; i < steps.length; i++) {
      if (debugFailWriteStep == i + 1) {
        // 只失败一次：回滚时的第二次写入必须能真正落盘
        debugFailWriteStep = 0;
        throw StateError('注入的写盘失败（仅测试）');
      }
      await steps[i]();
    }
  }

  /// 仅供测试：模拟 `_writeAll()` 执行到第 n 步时写盘失败。
  ///
  /// 用来验证恢复流程的失败回滚确实是**内存 + 磁盘一起回滚**，
  /// 而不是只把内存改回去、把「一半新一半旧」留在磁盘上。
  /// 设为 0（默认）表示不注入失败。
  @visibleForTesting
  int debugFailWriteStep = 0;

  Future<void> _writeProducts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kProducts, jsonEncode(products.map((p) => p.toJson()).toList()));
  }

  Future<void> _writeCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kCategories, categories);
  }

  Future<void> _writeSales() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kSales, jsonEncode(sales.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> _writeCredits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kCredits, jsonEncode(credits.map((c) => c.toJson()).toList()));
  }

  Future<void> _writeSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeeded, seeded);
  }

  Future<void> _writeNextSeq() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNextSeq, _nextSeq);
  }

  Future<void> _writeLastBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kLastBackup, lastBackupAt?.toIso8601String() ?? '');
  }

  Future<void> _writeRestoreSnapshot(String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRestoreSnapshot, text);
  }

  Future<void> _writeSyncConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSyncConfig, jsonEncode(syncConfig.toJson()));
  }

  Future<void> _writeSyncLast() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSyncLast, lastSyncAt?.toIso8601String() ?? '');
  }
}

/// 导入结果
class ImportResult {
  ImportResult(
      {required this.overwritten, required this.added, required this.skipped});

  final int overwritten; // 有条码且已存在 → 覆盖
  final int added; // 新条码 / 空条码 → 追加
  final int skipped; // 名称与条码都为空 → 跳过
}
