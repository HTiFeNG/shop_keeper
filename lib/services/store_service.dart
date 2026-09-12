import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sample_products.dart';
import '../models/monthly_stats.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/csv_codec.dart';
import '../utils/date_utils.dart' as du;

/// 固定分类名：不可删除、不可重命名
const String kCategoryAll = '全部';
const String kCategoryNone = '未分类';

/// 数据层：商品 / 分类 / 搜索历史 / 销售记录 的本地持久化与全部业务逻辑。
///
/// 存储方案：shared_preferences + JSON 字符串（Web 端自动落 localStorage）。
/// 所有键名统一 `sk_` 前缀，与旧 product_store（ps_*）/ 旧 sales-tracker 零冲突。
/// 所有修改操作立即落盘并 notifyListeners()，页面通过 ListenableBuilder 自动刷新。
class StoreService extends ChangeNotifier {
  StoreService._();

  static final StoreService instance = StoreService._();

  static const String _kProducts = 'sk_products';
  static const String _kCategories = 'sk_categories';
  static const String _kSales = 'sk_sales';
  static const String _kSeeded = 'sk_seeded';
  static const String _kNextSeq = 'sk_next_seq';
  static const String _kLastBackup = 'sk_last_backup';
  static const String _kRestoreSnapshot = 'sk_restore_snapshot';

  List<Product> products = [];
  List<String> categories = []; // 不含固定项「全部」「未分类」

  /// 销售记录：键为日期 `YYYY-MM-DD`
  Map<String, DailyRecord> sales = {};

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

  /// 上次成功导出备份的时间（null = 从未备份）
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

  /// 上移 / 下移分类（自定义顺序），delta = -1 上移、1 下移
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

  bool _isDuplicateCategory(String name, {String? ignore}) {
    if (name == kCategoryAll || name == kCategoryNone) return true;
    return categories.any((c) => c == name && c != ignore);
  }

  // ==================== 销售记录 ====================

  /// 某天的明细行列表（无记录返回空列表，不创建空记录）
  List<SaleItem> itemsOf(String date) => sales[date]?.items ?? [];

  /// 某天的日合计
  double dayTotal(String date) => sales[date]?.total ?? 0;

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

