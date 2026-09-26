import 'package:flutter/material.dart';

import '../services/store_constants.dart';
import '../theme/app_theme.dart';

/// 分类选择底部面板。
///
/// **为什么要有它**：以前给一个商品换分类要走四步 ——「点批量 → 勾选商品 →
/// 点底部"移动分类" → 弹窗里挑分类」。可绝大多数时候，店主只是想给**一个**
/// 商品挪个位置（新进的货归类、之前分错了）。现在商品行上的分类标签本身就是
/// 可点的，点完直接弹出这个面板，**两次点击结束**。
///
/// 返回：选中的分类名；用户取消返回 null。
/// 点「新建分类」时会把新建出来的名字**直接作为结果返回**，省掉
/// 「建完还要再选一次」的多余动作。
Future<String?> showCategoryPicker(
  BuildContext context, {
  required List<String> categories,
  String? current,
  bool allowNone = true,
  String title = '移动到分类',
  Future<String?> Function()? onCreate,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _CategoryPickerSheet(
      categories: categories,
      current: current,
      allowNone: allowNone,
      title: title,
      onCreate: onCreate,
    ),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.current,
    required this.allowNone,
    required this.title,
    required this.onCreate,
  });

  final List<String> categories;
  final String? current;
  final bool allowNone;
  final String title;
  final Future<String?> Function()? onCreate;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  /// 正在等待「新建分类」对话框返回：期间禁掉重复点击
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    // 分类多的时候面板最多占半屏，剩下的交给列表滚动
    final maxListHeight = MediaQuery.of(context).size.height * 0.5;
    final hasOptions = widget.allowNone || widget.categories.isNotEmpty;

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
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: AppTheme.sectionTitle),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (!hasOptions)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Text('还没有分类，先新建一个吧', style: AppTheme.caption),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListHeight),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    if (widget.allowNone)
                      _option(kCategoryNone, Icons.remove_circle_outline),
                    for (final c in widget.categories)
                      _option(c, Icons.folder_outlined),
                  ],
                ),
              ),
            ),
          const Divider(height: 1, color: AppTheme.divider),
          _createRow(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 单个可选项。
  ///
  /// 底色交给 `Material` 而不是 `Container`：后者会盖住 InkWell 的水波纹
  /// （Flutter 会为此抛断言，选中项恰好是最常点的那一行）。
  Widget _option(String name, IconData icon) {
    final sel = name == widget.current;
    return Material(
      color: sel ? AppTheme.orangeSurface : Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => Navigator.pop(context, name),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: sel ? AppTheme.primary : AppTheme.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTheme.fontBody,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    color: sel ? AppTheme.primaryText : AppTheme.textPrimary,
                  ),
                ),
              ),
              if (sel)
                const Icon(Icons.check_circle, size: 20, color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部「新建分类」：建完直接把新名字作为选择结果返回
  Widget _createRow() {
    final canCreate = widget.onCreate != null && !_busy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canCreate
            ? () async {
                setState(() => _busy = true);
                final created = await widget.onCreate!();
                if (!mounted) return;
                setState(() => _busy = false);
                if (created != null && created.isNotEmpty && mounted) {
                  Navigator.pop(context, created);
                }
              }
            : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.add, size: 20, color: AppTheme.primary),
              const SizedBox(width: 12),
              Text(
                '新建分类',
                style: TextStyle(
                  fontSize: AppTheme.fontBody,
                  fontWeight: FontWeight.w600,
                  color: widget.onCreate == null
                      ? AppTheme.textSecondary
                      : AppTheme.primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
