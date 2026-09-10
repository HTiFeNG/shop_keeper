import 'package:flutter/material.dart';

import '../services/store_service.dart';
import '../theme/app_theme.dart';

/// 手机端顶部分类横滑 Chips（替代左侧栏）。
///
/// - 顶部固定「全部」+ 自定义分类 +「未分类」（存在时）+「＋」添加入口；
/// - 长按自定义分类 → 上移 / 下移 / 编辑 / 删除菜单。
class CategoryChips extends StatelessWidget {
  const CategoryChips({
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
  final int uncategorizedCount;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onMoveUp;
  final ValueChanged<String> onMoveDown;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(context, kCategoryAll, fixed: true),
          for (var i = 0; i < categories.length; i++)
            _chip(context, categories[i], index: i, total: categories.length),
          if (showUncategorized)
            _chip(context, kCategoryNone, fixed: true, count: uncategorizedCount),
          // 添加分类
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 16, color: AppTheme.primary),
              label: const Text('分类',
                  style: TextStyle(fontSize: 13, color: AppTheme.primary)),
              backgroundColor: Colors.white,
              shape: StadiumBorder(
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4))),
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String name,
      {bool fixed = false, int? count, int index = 0, int total = 0}) {
    final sel = name == selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: GestureDetector(
        onLongPress: fixed
            ? null
            : () => _showMenu(context, name, index: index, total: total),
        child: ChoiceChip(
          label: Text(
            count != null && count > 0 ? '$name（$count）' : name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
              color: sel ? Colors.white : AppTheme.textPrimary,
            ),
          ),
          selected: sel,
          selectedColor: AppTheme.primary,
          backgroundColor: Colors.white,
          showCheckmark: false,
          onSelected: (_) => onSelect(name),
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
