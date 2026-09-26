import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 商品列表项：商品名、条码 · 品牌、**可点分类标签**、红色零售价、星标、「记一笔」。
///
/// - 点击整行 → 编辑；垃圾桶 → 删除（带确认）；
/// - **点分类标签 → 直接弹分类选择面板**（不必再进批量模式，见 [onChangeCategory]）；
/// - 「记一笔」→ 首页预填一行（store.requestPrefill）；
/// - ★ → 切换常用商品（直接影响首页一键记账栏）；
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
    this.onChangeCategory,
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

  /// 点分类标签时触发（null 时分类只作展示、不可点）
  final VoidCallback? onChangeCategory;
  final bool selected;
  final VoidCallback? onSelectToggle; // 非 null 时进入批量模式

  bool get _batchMode => onSelectToggle != null;

  /// 分类标签是否可点：批量模式下整行都是「选中」语义，不能再叠改分类
  bool get _categoryTappable => onChangeCategory != null && !_batchMode;

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

  /// 可点的分类标签。
  ///
  /// 这是本次「简化分类操作」的核心：以前换分类必须先进批量模式勾选商品，
  /// 现在分类本身就是个按钮，点一下直接出选择面板，两次点击搞定。
  /// 视觉高度只有 32dp（不然会把商品行撑得很松），但外层垫到 32dp 的命中区；
  /// 误触的代价只是弹出一个选择面板，不会改坏数据。
  Widget _categoryChip() {
    final has = product.category.isNotEmpty;
    final label = has ? product.category : '未分类';
    return Material(
      color: has ? AppTheme.orangeSurface : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _categoryTappable ? onChangeCategory : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: has
                  ? AppTheme.primary.withValues(alpha: 0.28)
                  : AppTheme.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                has ? Icons.folder_outlined : Icons.folder_off_outlined,
                size: 14,
                color: has ? AppTheme.primaryText : AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              // 外面套 Flexible 才是防溢出的关键：这一行在 360dp 屏上只有
              // 约 100dp 可用，空间不够时先让文字收缩（省略号），标签本身
              // 绝不被顶出边界。
              // 外层 Column 的 crossAxisAlignment 给的是「0..可用宽」这个
              // **有界**约束，所以这里的 Flexible 合法（无界约束下会抛异常）。
              Flexible(
                child: ConstrainedBox(
                  // 上限 52 ≈ 4 个汉字，避免分类名太长时把标签撑得很宽
                  constraints: const BoxConstraints(maxWidth: 52),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          has ? AppTheme.primaryText : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              if (_categoryTappable) ...[
                const SizedBox(width: 2),
                // 小箭头是「这里能点」的视觉暗示；不可点时干脆不画
                Icon(Icons.arrow_drop_down,
                    size: 14,
                    color: has ? AppTheme.primaryText : AppTheme.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
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
                    // 条码 + 品牌合成一行纯文本。
                    //
                    // 品牌**没有**在这里做成标签：360dp 屏上这一侧只有约 100dp
                    // 可用宽度（右侧三个 48dp 图标按钮吃掉了 144dp），
                    // 「品牌标签 + 分类标签」并排必然溢出 —— 组件测试里实测
                    // 溢出 24px。合成一行 + 省略号才是稳的。
                    Text(
                      [
                        if (product.barcode.isEmpty)
                          '条码：—'
                        else
                          '条码：${product.barcode}',
                        if (product.brand.isNotEmpty) product.brand,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: AppTheme.fontCaption,
                          color: AppTheme.textSecondary),
                    ),
                    // 分类标签独占一行 —— 它是可点的，别跟别的文字抢空间
                    if (product.category.isNotEmpty || _categoryTappable) ...[
                      const SizedBox(height: 4),
                      _categoryChip(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 中：零售价（＋批发价，填过才显示）
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
                  if (product.wholesalePrice > 0)
                    Text(
                      '批 ¥${fmtPrice(product.wholesalePrice)}',
                      style: const TextStyle(
                        fontSize: AppTheme.fontCaption,
                        color: AppTheme.textSecondary,
                      ),
                    ),
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
