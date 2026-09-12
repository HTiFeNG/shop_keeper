import 'package:flutter/material.dart';

import '../services/store_service.dart';
import '../theme/app_theme.dart';

/// 左侧分类栏（宽屏布局保留；手机端改用 CategoryChips）。
///
/// - 顶部固定「全部」（不可编辑 / 删除）
/// - 底部固定「未分类」（仅当存在未分类商品时显示）
/// - 中间为自定义分类：长按弹出「上移 / 下移 / 编辑 / 删除」菜单
/// - 底部「+ 添加分类」入口
class CategorySidebar extends StatelessWidget {
  const CategorySidebar({
    super.key,
    required this.categories,
    required this.selected,
    required this.showUncategorized,
    required this.uncategorizedCount,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final List<String> categories;
  final String selected;
  final bool showUncategorized;
  final int uncategorizedCount; // 未分类商品数量
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onMoveUp;
  final ValueChanged<String> onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      color: AppTheme.orangeSurface,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _item(context, kCategoryAll, fixed: true),
                for (var i = 0; i < categories.length; i++)
                  _item(context, categories[i], index: i, total: categories.length),
                if (showUncategorized)
                  _item(context, kCategoryNone, fixed: true, count: uncategorizedCount),
              ],
            ),
          ),
          InkWell(
            onTap: onAdd,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18, color: AppTheme.primary),
                  SizedBox(height: 2),
                  Text('添加分类',
                      style: TextStyle(
                          fontSize: AppTheme.fontCaption,
                          color: AppTheme.primaryText)),
                ],
              ),
            ),
          ),
          // 可见的「管理分类」入口（长按对中老年用户基本等于不存在）
          if (selected != kCategoryAll && selected != kCategoryNone)
            InkWell(
              onTap: () => _showMenu(context, selected,
                  index: categories.indexOf(selected),
                  total: categories.length),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune, size: 18, color: AppTheme.primary),
                    SizedBox(height: 2),
                    Text('管理分类',
                        style: TextStyle(
                            fontSize: AppTheme.fontCaption,
                            color: AppTheme.primaryText)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, String name,
      {bool fixed = false, int? count, int index = 0, int total = 0}) {
    final isSel = name == selected;
    final isUncat = name == kCategoryNone;
    return InkWell(
      onTap: () => onSelect(name),
      onLongPress:
          fixed ? null : () => _showMenu(context, name, index: index, total: total),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          // 选中态换深橙：原来白字压 primary(#EF6C00) 只有 3.08:1
          color: isSel ? AppTheme.totalGradientEnd : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTheme.fontCaption,
                color: isSel
                    ? Colors.white
                    : (isUncat ? AppTheme.textSecondary : AppTheme.textPrimary),
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(height: 2),
              Text('$count',
                  style: TextStyle(
                      fontSize: AppTheme.fontCaption,
                      color: isSel ? Colors.white : AppTheme.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }

  /// 长按分类 → 上移 / 下移 / 编辑 / 删除菜单
  void _showMenu(BuildContext context, String name,
      {required int index, required int total}) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('分类：$name',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              enabled: index > 0,
              leading: const Icon(Icons.arrow_upward),
              title: const Text('上移'),
              onTap: () {
                Navigator.pop(ctx);
                onMoveUp(name);
              },
            ),
            ListTile(
              enabled: index < total - 1,
              leading: const Icon(Icons.arrow_downward),
              title: const Text('下移'),
              onTap: () {
                Navigator.pop(ctx);
                onMoveDown(name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑分类'),
              onTap: () {
                Navigator.pop(ctx);
                onEdit(name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.priceRed),
              title: const Text('删除分类',
                  style: TextStyle(color: AppTheme.priceRed)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete(name);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
