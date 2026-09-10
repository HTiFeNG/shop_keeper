import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_tile.dart';
import '../widgets/scan_page.dart';
import 'product_edit_page.dart';

/// 查找商品页（Tab 3）
///
/// - 顶部关键词搜索：按商品名或条码，实时显示「共找到 N 个」与结果列表；
/// - 搜索历史（最多 10 条，点击可重搜，支持一键清空）；
/// - 大按钮「扫一扫查商品」（仅 Android / iOS 显示，Web 隐藏）；
/// - 结果项支持「记一笔」快捷按钮。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final store = StoreService.instance;
  final _ctrl = TextEditingController();
  String _query = '';

  bool get _canScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Product> _results() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return store.products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.barcode.toLowerCase().contains(q))
        .toList();
  }

  void _submit(String q) {
    setState(() => _query = q);
    if (q.trim().isNotEmpty) store.addSearchHistory(q);
    FocusScope.of(context).unfocus();
  }

  void _research(String q) {
    _ctrl.text = q;
    _submit(q);
  }

  void _openEdit([Product? product, String? presetBarcode]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ProductEditPage(product: product, presetBarcode: presetBarcode),
    ));
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final results = _results();
            final searching = _query.trim().isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('查找商品', style: AppTheme.pageTitle),
                ),
                _searchField(),
                Expanded(
                  child: searching ? _resultsView(results) : _idleView(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: TextField(
          controller: _ctrl,
          onSubmitted: _submit,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '输入商品名或条码搜索',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      );

  /// 搜索结果视图
  Widget _resultsView(List<Product> results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            '共找到 ${results.length} 个',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text('没有找到相关商品', style: AppTheme.caption),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: results.length,
                  itemBuilder: (context, i) => ProductTile(
                    product: results[i],
                    onTap: () => _openEdit(results[i]),
                    onDelete: () => store.deleteProduct(results[i].id),
                    onQuickSale: () => store.requestPrefill(results[i].id),
                  ),
                ),
        ),
      ],
    );
  }

  /// 空闲视图：搜索历史 + 扫码大按钮（仅手机端）
  Widget _idleView() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_canScan)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: InkWell(
              onTap: _startScan,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: Container(
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFB8C00), Color(0xFFEF6C00)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.qr_code_scanner,
                          color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('扫一扫查商品',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('扫码自动识别条码，快速定位商品',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        // ---- 搜索历史 ----
        if (store.searchHistory.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Text('搜索历史',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => store.clearSearchHistory(),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('清空', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: AppTheme.cardDecoration,
            child: Column(
              children: [
                for (var i = 0; i < store.searchHistory.length; i++)
                  InkWell(
                    onTap: () => _research(store.searchHistory[i]),
                    child: Column(
                      children: [
                        if (i > 0)
                          const Divider(
                              height: 1,
                              indent: 52,
                              color: AppTheme.divider),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.history,
                                  size: 18, color: AppTheme.textSecondary),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  store.searchHistory[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const Icon(Icons.north_west,
                                  size: 16, color: AppTheme.textSecondary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ] else if (!_canScan)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text('输入商品名或条码开始搜索', style: AppTheme.caption),
            ),
          ),
      ],
    );
  }
}
