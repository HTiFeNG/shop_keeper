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
  static const String _kHistory = 'sk_search_history';
  static const String _kSales = 'sk_sales';
  static const String _kSeeded = 'sk_seeded';

  List<Product> products = [];
  List<String> categories = []; // 不含固定项「全部」「未分类」
  List<String> searchHistory = []; // 最近搜索关键词，最多 10 条，新的在前

  /// 销售记录：键为日期 `YYYY-MM-DD`
  Map<String, DailyRecord> sales = {};

  bool ready = false; // 首次加载完成前为 false

  /// 是否已完成首启询问（false → UI 弹窗询问是否载入示例数据）
  bool seeded = false;

  /// 商品页「记一笔」→ 首页预填一行 的跨 Tab 通知（解耦）
  final ValueNotifier<SalePrefill?> salePrefill = ValueNotifier<SalePrefill?>(null);

  /// 应用启动时调用
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // ---- 商品 ----
    final productsRaw = prefs.getString(_kProducts);
    if (productsRaw != null && productsRaw.isNotEmpty) {
      try {
        final list = jsonDecode(productsRaw) as List;
        products = list
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        products = [];
      }
    }

    // ---- 分类 ----
    categories = prefs.getStringList(_kCategories) ?? [];
    categories.remove(kCategoryAll);

    // ---- 首启询问语义：不再自动载入示例数据 ----
    seeded = prefs.getBool(_kSeeded) ?? false;

    // ---- 搜索历史 ----
    searchHistory = prefs.getStringList(_kHistory) ?? [];

    // ---- 销售记录 ----
    final salesRaw = prefs.getString(_kSales);
    if (salesRaw != null && salesRaw.isNotEmpty) {
      try {
        final map = jsonDecode(salesRaw) as Map<String, dynamic>;
        sales = map.map((k, v) =>
            MapEntry(k, DailyRecord.fromJson(v as Map<String, dynamic>)));
      } catch (_) {
        sales = {};
      }
    }

    ready = true;
    notifyListeners();
  }

  /// 首启弹窗选「载入示例数据」：24 商品 + 5 分类；选「从空开始」调用 markSeeded。
  void seedSampleData() {
    products = SampleProducts.build();
    categories = List.of(SampleProducts.defaultCategories);
    seeded = true;
    _persistProducts();
    _persistCategories();
    _persistSeeded();
    notifyListeners();
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

  /// 根据 id 查找商品（销售行库存联动用）
  Product? findById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 生成下一个编号：SP0001、SP0002 ……（自动递增）
  String nextId() {
    int max = 0;
    for (final p in products) {
      final m = RegExp(r'^SP(\d+)$').firstMatch(p.id);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > max) max = n;
      }
    }
    return 'SP${(max + 1).toString().padLeft(4, '0')}';
  }

  void addProduct(Product p) {
    products.add(p);
    _persistProducts();
    notifyListeners();
  }

  void updateProduct(Product p) {
    final i = products.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      // 编辑页不带 isFavorite 时以内存现值为准，避免误清
      p.isFavorite = products[i].isFavorite;
      products[i] = p;
    }
    _persistProducts();
    notifyListeners();
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

  // ==================== 搜索历史 ====================

  /// 记录一次搜索：去重、置顶、最多保留 10 条
  void addSearchHistory(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    searchHistory.remove(q);
    searchHistory.insert(0, q);
    if (searchHistory.length > 10) searchHistory = searchHistory.sublist(0, 10);
    _persistHistory();
    notifyListeners();
  }

  void clearSearchHistory() {
    searchHistory = [];
    _persistHistory();
    notifyListeners();
  }

  // ==================== 销售记录 ====================

  /// 某天的明细行列表（无记录返回空列表，不创建空记录）
  List<SaleItem> itemsOf(String date) => sales[date]?.items ?? [];

  /// 某天的日合计
  double dayTotal(String date) => sales[date]?.total ?? 0;

  /// 新增 / 更新一行销售明细（数量差量算法联动库存，允许负数）。
  ///
  /// 算法要点：
  /// ① 换绑商品：先回补旧商品数量；
  /// ② 同商品：按数量差值扣减 / 回补；
  /// ③ 手动改写总价（isManualMode）不动 quantity → 不触发库存变化。
  void upsertSaleItem(String date, SaleItem newItem) {
    final record = sales.putIfAbsent(date, () => DailyRecord(date: date));
    final idx = record.items.indexWhere((e) => e.id == newItem.id);
    final oldItem = idx >= 0 ? record.items[idx] : null;

    // ① 换绑：旧行关联了别的商品 → 先回补旧商品
    if (oldItem != null &&
        oldItem.productId != null &&
        oldItem.productId != newItem.productId) {
      _applyStockDelta(findById(oldItem.productId!), oldItem.quantity);
    }

    // ② 差量扣减 / 回补新商品
    if (newItem.productId != null) {
      final oldQty =
          (oldItem != null && oldItem.productId == newItem.productId)
              ? oldItem.quantity
              : 0;
      _applyStockDelta(
          findById(newItem.productId!), -(newItem.quantity - oldQty));
    }

    // ③ 覆盖 / 追加
    if (idx >= 0) {
      record.items[idx] = newItem;
    } else {
      record.items.add(newItem);
    }
    _persistSales();
    _persistProducts();
    notifyListeners();
  }

  /// 记录一件商品的销售：当天已有同商品行（productId 相同）→ 数量+1 合并，
  /// 否则新建一行。库存差量扣减由 [upsertSaleItem] 完成。
  ///
  /// 手动模式（isManualMode）的行合并时只加数量、不改总价；
  /// 非手动行总价 = 新数量 × 单价。
  void recordSaleFromProduct(String date, Product product) {
    final record = sales[date];
    if (record != null) {
      final idx =
          record.items.indexWhere((e) => e.productId == product.id);
      if (idx >= 0) {
        final it = record.items[idx];
        final q = it.quantity + 1;
        upsertSaleItem(date, it.copy()
          ..quantity = q
          ..totalPrice = it.isManualMode ? it.totalPrice : q * it.unitPrice);
        return;
      }
    }
    upsertSaleItem(date, SaleItem.fromProduct(product));
  }

  /// 删除一行销售明细（回补库存）。
  ///
  /// 返回被删除的行（含删除位置），供 UI 层撤销还原；找不到返回 null。
  SaleItem? deleteSaleItem(String date, String itemId) {
    final record = sales[date];
    if (record == null) return null;
    final idx = record.items.indexWhere((e) => e.id == itemId);
    if (idx < 0) return null;
    final item = record.items.removeAt(idx);
    if (item.productId != null) {
      _applyStockDelta(findById(item.productId!), item.quantity);
    }
    if (record.items.isEmpty) {
      sales.remove(date); // 清空当天则不保留空记录
    }
    _persistSales();
    _persistProducts();
    notifyListeners();
    return item;
  }

  /// 库存差量调整：int 直接加减，允许负数（超卖记录）。
  /// p == null 时忽略（商品可能已被删除，productId 悬空）。
  void _applyStockDelta(Product? p, int delta) {
    if (p == null || delta == 0) return;
    p.stock += delta;
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
    double estimatedProfit = 0;

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

        // 估算毛利：仅关联商品且参考进价 > 0 才计入（按单价口径，保持口径稳定）
        if (item.productId != null) {
          final p = findById(item.productId!);
          if (p != null && p.purchasePrice > 0) {
            final margin = item.unitPrice - p.purchasePrice;
            if (margin > 0) {
              estimatedProfit += margin * item.quantity;
            }
          }
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

  // ==================== 备份 / 恢复（P1-6） ====================

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

  /// 从备份 JSON 恢复：整体校验结构后全量替换（不做合并）。
  /// 返回 false 表示格式非法。
  bool importBackup(String jsonText) {
    try {
      final map = jsonDecode(jsonText);
      if (map is! Map<String, dynamic>) return false;
      final version = map['version'];
      if (version != 2) return false;
      final productsRaw = map['products'];
      final categoriesRaw = map['categories'];
      final salesRaw = map['sales'];
      if (productsRaw is! List ||
          categoriesRaw is! List ||
          salesRaw is! Map) {
        return false;
      }
      products = productsRaw
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      categories = categoriesRaw
          .whereType<String>()
          .where((c) => c != kCategoryAll)
          .toList();
      sales = salesRaw.map((k, v) =>
          MapEntry(k as String, DailyRecord.fromJson(v as Map<String, dynamic>)));
      seeded = true;
      _persistProducts();
      _persistCategories();
      _persistSales();
      _persistSeeded();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
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

  /// 按条码合并导入商品
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
            ..retailPrice = p.retailPrice
            ..stock = p.stock;
          overwritten++;
          continue;
        }
      }
      products.add(Product(
        id: nextId(),
        name: p.name,
        category: p.category,
        brand: p.brand,
        barcode: p.barcode,
        wholesalePrice: p.wholesalePrice,
        purchasePrice: p.purchasePrice,
        retailPrice: p.retailPrice,
        stock: p.stock,
      ));
      added++;
    }
    _persistProducts();
    notifyListeners();
    return ImportResult(overwritten: overwritten, added: added, skipped: skipped);
  }

  // ==================== 持久化 ====================

  Future<void> _persistProducts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kProducts, jsonEncode(products.map((p) => p.toJson()).toList()));
  }

  Future<void> _persistCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kCategories, categories);
  }

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kHistory, searchHistory);
  }

  Future<void> _persistSales() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kSales, jsonEncode(sales.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> _persistSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeeded, seeded);
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
