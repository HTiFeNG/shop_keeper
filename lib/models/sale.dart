import 'product.dart';

/// 计价方式：零售 / 批发。
///
/// 一箱饮料按零售价一瓶瓶卖，和整箱按批发价出去，是两笔完全不同的生意，
/// 记账时必须能区分——否则「批发价」字段就永远只是个没人用的摆设。
enum SalePriceMode {
  retail('retail', '零售'),
  wholesale('wholesale', '批发');

  const SalePriceMode(this.storageName, this.label);

  final String storageName; // 落盘的稳定标识（不要用 index，重排会串数据）
  final String label; // UI 显示

  static SalePriceMode fromName(String? name) => SalePriceMode.values.firstWhere(
        (e) => e.storageName == name,
        orElse: () => SalePriceMode.retail,
      );
}

/// 一行销售明细。
///
/// [name] 是快照：不随后台商品改名联动（保留历史真实记录）。
/// [productId] 用于统计聚合；商品被删后悬空按 null 处理。
class SaleItem {
  SaleItem({
    required this.id,
    this.name = '',
    this.quantity = 0,
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.isManualMode = false,
    this.productId,
    this.costPrice,
    this.priceMode = SalePriceMode.retail,
    this.retailPrice,
    this.wholesalePrice,
  });

  String id; // 行唯一标识（微秒时间戳 + 进程内自增，避免同毫秒碰撞）
  String name; // 商品名快照
  int quantity; // 数量 >= 0
  double unitPrice; // 单价（选品时按计价方式带入）
  double totalPrice; // 总价 = unitPrice*quantity，或手动改写
  bool isManualMode; // true = 手动总价（解绑自动计算）
  String? productId; // 关联商品库 id；纯手输行为 null

  /// 售出时的参考进价快照（null = 当时未填进价）。
  ///
  /// 必须在成交时定格：否则以后修改商品进价会把**已经过去**的月份毛利
  /// 一起改掉，历史报表无法复现。
  double? costPrice;

  /// 计价方式（零售 / 批发）
  SalePriceMode priceMode;

  /// 商品零售价快照（用于在行内切换计价方式）
  double? retailPrice;

  /// 商品批发价快照（null / 0 = 该商品没有批发价，不显示切换入口）
  double? wholesalePrice;

  /// 能否切换零售/批发：必须是商品库来的行，且商品有批发价
  bool get canSwitchPriceMode =>
      productId != null && (wholesalePrice ?? 0) > 0;

  /// 切到零售时应使用的单价（老数据没有快照 → 退回当前单价）
  double get baseRetailPrice => retailPrice ?? unitPrice;

  /// 生成唯一行 id：微秒时间戳 + 进程内自增序号。
  ///
  /// 旧实现是「毫秒 + 16 位随机数」，同一毫秒内建多行有碰撞风险；
  /// 一旦碰撞，按 id 查找只会命中第一行，编辑/删除会改错行。
  static int _seq = 0;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${(_seq++).toRadixString(16)}';

  /// 从商品库商品创建一行：带入名称 + 价格 + 进价快照，数量 1
  factory SaleItem.fromProduct(
    Product p, {
    SalePriceMode mode = SalePriceMode.retail,
  }) {
    final hasWholesale = p.wholesalePrice > 0;
    final useWholesale = mode == SalePriceMode.wholesale && hasWholesale;
    final price = useWholesale ? p.wholesalePrice : p.retailPrice;
    return SaleItem(
      id: newId(),
      name: p.name,
      quantity: 1,
      unitPrice: price,
      totalPrice: price,
      isManualMode: false,
      productId: p.id,
      costPrice: p.purchasePrice > 0 ? p.purchasePrice : null,
      priceMode: useWholesale ? SalePriceMode.wholesale : SalePriceMode.retail,
      retailPrice: p.retailPrice,
      wholesalePrice: hasWholesale ? p.wholesalePrice : null,
    );
  }

  /// 按当前 [priceMode] 重算单价与总价（恢复自动联动）
  SaleItem withPriceMode(SalePriceMode mode) {
    final price = mode == SalePriceMode.wholesale
        ? (wholesalePrice ?? unitPrice)
        : baseRetailPrice;
    return copy()
      ..priceMode = mode
      ..unitPrice = price
      ..totalPrice = price * quantity
      ..isManualMode = false;
  }

  SaleItem copy() => SaleItem(
        id: id,
        name: name,
        quantity: quantity,
        unitPrice: unitPrice,
        totalPrice: totalPrice,
        isManualMode: isManualMode,
        productId: productId,
        costPrice: costPrice,
        priceMode: priceMode,
        retailPrice: retailPrice,
        wholesalePrice: wholesalePrice,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalPrice': totalPrice,
        'isManualMode': isManualMode,
        'productId': productId,
        'costPrice': costPrice,
        'priceMode': priceMode.storageName,
        'retailPrice': retailPrice,
        'wholesalePrice': wholesalePrice,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        id: json['id'] as String? ?? newId(),
        name: json['name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0,
        isManualMode: json['isManualMode'] as bool? ?? false,
        productId: json['productId'] as String?,
        costPrice: (json['costPrice'] as num?)?.toDouble(),
        priceMode: SalePriceMode.fromName(json['priceMode'] as String?),
        retailPrice: (json['retailPrice'] as num?)?.toDouble(),
        wholesalePrice: (json['wholesalePrice'] as num?)?.toDouble(),
      );
}

/// 一天的营业记录。
class DailyRecord {
  DailyRecord({required this.date, List<SaleItem>? items})
      : items = items ?? [];

  String date; // 'YYYY-MM-DD' 本地时区
  List<SaleItem> items;

  /// 日合计营业额
  double get total => items.fold(0.0, (sum, e) => sum + e.totalPrice);

  /// 日合计件数
  int get totalQuantity => items.fold(0, (sum, e) => sum + e.quantity);

  Map<String, dynamic> toJson() => {
        'date': date,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory DailyRecord.fromJson(Map<String, dynamic> json) => DailyRecord(
        date: json['date'] as String? ?? '',
        items: (json['items'] as List? ?? [])
            .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 商品页「记一笔」→ 首页预填一行 的跨 Tab 通知载体。
class SalePrefill {
  SalePrefill({
    required this.productId,
    required this.name,
    required this.unitPrice,
  });

  final String productId;
  final String name;
  final double unitPrice;
}
