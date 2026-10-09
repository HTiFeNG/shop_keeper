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
    this.onChangeCategory,
    this.selected = false,
    this.onSelectToggle,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// 「记一笔」快捷回调（null 时不显示按钮）
  final VoidCallback? onQuickSale;

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

  /// 条码：跟在标签右边、贴住卡片右边界。
  ///
  /// 不能留在第一行左侧那一列 —— 那列在 360dp 屏上只有约 90dp 可用
  /// （右侧图标按钮占掉大半），而 13 位条码自己就要约 91dp，永远被截成 `6901…`。
  /// 条码是核对商品的主要凭据，看不全等于没有。
  ///
  /// 没填条码时整个不渲染（调用方判断），不占位置。
  Widget _barcodeRow() {
    return Row(
      // min：按内容取宽，这样它贴着右边而不是把 140dp 撑满后内容靠左
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.qr_code_2, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        // 兜底：条码异常长时在内部省略（正常 13 位远用不到）
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
                  // 左：名称（含星标）。
                  //
                  // 品牌 / 分类标签与条码都挪到第二行去了 —— 第一行只留名称，
                  // 它才拿得到足够宽度显示完整。
                  Expanded(
                    child: Row(
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
                  ),
                  const SizedBox(width: 8),
                  // 中：零售价
                  //
                  // 批发价不再显示 —— 它是「编辑商品时看一眼」的信息，不该占
                  // 列表每一行的位置。需要时进编辑页即可。
                  Text(
                    '¥${fmtPrice(product.retailPrice)}',
                    style: TextStyle(
                      fontSize: AppTheme.fontCardTitle,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.priceRed,
                    ),
                  ),
                  // 右：记一笔 + 删除（批量模式下隐藏）
                  //
                  // 星标按钮已去掉：首页「最近常卖」是按销量自动生成的，并不依赖
                  // 手工加星 —— 那个按钮挤占的宽度比它的用处大得多，去掉后商品名
                  // 和标签都宽松了。要设常用时进编辑页。
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
                      icon: Icon(Icons.delete_outline,
                          size: 20, color: AppTheme.textSecondary),
                      onPressed: () => _confirmDelete(context),
                    ),
                  ],
                ],
              ),
              // 第二行：左边品牌 + 分类标签，右边条码。
              //
              // 之所以能并排放下：这一行是**整行宽**（不受右侧按钮影响），
              // 两个标签加起来约 160dp、条码约 110dp，308dp 的可用宽度绰绰有余。
              // 之前把它们挤在第一行时只有约 90dp —— 标签必然换行、条码必然被截。
              if (product.brand.isNotEmpty ||
                  product.category.isNotEmpty ||
                  _categoryTappable ||
                  product.barcode.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    // 标签区吃掉剩余宽度，把条码顶到最右
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (product.brand.isNotEmpty) _brandChip(),
                          if (product.category.isNotEmpty || _categoryTappable)
                            _categoryChip(),
                        ],
                      ),
                    ),
                    if (product.barcode.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      // 非弹性 + 上限 140dp：按内容取宽、贴住右边界，
                      // 异常长的条码则在内部省略，不会把标签挤没
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: _barcodeRow(),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
