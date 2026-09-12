import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 商品列表项：商品名、条码、品牌类别、红色零售价、星标、「记一笔」快捷按钮。
///
/// - 点击整行 → 编辑；垃圾桶 → 删除（带确认）；
/// - 「记一笔」→ 首页预填一行（store.requestPrefill）；
/// - ★ → 切换常用商品（直接影响首页一键记账栏）；
/// - 未填参考进价 → 提示「进价未填」，因为毛利会漏算这一项；
/// - 批量模式（onSelectToggle != null）：左侧复选框，整行切换选中。
///
/// 注：库存已随「库存功能」移除，本列表不再显示库存。
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    required this.onDelete,
    this.onQuickSale,
    this.onToggleFavorite,
    this.selected = false,
    this.onSelectToggle,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// 「记一笔」快捷回调（null 时不显示按钮）
  final VoidCallback? onQuickSale;

  /// 切换星标（null 时不显示星标按钮）
  final VoidCallback? onToggleFavorite;
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
                                size: 15, color: AppTheme.chartPeak),
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
                          fontSize: AppTheme.fontCaption,
                          color: AppTheme.textSecondary),
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
                            fontSize: AppTheme.fontCaption,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 中：零售价（+ 缺进价提示，因为那会让毛利漏算）
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '¥${fmtPrice(product.retailPrice)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.priceRed,
                    ),
                  ),
                  if (product.purchasePrice <= 0) ...[
                    const SizedBox(height: 2),
                    const Text(
                      '进价未填',
                      style: TextStyle(
                          fontSize: AppTheme.fontCaption,
                          color: AppTheme.primaryText),
                    ),
                  ],
                ],
              ),
              // 右：星标 + 记一笔 + 删除（批量模式下隐藏）
              if (!_batchMode) ...[
                if (onToggleFavorite != null)
                  IconButton(
                    tooltip: product.isFavorite ? '取消常用' : '设为常用',
                    icon: Icon(
                      product.isFavorite ? Icons.star : Icons.star_border,
                      size: 22,
                      color: product.isFavorite
                          ? AppTheme.chartPeak
                          : AppTheme.textSecondary,
                    ),
                    onPressed: onToggleFavorite,
                  ),
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
}
