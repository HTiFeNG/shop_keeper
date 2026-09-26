import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 明细行「小标签」的统一规格。
///
/// 营业额明细里品牌标签和「零售 / 批发」切换标签是**挨着显示**的，规格只要
/// 差一点（字号、内边距、圆角），用户一眼就能看出「一大一小」。所以尺寸全部
/// 收在这里，两边共用同一套常量。
///
/// 12 而非 fontCaption(13)：标签是辨识用的，比正文再轻一档，免得和商品名
/// 抢视线，也避免把明细行撑高。
const double kTagFontSize = 12;

/// 1.25 的行高让标签高度稳定在 21dp 左右，两种标签并排时不会错位
const double kTagLineHeight = 1.25;

const EdgeInsets kTagPadding =
    EdgeInsets.symmetric(horizontal: 6, vertical: 2);

const double kTagRadius = 6;

/// 标签文字样式（颜色由各处按语义自己补）
const TextStyle kTagTextStyle =
    TextStyle(fontSize: kTagFontSize, height: kTagLineHeight);

/// 品牌小标签。
///
/// 存在的唯一目的：让「农夫山泉 矿泉水」和「娃哈哈 矿泉水」在营业额明细里
/// 一眼分得开。设计上刻意做得轻 —— 淡橙底 + 细边框 + 深橙字，紧跟在商品名
/// 右边，既不抢商品名的视觉重量，也不额外占一行高度。
class BrandTag extends StatelessWidget {
  const BrandTag(this.brand, {super.key});

  /// 品牌名；空串时什么都不渲染（调用方不必自己判断）
  final String brand;

  @override
  Widget build(BuildContext context) {
    final name = brand.trim();
    if (name.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: kTagPadding,
      decoration: BoxDecoration(
        color: AppTheme.orangeSurface,
        borderRadius: BorderRadius.circular(kTagRadius),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.28)),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: kTagTextStyle.copyWith(color: AppTheme.primaryText),
      ),
    );
  }
}
