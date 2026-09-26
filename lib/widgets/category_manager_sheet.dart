import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'category_name_dialog.dart';

/// 分类管理面板：**拖拽一次到位**地调整分类顺序，并就地改名 / 删除。
///
/// 旧的「上移 / 下移」一次只能挪一格 —— 想把第 5 个分类挪到第 1 位要点 4 次，
/// 还得每次重新打开菜单。这里改成拖动：按住右侧手柄拖到目标位置松手即可，
/// 一次操作跨越任意距离。
///
/// 为什么用**显式拖拽手柄**而不是长按整行：目标用户里中老年居多，长按手势
/// 没有视觉提示、还会和列表滚动打架，等于没这个功能。
///
/// 面板本身维护一份本地顺序（[_order]）并在每次操作后回调外部；
/// 外部的 store 更新会让底层页面重建，但不会影响本面板已经排好的顺序。
Future<void> showCategoryManager(
  BuildContext context, {
  required List<String> categories,
  required void Function(List<String> ordered) onReorder,
  required bool Function(String oldName, String newName) onRename,
  required void Function(String name) onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _CategoryManagerSheet(
      categories: categories,
      onReorder: onReorder,
      onRename: onRename,
      onDelete: onDelete,
    ),
  );
}

class _CategoryManagerSheet extends StatefulWidget {
  const _CategoryManagerSheet({
    required this.categories,
    required this.onReorder,
    required this.onRename,
    required this.onDelete,
  });

  final List<String> categories;
  final void Function(List<String> ordered) onReorder;
  final bool Function(String oldName, String newName) onRename;
  final void Function(String name) onDelete;

  @override
  State<_CategoryManagerSheet> createState() => _CategoryManagerSheetState();
}

class _CategoryManagerSheetState extends State<_CategoryManagerSheet> {
  late List<String> _order = [...widget.categories];

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      // ReorderableListView 给的 newIndex 是「移除前」的插入位，往后拖要减 1
      if (newIndex > oldIndex) newIndex -= 1;
      _order.insert(newIndex, _order.removeAt(oldIndex));
    });
    widget.onReorder(List.of(_order));
  }

  Future<void> _rename(int index) async {
    final old = _order[index];
    final newName = await showCategoryNameDialog(
      context,
      title: '编辑分类',
      initial: old,
      oldName: old,
      existing: _order,
    );
    if (!mounted) return;
    if (newName == null || newName == old) return;
    if (!widget.onRename(old, newName)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('该分类已存在')));
      return;
    }
    setState(() => _order[index] = newName);
  }

  Future<void> _delete(int index) async {
    final name = _order[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除分类「$name」'),
        content: const Text(
            '删除后：该分类下无小类的商品将归入「未分类」，带小类的商品仅保留小类名。确定删除吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.priceRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    setState(() => _order.removeAt(index));
    widget.onDelete(name);
  }

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.of(context).size.height * 0.55;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('管理分类', style: AppTheme.sectionTitle),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Icon(Icons.drag_indicator,
                    size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _order.isEmpty
                        ? '还没有分类'
                        : '按住右侧 ☰ 拖动，松手即完成排序',
                    style: AppTheme.caption,
                  ),
                ),
              ],
            ),
          ),
          if (_order.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text('点分类栏上的「＋ 分类」新建一个',
                  style: TextStyle(
                      fontSize: AppTheme.fontCaption,
                      color: AppTheme.textSecondary)),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListHeight),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  // 关掉默认的「长按整行拖动」，改用右侧显式手柄
                  buildDefaultDragHandles: false,
                  itemCount: _order.length,
                  onReorder: _onReorder,
                  itemBuilder: (ctx, i) => _row(i),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(int i) {
    final name = _order[i];
    return Material(
      // key 用分类名：ReorderableListView 靠它追踪是哪一个被拖走了
      key: ValueKey('cat-$name'),
      color: Colors.white,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.only(left: 16, right: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.divider, width: 1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined,
                size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: AppTheme.fontBody),
              ),
            ),
            IconButton(
              tooltip: '重命名',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _rename(i),
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppTheme.priceRed),
              onPressed: () => _delete(i),
            ),
            // 拖拽手柄：必须包在 ReorderableDragStartListener 里，
            // 且把 iOS 的延迟拖拽也算上（默认长按才响应，这里改成按下即抓）
            ReorderableDragStartListener(
              index: i,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: const Icon(Icons.drag_handle,
                    size: 22, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
