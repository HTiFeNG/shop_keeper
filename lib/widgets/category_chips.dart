import 'package:flutter/material.dart';

import '../services/store_service.dart';
import '../theme/app_theme.dart';
import 'category_manager_sheet.dart';

/// 手机端顶部分类横滑 Chips（替代左侧栏）。
///
/// - 顶部固定「全部」+ 自定义分类 +「未分类」（存在时）+「＋ 分类」新建入口；
/// - 右侧「管理」打开分类管理面板：拖拽排序 + 改名 + 删除（见
///   [showCategoryManager]）。原先的「上移 / 下移」一次只挪一格，已废弃。
class CategoryChips extends StatelessWidget {
  const CategoryChips({
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
  final int uncategorizedCount;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  /// 重命名分类；返回 false 表示重名（面板会提示并放弃本次改名）
  final bool Function(String oldName, String newName) onRename;
  final ValueChanged<String> onDelete;

  /// 拖拽排序后一次性提交新的分类顺序
  final void Function(List<String> ordered) onReorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 48dp：Chip 自身被外部高度压到 36dp 时，点起来很费劲
      height: 48,
      child: Row(
        children: [
          // 分类本身的横向滚动区
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 12),
              children: [
                _chip(context, kCategoryAll),
                for (final c in categories) _chip(context, c),
                if (showUncategorized)
                  _chip(context, kCategoryNone, count: uncategorizedCount),
              ],
            ),
          ),
          // 「＋ 分类」「管理」**固定在右侧**，不跟着分类列表滚。
          //
          // 原来这两个入口排在滚动区末尾，分类一多就被推到屏幕外 ——
          // 在 360dp 屏上「管理」的中心点落在 x=375.9，用户根本点不到。
          // 这个坑是组件测试里 hit test 直接失败才暴露出来的：测试点它，
          // 提示「该位置在渲染树边界之外」。
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: _actionChip(Icons.add, '分类', onAdd),
          ),
          if (categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 12),
              child: _actionChip(
                  Icons.tune, '管理', () => openCategoryManager(context)),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// 右侧固定区的动作 chip（＋分类 / 管理）
  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppTheme.primary),
      label: Text(label,
          style: const TextStyle(
              fontSize: AppTheme.fontCaption, color: AppTheme.primaryText)),
      backgroundColor: Colors.white,
      shape: StadiumBorder(
          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4))),
      onPressed: onTap,
    );
  }

  void openCategoryManager(BuildContext context) => showCategoryManager(
        context,
        categories: categories,
        onReorder: onReorder,
        onRename: onRename,
        onDelete: onDelete,
      );

  Widget _chip(BuildContext context, String name, {int? count}) {
    final sel = name == selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ChoiceChip(
          label: Text(
            count != null && count > 0 ? '$name（$count）' : name,
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
              // 选中态改为「浅橙底 + 深橙字」：原来白字压主色只有 3.08:1
              color: sel ? AppTheme.primaryText : AppTheme.textPrimary,
            ),
          ),
          selected: sel,
          selectedColor: AppTheme.orangeSurface,
          backgroundColor: Colors.white,
          showCheckmark: sel,
          onSelected: (_) => onSelect(name),
        ),
    );
  }
}
