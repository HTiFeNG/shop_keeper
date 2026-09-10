import 'dart:math';

import 'product.dart';

/// 一行销售明细。
///
/// [name] 是快照：不随后台商品改名联动（保留历史真实记录）。
/// [productId] 仅用于库存联动与统计聚合；商品被删后悬空按 null 处理。
class SaleItem {
  SaleItem({
    required this.id,
    this.name = '',
    this.quantity = 0,
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.isManualMode = false,
    this.productId,
  });

  String id; // 行唯一标识（时间戳 + 随机后缀）
  String name; // 商品名快照
  int quantity; // 数量 >= 0
  double unitPrice; // 单价（选品时带入零售价）
  double totalPrice; // 总价 = unitPrice*quantity，或手动改写
  bool isManualMode; // true = 手动总价（解绑自动计算）
  String? productId; // 关联商品库 id；纯手输行为 null

  /// 生成唯一行 id
  static String newId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFF);
    return '$ms-${rand.toRadixString(16)}';
  }

  /// 从商品库商品创建一行：带入名称 + 零售价，数量 1，自动联动
  factory SaleItem.fromProduct(Product p) => SaleItem(
        id: newId(),
        name: p.name,
        quantity: 1,
        unitPrice: p.retailPrice,
        totalPrice: p.retailPrice,
        isManualMode: false,
        productId: p.id,
      );

  SaleItem copy() => SaleItem(
        id: id,
        name: name,
        quantity: quantity,
        unitPrice: unitPrice,
        totalPrice: totalPrice,
        isManualMode: isManualMode,
        productId: productId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalPrice': totalPrice,
        'isManualMode': isManualMode,
        'productId': productId,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        id: json['id'] as String? ?? newId(),
        name: json['name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0,
        isManualMode: json['isManualMode'] as bool? ?? false,
        productId: json['productId'] as String?,
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
