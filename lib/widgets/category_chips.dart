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
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(context, kCategoryAll),
          for (final c in categories) _chip(context, c),
          if (showUncategorized)
            _chip(context, kCategoryNone, count: uncategorizedCount),
          // 添加分类
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 16, color: AppTheme.primary),
              label: const Text('分类',
                  style: TextStyle(
                      fontSize: AppTheme.fontCaption,
                      color: AppTheme.primaryText)),
              backgroundColor: Colors.white,
              shape: StadiumBorder(
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4))),
              onPressed: onAdd,
            ),
          ),
          // 管理入口：改名 / 排序 / 删除原先只能长按触发，而长按既没有视觉
          // 提示、又会和横滑手势打架，对中老年用户等于不存在。
          //
          // 注意它现在**始终显示**（原先只在选中自定义分类时才出现）——
          // 否则选中「全部」时想整理分类，用户根本找不到入口。
          if (categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ActionChip(
                avatar:
                    const Icon(Icons.tune, size: 16, color: AppTheme.primary),
                label: const Text('管理',
                    style: TextStyle(
                        fontSize: AppTheme.fontCaption,
                        color: AppTheme.primaryText)),
                backgroundColor: Colors.white,
                shape: StadiumBorder(
                    side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.4))),
                onPressed: () => openCategoryManager(context),
              ),
            ),
        ],
      ),
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
