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
        child: const Text(
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
                style: const TextStyle(
                    fontSize: AppTheme.fontCaption,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 108, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
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
                style: const TextStyle(
                    fontSize: AppTheme.fontCaption,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
              Text(
                '¥${fmtPrice(product.retailPrice)}',
                style: const TextStyle(
                    fontSize: AppTheme.fontCaption,
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