  /// 记录一件商品的销售：当天已有同商品行（productId 相同）→ 数量+1 合并，
  /// 否则新建一行。
  ///
  /// 手动改过总价的行（抹零 / 改价）合并时，把那份总价理解为**该行的实际
  /// 单价**再按新数量等比放大：1 件手动 ¥5 → 再卖 1 件 = 2 件 ¥10。
  /// 旧实现直接沿用原总价，会出现「件数 +1、营业额却一分没涨」的漏记。
  void recordSaleFromProduct(String date, Product product) {
    final record = sales[date];
    if (record != null) {
      final idx = record.items.indexWhere((e) => e.productId == product.id);
      if (idx >= 0) {
        final it = record.items[idx];
        final q = it.quantity + 1;
        final double total = it.isManualMode
            ? (it.quantity > 0 ? it.totalPrice / it.quantity * q : q * it.unitPrice)
            : q * it.unitPrice;
        upsertSaleItem(date, it.copy()
          ..quantity = q
          ..totalPrice = total);
        return;
      }
    }
    upsertSaleItem(date, SaleItem.fromProduct(product));
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

  // ==================== 月度统计 ====================

  /// 按月聚合统计（含环比、商品排行、估算毛利）。
  MonthlyStats monthlyStats(String yearMonth) {
    final monthRecords = sales.values
        .where((r) => r.date.startsWith(yearMonth) && r.items.isNotEmpty)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final dailyData = <MonthlyDayData>[];
    // 商品维度聚合：key = productId 或 'name:名称'（悬空 / 手输行按名称聚合）
    final Map<String, ProductRank> rankMap = {};
    // 一次性建索引：旧实现每行都线性扫一遍 products，
    // 「几百个商品 × 一个月几千行」会在 UI 线程上明显卡顿。
    final byId = {for (final p in products) p.id: p};
    double estimatedProfit = 0;
    int missingCostLines = 0;

    for (final record in monthRecords) {
      double revenue = 0;
      int totalQuantity = 0;
      for (final item in record.items) {
        revenue += item.totalPrice;
        totalQuantity += item.quantity;

        final key = item.productId ?? 'name:${item.name}';
        final rank = rankMap.putIfAbsent(
          key,
          () => ProductRank(
              productId: item.productId, name: item.name, quantity: 0, revenue: 0),
        );
        rankMap[key] = ProductRank(
          productId: rank.productId,
          name: rank.name,
          quantity: rank.quantity + item.quantity,
          revenue: rank.revenue + item.totalPrice,
        );

        // 估算毛利：营收取 totalPrice（与上面完全同口径），成本取**售出时快照**。
        // 快照缺失（升级前的老数据、或当时没填进价）才退回商品库当前进价。
        // 刻意不再用 margin > 0 过滤：亏本清仓必须记成负数，否则毛利被高估。
        final cost = item.costPrice ??
            (item.productId == null ? null : byId[item.productId!]?.purchasePrice);
        if (cost != null && cost > 0) {
          estimatedProfit += item.totalPrice - cost * item.quantity;
        } else {
          missingCostLines++;
        }
      }
      dailyData.add(MonthlyDayData(
        date: record.date,
        revenue: revenue,
        productCount: record.items.length,
        totalQuantity: totalQuantity,
      ));
    }

    final totalRevenue = dailyData.fold(0.0, (s, d) => s + d.revenue);
    final totalItems = dailyData.fold(0, (s, d) => s + d.totalQuantity);
    final recordCount = dailyData.length;
    final averageRevenue = recordCount > 0 ? totalRevenue / recordCount : 0.0;

    // 最高日：初始化为第一天，营收并列时保留最早日期
    double maxRevenue = dailyData.isNotEmpty ? dailyData.first.revenue : 0;
    String? maxRevenueDate = dailyData.isNotEmpty ? dailyData.first.date : null;
    for (var i = 1; i < dailyData.length; i++) {
      if (dailyData[i].revenue > maxRevenue) {
        maxRevenue = dailyData[i].revenue;
        maxRevenueDate = dailyData[i].date;
      }
    }

    final ranking = rankMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return MonthlyStats(
      yearMonth: yearMonth,
      dailyData: dailyData,
      totalRevenue: totalRevenue,
      averageRevenue: averageRevenue,
      maxRevenue: maxRevenue,
      maxRevenueDate: maxRevenueDate,
      totalItems: totalItems,
      recordCount: recordCount,
      prevMonthRevenue: _monthRevenue(du.prevMonth(yearMonth)),
      estimatedProfit: estimatedProfit,
      profitMissingCostLines: missingCostLines,
      productRanking: ranking,
    );
  }

  /// 某月总营收（内部环比用，不递归）
  double _monthRevenue(String yearMonth) {
    double sum = 0;
    for (final r in sales.values) {
      if (r.date.startsWith(yearMonth)) {
        sum += r.total;
      }
    }
    return sum;
  }

  /// 商品维度排行（monthlyStats 的便捷入口）
  List<ProductRank> productStats(String yearMonth) =>
      monthlyStats(yearMonth).productRanking;

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

  /// 导出全部数据为单 JSON 字符串（版本 2，含商品 + 分类 + 销售记录）
  String exportBackup() {
    final map = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'products': products.map((p) => p.toJson()).toList(),
      'categories': categories,
      'sales': sales.map((k, v) => MapEntry(k, v.toJson())),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// 记下「刚刚成功导出过备份」，供首页提醒使用。
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
    final map = _tryDecode(jsonText);
    if (map is! Map<String, dynamic>) {
      return RestoreResult.fail('这不是备份文件，无法解析');
    }
    if (map['version'] != 2) {
      return RestoreResult.fail('备份文件版本不支持（需要 v2）');
    }
    final productsRaw = map['products'];
    final categoriesRaw = map['categories'];
    final salesRaw = map['sales'];
    if (productsRaw is! List || categoriesRaw is! List || salesRaw is! Map) {
      return RestoreResult.fail('备份文件内容不完整');
    }

    // ---- 阶段一：全部解析 + 校验，完全不碰现有数据 ----
    final newProducts = <Product>[];
    var skipped = 0;
    for (final e in productsRaw) {
      if (e is Map<String, dynamic>) {
        final p = Product.fromJson(e);
        if (p.id.isEmpty && p.name.isEmpty) {
          skipped++;
          continue;
        }
        newProducts.add(p);
      } else {
        skipped++;
      }
    }
    final newCategories = categoriesRaw
        .whereType<String>()
        .where((c) => c != kCategoryAll)
        .toList();
    final newSales = <String, DailyRecord>{};
    for (final entry in salesRaw.entries) {
      final k = entry.key;
      final v = entry.value;
      if (k is! String || v is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final rec = DailyRecord.fromJson(v);
      rec.date = k; // 以键为准，避免「某天看得到、月度统计算不到」
      newSales[k] = rec;
    }

    // 保护：备份里一个商品都没有，而本地有 → 多半选错了文件，宁可不动
    if (newProducts.isEmpty && products.isNotEmpty) {
      return RestoreResult.fail('备份里没有任何商品，已取消恢复以保护现有数据');
    }

    // ---- 阶段二：存快照 → 整体替换 ----
    final snapshot = exportBackup();
    products = newProducts;
    categories = newCategories;
    sales = newSales;
    seeded = true;
    _syncSeq();

    // ---- 阶段三：落盘；失败则回滚 ----
    try {
      await _writeProducts();
      await _writeCategories();
      await _writeSales();
      await _writeSeeded();
      await _writeNextSeq();
      await _writeRestoreSnapshot(snapshot);
      hasRestoreSnapshot = true;
    } catch (_) {
      final rollback = _tryDecode(snapshot);
      if (rollback is Map<String, dynamic>) {
        products = (rollback['products'] as List)
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
        categories =
            (rollback['categories'] as List).whereType<String>().toList();
        sales = (rollback['sales'] as Map).map((k, v) => MapEntry(
            k as String, DailyRecord.fromJson(v as Map<String, dynamic>)));
      }
      notifyListeners();
      return RestoreResult.fail('写入失败，已回滚到恢复前的数据');
    }

    notifyListeners();
    return RestoreResult.ok(
      productCount: products.length,
      dayCount: sales.length,
      skipped: skipped,
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
  /// 返回 null 表示这不是一个可识别的 v2 备份文件。
  BackupPreview? previewBackup(String jsonText) {
    final map = _tryDecode(jsonText);
    if (map is! Map<String, dynamic>) return null;
    if (map['version'] != 2) return null;
    final p = map['products'];
    final s = map['sales'];
    if (p is! List || s is! Map) return null;
    var items = 0;
    for (final v in s.values) {
      if (v is Map && v['items'] is List) items += (v['items'] as List).length;
    }
    return BackupPreview(
      productCount: p.length,
      dayCount: s.length,
      itemCount: items,
      exportedAt: map['exportedAt'] as String?,
    );
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
            ..barcode = p.barcode
            ..wholesalePrice = p.wholesalePrice
            ..purchasePrice = p.purchasePrice
            ..retailPrice = p.retailPrice;
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

  // 下面 5 个 `_persist*` 供各变更路径「发射后不管」地调用（自带失败捕获）。
  void _persistProducts() => _save(_writeProducts);
  void _persistCategories() => _save(_writeCategories);
  void _persistSales() => _save(_writeSales);
  void _persistSeeded() => _save(_writeSeeded);
  void _persistNextSeq() => _save(_writeNextSeq);
  void _persistLastBackup() => _save(_writeLastBackup);

  // 下面 5 个是真正的写入实现，失败会向上抛，供需要 `await` 的流程
  // （如恢复备份）使用，以便失败时回滚。
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
}

/// 恢复前预览（不改动任何数据）
class BackupPreview {
  BackupPreview({
    required this.productCount,
    required this.dayCount,
    required this.itemCount,
    this.exportedAt,
  });

  final int productCount;
  final int dayCount;
  final int itemCount;
  final String? exportedAt; // 备份文件的导出时间（ISO 字符串，可能为 null）
}

/// 恢复备份的结果
class RestoreResult {
  RestoreResult.ok({
    required this.productCount,
    required this.dayCount,
    required this.skipped,
  })  : ok = true,
        reason = '';

  RestoreResult.fail(this.reason)
      : ok = false,
        productCount = 0,
        dayCount = 0,
        skipped = 0;

  final bool ok;
  final String reason; // 失败原因（面向用户的一句话）
  final int productCount; // 恢复后的商品数
  final int dayCount; // 恢复后的记账天数
  final int skipped; // 跳过的坏行数
}

/// 导入结果
class ImportResult {
  ImportResult(
      {required this.overwritten, required this.added, required this.skipped});

  final int overwritten; // 有条码且已存在 → 覆盖
  final int added; // 新条码 / 空条码 → 追加
  final int skipped; // 名称与条码都为空 → 跳过
}
