import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 品牌小标签。
///
/// 存在的唯一目的：让「农夫山泉 矿泉水」和「娃哈哈 矿泉水」在营业额明细里
/// 一眼分得开。设计上刻意做得轻 —— 淡橙底 + 细边框 + 深橙字，紧跟在商品名
/// 右边，既不抢商品名的视觉重量，也不额外占一行高度。
class BrandTag extends StatelessWidget {
  const BrandTag(this.brand, {super.key, this.dense = false});

  /// 品牌名；空串时什么都不渲染（调用方不必自己判断）
  final String brand;

  /// 紧凑模式：宽屏表格行高有限，内边距再收一档
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final name = brand.trim();
    if (name.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 6,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.orangeSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.28)),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // 12 而非 fontCaption(13)：这是辨识用的标签，比正文再轻一档，
        // 免得和商品名抢视线，也避免把明细行撑高。
        style: const TextStyle(
          fontSize: 12,
          height: 1.25,
          color: AppTheme.primaryText,
        ),
      ),
    );
  }
}
