import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 首页快捷记账条：点一下就把该商品记一行销售明细。
///
/// 优先展示星标「常用商品」；没有星标时展示「最近常卖」—— 后者完全由销售
/// 历史推导，所以新用户装上就能用上一键记账，不必先知道要去编辑页点星标。
class FavoriteQuickBar extends StatelessWidget {
  const FavoriteQuickBar({
    super.key,
    required this.favorites,
    required this.onPick,
    this.recent = const [],
  });

  /// 星标商品（优先）
  final List<Product> favorites;

  /// 最近常卖（无星标时顶上）
  final List<Product> recent;

  final ValueChanged<Product> onPick;

  @override
  Widget build(BuildContext context) {
    final starred = favorites.isNotEmpty;
    final list = starred ? favorites : recent;

    // 什么都没得显示时给一句能照做的指引（原来这行占了一整块 56dp 高）
    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.orangeSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Text(
          '多记几笔账，常卖的商品会自动出现在这里，点一下就记一笔',
          style: TextStyle(
              fontSize: AppTheme.fontCaption, color: AppTheme.textPrimary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Row(
            children: [
              Icon(starred ? Icons.star : Icons.trending_up,
                  size: 16, color: AppTheme.chartPeak),
              const SizedBox(width: 4),
              Text(
                starred ? '常用商品 · 点一下快速记账' : '最近常卖 · 点一下快速记账',
                style: TextStyle(
                    fontSize: AppTheme.fontCaption,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) =>
                _FavoriteChip(product: list[i], onTap: () => onPick(list[i])),
          ),
        ),
      ],
    );
  }
}

class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 尺寸收小过一轮：原来 108×48、内边距 12/6、圆角用的卡片规格（14）。
    // 一条快捷栏连标题要吃掉约 78dp 高度，在 640dp 高的机器上把明细区压得很紧。
    // 现在 88×40、内边距 10/4、圆角换成 radiusSmall(10)（小控件本来就该用这一档）：
    // 高度 −23%、宽度 −19%，一屏能多放下大半个 chip。
    //
    // 代价：触控区随之变成 40dp，低于项目「≥48dp」的约定。这是「更紧凑」与
    // 「更好点」的取舍 —— 觉得难点就把 minHeight 调回 44 或 48。
    final radius = BorderRadius.circular(AppTheme.radiusSmall);
    return Material(
      color: AppTheme.cardBackground,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 88, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTheme.fontSmall,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
              Text(
                '¥${fmtPrice(product.retailPrice)}',
                style: TextStyle(
                    fontSize: AppTheme.fontSmall,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.priceRed),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
