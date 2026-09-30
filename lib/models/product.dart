import '../utils/format.dart';

/// 商品数据模型
///
/// 业务字段：名称、类别、品牌、条码、批发价、参考进价、零售价、星标收藏。
/// 编号（id）由应用自动生成，只读。
///
/// 注：[stock] 自 3.0.0 起不再对外使用（库存功能已移除），保留该字段仅为
/// 不销毁用户已有的历史数据，值仍会随 JSON 备份原样读写。
class Product {
  Product({
    required this.id,
    required this.name,
    this.category = '',
    this.brand = '',
    this.barcode = '',
    this.wholesalePrice = 0,
    this.purchasePrice = 0,
    this.retailPrice = 0,
    this.stock = 0,
    this.isFavorite = false,
  });

  String id; // 编号，自动生成，如 SP0001
  String name; // 商品名称
  String category; // 类别（对应分类栏）
  String brand; // 品牌
  String barcode; // 条码
  double wholesalePrice; // 批发价
  double purchasePrice; // 参考进价（为 0 视为缺少进价）
  double retailPrice; // 零售价
  int stock; // 已弃用（3.0.0 起不再使用），保留以免丢失历史数据
  bool isFavorite; // 星标收藏（常用商品，记账时优先展示）

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'brand': brand,
        'barcode': barcode,
        'wholesalePrice': wholesalePrice,
        'purchasePrice': purchasePrice,
        'retailPrice': retailPrice,
        'stock': stock,
        'isFavorite': isFavorite,
      };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? '',
        brand: json['brand'] as String? ?? '',
        barcode: json['barcode'] as String? ?? '',
        wholesalePrice: (json['wholesalePrice'] as num?)?.toDouble() ?? 0,
        purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0,
        retailPrice: (json['retailPrice'] as num?)?.toDouble() ?? 0,
        stock: (json['stock'] as num?)?.toInt() ?? 0,
        isFavorite: json['isFavorite'] as bool? ?? false,
      );

  /// CSV 表头（导入 / 导出共用同一格式；不加收藏列保持格式不变）
  ///
  /// 自 3.0.0 起不再导出「库存」列（库存功能已移除）。导入仍然兼容旧的
  /// 9 列文件：第 9 列存在时会照常读入，只是不再写入商品。
  static const List<String> csvHeader = [
    '编号', '名称', '类别', '品牌', '条码',
    '批发价', '参考进价', '零售价',
  ];

  List<String> toCsvRow() => [
        id, name, category, brand, _barcodeCell(barcode),
        fmtPrice(wholesalePrice), fmtPrice(purchasePrice),
        fmtPrice(retailPrice),
      ];

  /// CSV 里「条码」这一格的写法。
  ///
  /// 纯数字条码（EAN-13 就是 13 位）必须写成 Excel 的**强制文本**形式
  /// `="6901234567890"`，否则 Excel / WPS 打开时会：
  /// - 把长数字显示成科学计数法（`6.090103E+12`）；
  /// - 更糟的是**以 0 开头的条码会直接丢掉前导 0**
  ///   （`0690103000000` → `690103000000`，扫码就再也对不上了）。
  ///
  /// 这一格会被 [CsvCodec] 自动包成 `"=""6901234567890"""`（因为它含引号），
  /// Excel 打开时按公式求值成文本，显示完整数字；本 App 重新导入时再由
  /// [Product.fromCsvRow] 还原。非纯数字条码本来就会被当成文本，不需要包装。
  static String _barcodeCell(String barcode) {
    if (barcode.isEmpty) return '';
    if (!RegExp(r'^\d+$').hasMatch(barcode)) return barcode;
    return '="$barcode"';
  }

  /// 还原 CSV 里的条码：剥掉上面那种 Excel 强制文本的包装。
  ///
  /// 兼容三种来源：`="690..."`（本 App 导出的）、`=690...`（Excel 把公式
  /// 存回来的）、`'690...`（用户手工在 Excel 里用前导单引号强制文本）。
  static String _parseBarcode(String raw) {
    var s = raw.trim();
    if (s.startsWith('=')) {
      s = s.substring(1).trim();
      if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
        s = s.substring(1, s.length - 1);
      }
    }
    if (s.startsWith("'")) s = s.substring(1);
    return s.trim();
  }

  /// 从 CSV 行解析（列顺序需与 [csvHeader] 一致）
  factory Product.fromCsvRow(List<String> row) => Product(
        id: row.isNotEmpty ? row[0].trim() : '',
        name: row.length > 1 ? row[1].trim() : '',
        category: row.length > 2 ? row[2].trim() : '',
        brand: row.length > 3 ? row[3].trim() : '',
        barcode: row.length > 4 ? _parseBarcode(row[4]) : '',
        wholesalePrice: row.length > 5 ? parsePrice(row[5]) : 0,
        purchasePrice: row.length > 6 ? parsePrice(row[6]) : 0,
        retailPrice: row.length > 7 ? parsePrice(row[7]) : 0,
        stock: _parseInt(row.length > 8 ? row[8] : ''),
      );

  static int _parseInt(String s) {
    final v = double.tryParse(s.trim());
    if (v == null || !v.isFinite) return 0;
    return v.round();
  }
}
