import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/export_service.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/csv_codec.dart';
import '../widgets/category_chips.dart';
import '../widgets/category_sidebar.dart';
import '../widgets/product_tile.dart';
import '../widgets/scan_page.dart';
import 'product_edit_page.dart';

/// 商品管理页（Tab 2）
///
/// 布局自上而下：
/// 1. 标题栏（备份恢复菜单 + 批量 + 新增）
/// 2. 实时搜索框（按商品名或条码）
/// 3. 分类：宽屏(>720) 左侧栏 / 手机端顶部横滑 Chips
/// 4. 商品列表（星标 + 记一笔）
/// 5. 底部操作条（总数 / 导出 / 导入 / 扫码 —— 扫码仅手机端显示）
///
/// 注：库存已随「库存功能」移除（3.0.0），本页不再显示/编辑库存。
class ProductManagePage extends StatefulWidget {
  const ProductManagePage({super.key});

  @override
  State<ProductManagePage> createState() => _ProductManagePageState();
}

class _ProductManagePageState extends State<ProductManagePage> {
  final store = StoreService.instance;
  final _searchCtrl = TextEditingController();

  String _selectedCategory = kCategoryAll;
  String _query = '';
  bool _batchMode = false;
  final Set<String> _selectedIds = {};

  /// 扫码仅 Android / iOS 显示（Web 隐藏）
  bool get _canScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ==================== 筛选逻辑 ====================

  List<Product> _categoryProducts() {
    if (_selectedCategory == kCategoryAll) return store.products;
    if (_selectedCategory == kCategoryNone) {
      return store.products
          .where((p) => p.category.isEmpty || p.category == kCategoryNone)
          .toList();
    }
    return store.products
        .where((p) =>
            p.category == _selectedCategory ||
            p.category.startsWith('$_selectedCategory/'))
        .toList();
  }

