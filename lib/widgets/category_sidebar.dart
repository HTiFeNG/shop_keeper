import 'package:flutter/material.dart';

import '../services/store_service.dart';
import '../theme/app_theme.dart';
import 'category_manager_sheet.dart';

/// 左侧分类栏（宽屏布局保留；手机端改用 CategoryChips）。
///
/// - 顶部固定「全部」（不可编辑 / 删除）
/// - 底部固定「未分类」（仅当存在未分类商品时显示）
/// - 中间为自定义分类；底部的「管理分类」打开拖拽排序面板
///   （见 [showCategoryManager]，替代原先一次挪一格的「上移 / 下移」）
class CategorySidebar extends StatelessWidget {
  const CategorySidebar({
    super.key,
    required this.categories,
    required this.selected,
    required this.showUncategorized,
    required this.uncategorizedCount,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onReorder,
  });

  final List<String> categories;
  final String selected;
  final bool showUncategorized;
  final int uncategorizedCount; // 未分类商品数量
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  /// 重命名分类；返回 false 表示重名（面板会提示并放弃本次改名）
  final bool Function(String oldName, String newName) onRename;
  final ValueChanged<String> onDelete;

  /// 拖拽排序后一次性提交新的分类顺序
  final void Function(List<String> ordered) onReorder;

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
                _item(context, kCategoryAll),
                for (final c in categories) _item(context, c),
                if (showUncategorized)
                  _item(context, kCategoryNone, count: uncategorizedCount),
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
          // 管理入口始终显示（原先只在选中自定义分类时才出现，导致
          // 看「全部」时想整理分类根本找不到入口）
          if (categories.isNotEmpty)
            InkWell(
              onTap: () => showCategoryManager(
                context,
                categories: categories,
                onReorder: onReorder,
                onRename: onRename,
                onDelete: onDelete,
              ),
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

  Widget _item(BuildContext context, String name, {int? count}) {
    final isSel = name == selected;
    final isUncat = name == kCategoryNone;
    return InkWell(
      onTap: () => onSelect(name),
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
}
