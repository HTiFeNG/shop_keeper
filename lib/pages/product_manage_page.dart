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
/// 4. 商品列表（库存预警 + 星标 + 记一笔）
/// 5. 底部操作条（总数 / 导出 / 导入 / 扫码 —— 扫码仅手机端显示）
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
    } catch (_) {
      // 导出失败静默处理
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
      // 跳过表头行：与 Product.csvHeader 首列「编号」对齐判断，不依赖列数
      if (rows.isNotEmpty &&
          rows.first.isNotEmpty &&
          rows.first[0] == '编号') {
        rows.removeAt(0);
      }
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
      _toast('导入完成：覆盖 ${r.overwritten} 条，新增 ${r.added} 条，跳过 ${r.skipped} 条');
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  /// 备份全部数据（商品 + 分类 + 销售记录）
  Future<void> _backup() async {
    try {
      await ExportService.exportBackup(store.exportBackup());
    } catch (e) {
      _toast('备份失败：$e');
    }
  }

  /// 从备份文件恢复（全量替换，覆盖前二次确认）
  Future<void> _restore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;
      final text = utf8.decode(bytes, allowMalformed: true);

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复数据'),
          content: const Text('恢复将【完全覆盖】当前所有商品、分类和销售记录，且不可撤销。确定从备份文件恢复吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.priceRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖恢复'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      final success = store.importBackup(text);
      _toast(success ? '恢复成功，数据已还原' : '备份文件格式不对，恢复失败');
    } catch (e) {
      _toast('恢复失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
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
            const Text('商品管理', style: AppTheme.pageTitle),
            const Spacer(),
            if (_batchMode)
              TextButton(
                onPressed: _exitBatchMode,
                child: const Text('取消', style: TextStyle(fontSize: 14)),
              )
            else ...[
              PopupMenuButton<String>(
                tooltip: '数据备份',
                icon: const Icon(Icons.backup_outlined,
                    color: AppTheme.textSecondary),
                onSelected: (v) {
                  if (v == 'backup') _backup();
                  if (v == 'restore') _restore();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.upload_outlined),
                      title: Text('备份全部数据'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restore',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.download_outlined),
                      title: Text('从备份恢复'),
                    ),
                  ),
                ],
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: _enterBatchMode,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.checklist, size: 16),
                    SizedBox(width: 4),
                    Text('批量', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 36),
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
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text('暂无商品', style: AppTheme.caption),
            const SizedBox(height: 4),
            const Text('点右上角「新增」录入第一件商品',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
                GestureDetector(
                  onTap: () => _toggleSelectAll(products),
                  child: Row(
                    children: [
                      Icon(
                        products.every((p) => _selectedIds.contains(p.id))
                            ? Icons.deselect
                            : Icons.select_all,
                        size: 16,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        products.every((p) => _selectedIds.contains(p.id))
                            ? '取消全选'
                            : '全选',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.primary),
                      ),
                    ],
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
        color: AppTheme.primary,
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
                            fontSize: 13),
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
                            fontSize: 13),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: disabled ? Colors.white38 : Colors.white, size: 20),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: disabled ? Colors.white38 : Colors.white,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