  List<Product> _filteredProducts() {
    var list = _categoryProducts();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.barcode.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  // ==================== 页面跳转 ====================

  void _openEdit([Product? product, String? presetBarcode]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ProductEditPage(product: product, presetBarcode: presetBarcode),
    ));
  }

  /// 扫码后处理：库里有此条码 → 编辑；没有 → 新建并自动填入条码
  Future<void> _startScan() async {
    final code = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code is String && code.isNotEmpty && mounted) {
      final existing = store.findByBarcode(code);
      if (existing != null) {
        _openEdit(existing);
      } else {
        _openEdit(null, code);
      }
    }
  }

  // ==================== 分类管理 ====================

  Future<void> _showAddCategoryDialog() async {
    await _showCategoryDialog(title: '添加分类', initial: '');
  }

  Future<void> _showEditCategoryDialog(String oldName) async {
    await _showCategoryDialog(
        title: '编辑分类', initial: oldName, oldName: oldName);
  }

  Future<void> _showCategoryDialog({
    required String title,
    required String initial,
    String? oldName,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '请输入分类名称',
                errorText: error,
              ),
              onChanged: (_) {
                if (error != null) setStateDialog(() => error = null);
              },
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final name = ctrl.text.trim();
                  if (name.isEmpty) {
                    setStateDialog(() => error = '请输入分类名称');
                    return;
                  }
                  final dup = oldName == null
                      ? !store.addCategory(name)
                      : !store.renameCategory(oldName, name);
                  if (dup) {
                    setStateDialog(() => error = '该分类已存在');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true) {
      final newName = ctrl.text.trim();
      if (oldName != null &&
          _selectedCategory == oldName &&
          newName != oldName) {
        setState(() => _selectedCategory = newName);
      } else {
        _syncSelectedCategory();
      }
    }
  }

  Future<void> _confirmDeleteCategory(String name) async {
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
    if (ok == true) {
      store.deleteCategory(name);
      _syncSelectedCategory();
    }
  }

  void _syncSelectedCategory() {
    if (_selectedCategory != kCategoryAll &&
        _selectedCategory != kCategoryNone) {
      if (!store.categories.contains(_selectedCategory)) {
        setState(() => _selectedCategory = kCategoryAll);
      }
    }
  }

  // ==================== 导出 / 导入 / 备份 ====================

  /// 导出商品 CSV（分端：Android 分享文件 / Web 浏览器下载）
  Future<void> _export() async {
    try {
      await ExportService.exportProducts(store.exportCsv());
      _toast('已导出商品表');
    } catch (_) {
      // 原来这里是 catch (_) { // 导出失败静默处理 } —— 用户点了导出、
      // 什么都没发生，还以为文件已经存好了。
      _toastErr('导出没成功，请检查手机存储空间后重试', retry: _export);
    }
  }

  /// 导入商品 CSV
  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;

      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      final rows = const CsvCodec().decode(text);
      // 必须认得出表头：选错文件（照片、聊天记录导出）时那一行会被当成
      // 「名称」直接变成一个垃圾商品，旧实现不会报任何错。
      if (rows.isEmpty ||
          rows.first.isEmpty ||
          rows.first[0].trim() != '编号') {
        _toastErr('这不是商品数据文件（缺少「编号」表头），请重新选择');
        return;
      }
      rows.removeAt(0);
      if (rows.isEmpty) {
        _toast('文件中没有可导入的数据');
        return;
      }
      final incoming = rows.map(Product.fromCsvRow).toList();

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认导入'),
          content: Text('共解析到 ${incoming.length} 条商品数据。\n\n'
              '导入规则：\n'
              '· 有条码且已存在 → 覆盖原商品\n'
              '· 有条码但不存在 → 追加为新商品\n'
              '· 无条码 → 直接追加为新商品\n'
              '· 名称与条码都为空 → 跳过'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('导入')),
          ],
        ),
      );
      if (ok != true) return;

      final r = store.importProducts(incoming);
      // 这条信息要读三个数字，2 秒根本看不完
      _toast('导入完成：覆盖 ${r.overwritten} 条，新增 ${r.added} 条，跳过 ${r.skipped} 条',
          seconds: 6);
    } catch (_) {
      _toastErr('文件读不出来，请确认选的是商品 CSV 文件', retry: _import);
    }
  }

  /// 备份全部数据（商品 + 分类 + 销售记录）
  Future<void> _backup() async {
    try {
      await ExportService.exportBackup(store.exportBackup());
      store.markBackedUp();
      _toast('备份已导出，请把这个文件保存好');
    } catch (_) {
      _toastErr('备份没成功，请检查手机存储空间后重试', retry: _backup);
    }
  }

  /// 从备份文件恢复
  ///
  /// 流程：选文件 → **先预览内容**（商品/天数/明细条数/导出时间）→ 二次确认
  /// → 恢复 → 告知结果，并支持一键撤销回恢复前的状态。
  Future<void> _restore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;
      final text = utf8.decode(bytes, allowMalformed: true);

      final preview = store.previewBackup(text);
      if (preview == null) {
        _toastErr('这不是店铺管家的备份文件，请重新选择');
        return;
      }
      if (!mounted) return;

      final when = preview.exportedAt == null
          ? '未记录'
          : preview.exportedAt!.replaceFirst('T', ' ').split('.').first;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认恢复'),
          content: Text('这份备份包含：\n'
              '· ${preview.productCount} 个商品\n'
              '· ${preview.dayCount} 天的营业额（共 ${preview.itemCount} 条明细）\n'
              '· 导出时间：$when\n\n'
              '恢复会用上面的内容【完全覆盖】现在的数据。\n'
              '不用担心选错：恢复前会自动存一份当前数据，之后可以一键撤销。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.priceRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认恢复'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      final r = await store.importBackup(text);
      if (!mounted) return;
      if (!r.ok) {
        _toastErr('恢复失败：${r.reason}');
        return;
      }
      final skipped = r.skipped > 0 ? '，跳过 ${r.skipped} 条坏数据' : '';
      _toastErr('恢复完成：${r.productCount} 个商品、${r.dayCount} 天记录$skipped'
          '（如需反悔可点「撤销恢复」）');
    } catch (_) {
      _toastErr('文件读不出来，请确认选的是备份文件（.json）');
    }
  }

  /// 撤销上一次恢复
  Future<void> _undoRestore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销恢复'),
        content: const Text('将数据还原成上一次恢复之前的样子。确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('撤销恢复')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await store.undoLastRestore();
    if (!mounted) return;
    if (done) {
      _toast('已恢复到上一次恢复之前的状态');
    } else {
      _toastErr('恢复之前没有可用的快照，无法撤销');
    }
  }

  void _toast(String msg, {int seconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: Duration(seconds: seconds)));
  }

  /// 失败提示：一句人话 + 更久停留 + 可重试（原来是把 $e 裸异常显示 2 秒）
  void _toastErr(String msg, {Future<void> Function()? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 6),
        action: retry == null
            ? null
            : SnackBarAction(label: '重试', onPressed: () => retry()),
      ));
  }

  // ==================== 批量操作 ====================

  void _enterBatchMode() {
    setState(() {
      _batchMode = true;
      _selectedIds.clear();
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll(List<Product> visible) {
    final allSelected = visible.every((p) => _selectedIds.contains(p.id));
    setState(() {
      if (allSelected) {
        for (final p in visible) {
          _selectedIds.remove(p.id);
        }
      } else {
        for (final p in visible) {
          _selectedIds.add(p.id);
        }
      }
    });
  }

  Future<void> _batchMoveCategory() async {
    if (_selectedIds.isEmpty) {
      _toast('请先选择商品');
      return;
    }

    final options = <String>[kCategoryNone, ...store.categories];

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移动到分类'),
        children: [
          for (final cat in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, cat),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined,
                      size: 20, color: AppTheme.textSecondary),
                  const SizedBox(width: 12),
                  Text(cat, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await _showAddCategoryDialog();
              if (mounted) _batchMoveCategory();
            },
            child: const Row(
              children: [
                Icon(Icons.add, size: 20, color: AppTheme.primary),
                SizedBox(width: 12),
                Text('新建分类',
                    style: TextStyle(fontSize: 15, color: AppTheme.primary)),
              ],
            ),
          ),
        ],
      ),
    );

    if (result == null) return;
    final target = result;
    store.batchSetCategory(_selectedIds.toList(), target);
    _toast('已将 ${_selectedIds.length} 件商品移动到「$target」');
    _exitBatchMode();
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) {
      _toast('请先选择商品');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content:
            Text('确定删除选中的 ${_selectedIds.length} 件商品吗？此操作不可恢复。'),
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
    if (ok != true) return;
    final count = _selectedIds.length;
    store.batchDelete(_selectedIds.toList());
    _toast('已删除 $count 件商品');
    _exitBatchMode();
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > kWideBreakpoint;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final filtered = _filteredProducts();
            final uncatCount = store.products
                .where(
                    (p) => p.category.isEmpty || p.category == kCategoryNone)
                .length;
            return Column(
              children: [
                _header(),
                _searchBar(),
                if (!wide)
                  CategoryChips(
                    categories: store.categories,
                    selected: _selectedCategory,
                    showUncategorized: uncatCount > 0,
                    uncategorizedCount: uncatCount,
                    onSelect: (c) => setState(() => _selectedCategory = c),
                    onAdd: _showAddCategoryDialog,
                    onEdit: _showEditCategoryDialog,
                    onDelete: _confirmDeleteCategory,
                    onMoveUp: (c) => store.moveCategory(c, -1),
                    onMoveDown: (c) => store.moveCategory(c, 1),
                  ),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            CategorySidebar(
                              categories: store.categories,
                              selected: _selectedCategory,
                              showUncategorized: uncatCount > 0,
                              uncategorizedCount: uncatCount,
                              onSelect: (c) =>
                                  setState(() => _selectedCategory = c),
                              onAdd: _showAddCategoryDialog,
                              onEdit: _showEditCategoryDialog,
                              onDelete: _confirmDeleteCategory,
                              onMoveUp: (c) => store.moveCategory(c, -1),
                              onMoveDown: (c) => store.moveCategory(c, 1),
                            ),
                            Expanded(child: _productList(filtered)),
                          ],
                        )
                      : _productList(filtered),
                ),
                _bottomBar(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 标题栏：批量 / 新增 / 备份恢复菜单
  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Row(
          children: [
            // Flexible + 省略号：大字号（Android「大字体」）下标题不再把整行挤爆
            const Flexible(
              child: Text('商品管理',
                  style: AppTheme.pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const Spacer(),
            if (_batchMode)
              TextButton(
                onPressed: _exitBatchMode,
                child: const Text('取消', style: TextStyle(fontSize: 14)),
              )
            else ...[
              PopupMenuButton<String>(
                tooltip: '数据备份与恢复',
                icon: const Icon(Icons.backup_outlined,
                    color: AppTheme.textSecondary),
                onSelected: (v) {
                  if (v == 'backup') _backup();
                  if (v == 'restore') _restore();
                  if (v == 'undoRestore') _undoRestore();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.upload_outlined),
                      title: Text('备份全部数据'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'restore',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.download_outlined),
                      title: Text('从备份恢复'),
                    ),
                  ),
                  if (store.hasRestoreSnapshot)
                    const PopupMenuItem(
                      value: 'undoRestore',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.undo),
                        title: Text('撤销上次恢复'),
                      ),
                    ),
                ],
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryText,
                  side: const BorderSide(color: AppTheme.primary),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  // 48dp：原为 36，且与「新增」只隔 8dp，很容易点错
                  minimumSize: const Size(0, 48),
                ),
                onPressed: _enterBatchMode,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.checklist, size: 16),
                    SizedBox(width: 4),
                    Text('批量',
                        style: TextStyle(fontSize: AppTheme.fontCaption)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 48),
                ),
                onPressed: () => _openEdit(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增', style: TextStyle(fontSize: 14)),
              ),
            ],
          ],
        ),
      );

  /// 实时搜索框（按商品名或条码）
  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: '搜索商品名或条码',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      );

  /// 商品列表
  Widget _productList(List<Product> products) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.45)),
            const SizedBox(height: 8),
            const Text('暂无商品', style: AppTheme.caption),
            const SizedBox(height: 4),
            const Text('点右上角「新增」录入第一件商品',
                style: TextStyle(
                    fontSize: AppTheme.fontCaption,
                    color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_batchMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: Row(
              children: [
                Text(
                  '已选 ${_selectedIds.length} 件',
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // 原来是个裸 GestureDetector + 13px 文字，实际可点区只有约 18dp
                InkWell(
                  onTap: () => _toggleSelectAll(products),
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Icon(
                          products.every((p) => _selectedIds.contains(p.id))
                              ? Icons.deselect
                              : Icons.select_all,
                          size: 20,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          products.every((p) => _selectedIds.contains(p.id))
                              ? '取消全选'
                              : '全选',
                          style: const TextStyle(
                              fontSize: 14, color: AppTheme.primaryText),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            itemCount: products.length,
            itemBuilder: (context, i) => ProductTile(
              product: products[i],
              onTap: () => _openEdit(products[i]),
              onDelete: () => store.deleteProduct(products[i].id),
              onQuickSale: () => store.requestPrefill(products[i].id),
              // 直接在列表里加星：不必进编辑页，否则「一键记账」很难被发现
              onToggleFavorite: () => store.toggleFavorite(products[i].id),
              selected: _selectedIds.contains(products[i].id),
              onSelectToggle:
                  _batchMode ? () => _toggleSelect(products[i].id) : null,
            ),
          ),
        ),
      ],
    );
  }

  /// 底部操作条
  Widget _bottomBar() => Container(
        // 原来用 primary(#EF6C00) 打底配白字，只有 3.08:1；深橙后 5.6:1
        color: AppTheme.totalGradientEnd,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _batchMode
                ? Row(
                    children: [
                      Text(
                        '已选 ${_selectedIds.length} 件',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      const Spacer(),
                      _barBtn(Icons.drive_file_move_outline, '移动分类',
                          _selectedIds.isEmpty ? null : _batchMoveCategory),
                      _barBtn(Icons.delete_outline, '删除',
                          _selectedIds.isEmpty ? null : _batchDelete),
                    ],
                  )
                : Row(
                    children: [
                      Text(
                        '共 ${store.products.length} 件商品',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      const Spacer(),
                      _barBtn(Icons.ios_share, '导出', _export),
                      _barBtn(Icons.file_download, '导入', _import),
                      if (_canScan)
                        _barBtn(Icons.qr_code_scanner, '扫码', _startScan),
                    ],
                  ),
          ),
        ),
      );

  Widget _barBtn(IconData icon, String label, VoidCallback? onTap) {
    final disabled = onTap == null;
    // 约束到 ≥48dp：InkWell 本身不会扩大命中区，原来实际约 44dp，
    // 而「导出 / 导入 / 扫码」紧挨着，很容易点错（导入会覆盖数据）。
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: disabled ? Colors.white70 : Colors.white, size: 20),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: disabled ? Colors.white70 : Colors.white,
                    fontSize: AppTheme.fontCaption)),
          ],
        ),
      ),
    );
  }
}
