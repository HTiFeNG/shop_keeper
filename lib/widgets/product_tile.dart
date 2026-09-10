import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 商品列表项：商品名、条码、库存、红色零售价、星标、「记一笔」快捷按钮。
///
/// - 库存：负数红色加粗、0 < stock ≤ 3 橙色预警、其余灰色；
/// - 点击整行 → 编辑；垃圾桶 → 删除（带确认）；
/// - 「记一笔」→ 首页预填一行（store.requestPrefill）；
/// - 批量模式（onSelectToggle != null）：左侧复选框，整行切换选中。
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    required this.onDelete,
    this.onQuickSale,
    this.selected = false,
    this.onSelectToggle,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// 「记一笔」快捷回调（null 时不显示按钮）
  final VoidCallback? onQuickSale;
  final bool selected;
  final VoidCallback? onSelectToggle; // 非 null 时进入批量模式

  bool get _batchMode => onSelectToggle != null;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除商品'),
        content: Text('确定删除「${product.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.priceRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8, right: 12, top: 5, bottom: 5),
      decoration: AppTheme.cardDecoration,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: _batchMode ? onSelectToggle : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (_batchMode) ...[
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 22,
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
              ],
              // 左：名称（含星标）/ 条码 / 品牌类别
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (product.isFavorite)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.star,
                                size: 15, color: AppTheme.warningYellow),
                          ),
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.barcode.isEmpty
                          ? '条码：—'
                          : '条码：${product.barcode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    if (product.brand.isNotEmpty ||
                        product.category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (product.brand.isNotEmpty) product.brand,
                          if (product.category.isNotEmpty) product.category,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 中：库存预警 + 红色零售价
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _stockLabel(),
                  const SizedBox(height: 2),
                  Text(
                    '¥${fmtPrice(product.retailPrice)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.priceRed,
                    ),
                  ),
                ],
              ),
              // 右：记一笔 + 删除（批量模式下隐藏）
              if (!_batchMode) ...[
                if (onQuickSale != null)
                  IconButton(
                    tooltip: '记一笔销售',
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.orangeSurface,
                      foregroundColor: AppTheme.primary,
                    ),
                    icon: const Icon(Icons.point_of_sale, size: 20),
                    onPressed: onQuickSale,
                  ),
                IconButton(
                  tooltip: '删除商品',
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppTheme.textSecondary),
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 库存标签：负数红色加粗、0<≤3 橙色预警、其余灰色
  Widget _stockLabel() {
    final Color color;
    final FontWeight weight;
    final String text;
    if (product.stock < 0) {
      color = AppTheme.negativeStockRed;
      weight = FontWeight.w700;
      text = '库存 ${product.stock}（超卖）';
    } else if (product.stock <= 3) {
      color = AppTheme.lowStockOrange;
      weight = FontWeight.w600;
      text = '库存 ${product.stock}（快没了）';
    } else {
      color = AppTheme.textSecondary;
      weight = FontWeight.normal;
      text = '库存 ${product.stock}';
    }
    return Text(
      text,
      style: TextStyle(fontSize: 12, color: color, fontWeight: weight),
    );
  }
}
