import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 首页「常用商品」横向快捷条：星标商品点击即添加一行销售明细。
///
/// 无星标商品时显示引导文案（去商品页点亮星标）。
class FavoriteQuickBar extends StatelessWidget {
  const FavoriteQuickBar({
    super.key,
    required this.favorites,
    required this.onPick,
  });

  final List<Product> favorites;
  final ValueChanged<Product> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            children: [
              Icon(Icons.star, size: 16, color: AppTheme.warningYellow),
              SizedBox(width: 4),
              Text('常用商品 · 点一下快速记账',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ],
          ),
        ),
        SizedBox(
          height: 56,
          child: favorites.isEmpty
              ? Container(
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.orangeSurface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  ),
                  child: const Text(
                    '还没有常用商品 —— 到「商品」页给常卖的商品点亮 ★，这里就能一键记账',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: favorites.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = favorites[i];
                    return _FavoriteChip(product: p, onTap: () => onPick(p));
                  },
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
              Text(
                '¥${fmtPrice(product.retailPrice)}',
                style: const TextStyle(
                    fontSize: 12,
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
