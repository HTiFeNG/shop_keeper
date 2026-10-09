import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 商品列表项：商品名、**品牌标签**、**可点分类标签**、红色零售价、条码、星标、「记一笔」。
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

  /// 商品行里「小标签」的统一容器。
  ///
  /// 品牌标签和分类标签在行内是**并排站着的一对**，规格必须完全一致
  /// （高度 / 内边距 / 圆角 / 字号 / 图标尺寸）—— 差一点就能看出「一大一小」。
  /// 这和营业额明细行把品牌标签与价签统一到 `kTag*` 是同一个道理，
  /// 所以两者都从这里出，不各写各的。
  ///
  /// 注：这里**不**复用 `BrandTag` —— 那是为明细行设计的（21dp 高，和价签配对）；
  /// 商品页的标签要和「可点的分类标签」等高，两边的参照物不同。
  Widget _tag({
    required IconData icon,
    required String label,
    required bool highlight,
    VoidCallback? onTap,
    bool showArrow = false,
    double maxLabelWidth = 52,
  }) {
    final fg = highlight ? AppTheme.primaryText : AppTheme.textSecondary;
    return Material(
      color: highlight ? AppTheme.orangeSurface : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          // key 供组件测试按标签取尺寸用（验证两个标签等高）
          key: ValueKey('tag-$label'),
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: highlight
                  ? AppTheme.primary.withValues(alpha: 0.28)
                  : AppTheme.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
              // 外面套 Flexible 才是防溢出的关键：这一行在 360dp 屏上只有
              // 约 90dp 可用，空间不够时先让文字收缩（省略号），标签本身
              // 绝不被顶出边界。
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabelWidth),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppTheme.fontSmall, color: fg),
                  ),
                ),
              ),
              if (showArrow) ...[
                const SizedBox(width: 2),
                // 小箭头是「这里能点」的视觉暗示；不可点时干脆不画
                Icon(Icons.arrow_drop_down, size: 14, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 品牌标签（不可点，纯展示）。
  ///
  /// 存在的意义：让「农夫山泉 矿泉水」和「娃哈哈 矿泉水」一眼分得开。
  Widget _brandChip() => _tag(
        icon: Icons.local_offer_outlined,
        label: product.brand,
        highlight: true,
        // 上限 96dp 与营业额明细行一致，品牌名过长时先在标签内部省略
        maxLabelWidth: 96,
      );

  /// 分类标签。
  ///
  /// 这是「简化分类操作」的核心：以前换分类必须先进批量模式勾选商品，
  /// 现在分类本身就是个按钮，点一下直接出选择面板，两次点击搞定。
  /// 误触的代价只是弹出一个选择面板，不会改坏数据。
  Widget _categoryChip() {
    final has = product.category.isNotEmpty;
    return _tag(
      icon: has ? Icons.folder_outlined : Icons.folder_off_outlined,
      label: has ? product.category : '未分类',
      highlight: has,
      onTap: _categoryTappable ? onChangeCategory : null,
      // 批量模式下整行都是「选中」语义，不能再叠改分类
      showArrow: _categoryTappable,
    );
  }

  /// 条码：贴在卡片右下角，与「价格 / 按钮」那一列右对齐。
  ///
  /// 两个考虑：
  /// 1. **不能留在左侧那一列** —— 那列在 360dp 屏上只有约 90dp 可用
  ///    （右侧三个 48dp 图标按钮吃掉 144dp），而 13 位条码自己就要约 91dp，
  ///    永远被省略号截成 `6901…`。条码是核对商品的主要凭据，看不全等于没有。
  /// 2. **也不靠左占满一整行** —— 那样右边会留一大片空白，卡片显得松散。
  ///    右对齐后它正好落在价格和按钮下方，左侧整片空间留给名称与标签。
  ///
  /// 没填条码时整行不渲染（调用方判断），不占位置。
  Widget _barcodeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(Icons.qr_code_2, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        // 兜底：条码异常长时不横向溢出（正常 13 位远用不到）
        Flexible(
          child: Text(
            product.barcode,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.textSecondary,
              // 数字间略微放开：13 位连在一起的数字很容易看串行，
              // 加一点字距才好逐位核对
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 主行：名称 / 品牌 + 分类标签 | 价格 | 三个操作按钮
              Row(
                children: [
                  if (_batchMode) ...[
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color:
                          selected ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                  ],
                  // 左：名称（含星标）/ 品牌 + 分类标签
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (product.isFavorite)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(Icons.star,
                                    size: 15, color: AppTheme.chartPeak),
                              ),
                            Expanded(
                              child: Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: AppTheme.fontBody,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        // 品牌 + 分类标签同一行，用 Wrap 让它俩放不下时自动换行。
                        //
                        // 这一侧在 360dp 屏上只有约 100dp 可用，两个标签
                        // （品牌上限 96 + 分类上限 52）硬并排必然溢出 ——
                        // 组件测试里实测溢出 24px。Wrap 自动换行，两种标签
                        // 都能完整显示，代价只是极窄屏上多占一行。
                        if (product.brand.isNotEmpty ||
                            product.category.isNotEmpty ||
                            _categoryTappable) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (product.brand.isNotEmpty) _brandChip(),
                              if (product.category.isNotEmpty ||
                                  _categoryTappable)
                                _categoryChip(),
                            ],
                          ),
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
                        style: TextStyle(
                          fontSize: AppTheme.fontCardTitle,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.priceRed,
                        ),
                      ),
                      if (product.wholesalePrice > 0)
                        Text(
                          '批 ¥${fmtPrice(product.wholesalePrice)}',
                          style: TextStyle(
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
                      icon: Icon(Icons.delete_outline,
                          size: 20, color: AppTheme.textSecondary),
                      onPressed: () => _confirmDelete(context),
                    ),
                  ],
                ],
              ),
              // 底部：条码（未填则不占位置）
              if (product.barcode.isNotEmpty) ...[
                const SizedBox(height: 6),
                _barcodeRow(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
