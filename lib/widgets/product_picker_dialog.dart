import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/sale.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/search.dart';

/// 选品结果：选中的商品 + 这笔按什么价记。
///
/// 带上计价方式是为了让「点整行 = 零售价、点『批发』按钮 = 批发价」
/// 这两种意图在弹窗关闭时就确定下来，不必回到明细行再切一次。
class PickedProduct {
  const PickedProduct(this.product, this.mode);

  final Product product;
  final SalePriceMode mode;
}

/// 从商品库选品弹窗。
///
/// 分区：常用（星标）置顶 > 分类浏览 > 搜索过滤。
/// 选中后 pop 返回 [PickedProduct]（调用方据此带出名称 + 单价）。
Future<PickedProduct?> showProductPickerDialog(BuildContext context) {
  return showModalBottomSheet<PickedProduct>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProductPickerSheet(),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final store = StoreService.instance;
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _category = kCategoryAll;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Product> _filtered() {
    var list = store.products;
    if (_category == kCategoryNone) {
      list = list
          .where((p) => p.category.isEmpty || p.category == kCategoryNone)
          .toList();
    } else if (_category != kCategoryAll) {
      list = list
          .where((p) =>
              p.category == _category ||
              p.category.startsWith('$_category/'))
          .toList();
    }
    final q = _query.trim();
    if (q.isNotEmpty) {
      // 与商品页同一套检索：名称 / 品牌 / 条码 / 全拼 / 拼音首字母 + 相关度排序
      final scored = <MapEntry<Product, int>>[];
      for (final p in list) {
        final s = SearchIndex.score(
          query: q,
          name: p.name,
          brand: p.brand,
          barcode: p.barcode,
        );
        if (s > 0) scored.add(MapEntry(p, s));
      }
      scored.sort((a, b) => b.value.compareTo(a.value));
      list = scored.map((e) => e.key).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    final favorites = store.favoriteProducts();
    final filtered = _filtered();
    final searching = _query.trim().isNotEmpty || _category != kCategoryAll;

    return Container(
      height: maxHeight,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // 顶部：标题 + 关闭
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  const Text('从商品库选择', style: AppTheme.sectionTitle),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 搜索框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜名称 / 拼音首字母 / 品牌 / 条码',
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
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            // 分类筛选 Chips（搜索时不显示）
            if (!searching) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _catChip(kCategoryAll),
                    for (final c in store.categories) _catChip(c),
                    _catChip(kCategoryNone),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            // 列表
            Expanded(
              child: searching
                  ? _buildList(filtered)
                  : _buildBrowsing(favorites, filtered),
            ),
          ],
        ),
      ),
    );
  }

  /// 浏览模式：常用（星标）分区置顶 + 分类商品
  Widget _buildBrowsing(List<Product> favorites, List<Product> list) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (favorites.isNotEmpty && _category == kCategoryAll) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(Icons.star, size: 16, color: AppTheme.chartPeak),
                SizedBox(width: 4),
                Text('常用商品',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
              ],
            ),
          ),
          for (final p in favorites) _productTile(p),
          const Divider(indent: 16, endIndent: 16, color: AppTheme.divider),
        ],
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text('该分类下暂无商品', style: AppTheme.caption),
            ),
          )
        else
          for (final p in list) _productTile(p),
      ],
    );
  }

  Widget _buildList(List<Product> list) {
    if (list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 44, color: AppTheme.textSecondary),
            SizedBox(height: 8),
            Text('没有找到相关商品', style: AppTheme.caption),
          ],
        ),
      );
    }
    // 用 builder 而不是一次建出所有行：几百个商品时旧写法每敲一个字
    // 都要重建全部 ListTile，键盘输入会明显发卡。
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: list.length,
      itemBuilder: (context, i) => _productTile(list[i]),
    );
  }

  Widget _catChip(String c) {
    final sel = _category == c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        // 选中态用浅橙底 + 深橙字：原来白字压主色只有 3.08:1，看不清
        label: Text(
          c,
          style: TextStyle(
            fontSize: AppTheme.fontCaption,
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
            color: sel ? AppTheme.primaryText : AppTheme.textPrimary,
          ),
        ),
        selected: sel,
        selectedColor: AppTheme.orangeSurface,
        backgroundColor: Colors.white,
        onSelected: (_) => setState(() => _category = c),
      ),
    );
  }

  Widget _productTile(Product p) {
    // 面板外层是带底色的 Container，它会挡住 ListTile 的水波纹（Flutter 会
    // 报「ListTile background color or ink splashes may be invisible」，
    // 表现为点选商品完全没有点按反馈）。官方建议就是给 ListTile 垫一层 Material。
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppTheme.orangeSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          p.isFavorite ? Icons.star : Icons.inventory_2_outlined,
          color: p.isFavorite ? AppTheme.chartPeak : AppTheme.primary,
          size: 22,
        ),
      ),
      title: Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: AppTheme.fontBody, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          if (p.category.isNotEmpty && p.category != kCategoryNone) p.category,
          if (p.brand.isNotEmpty) p.brand,
        ].join(' · '),
        style: const TextStyle(
            fontSize: AppTheme.fontCaption, color: AppTheme.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '¥${fmtPrice(p.retailPrice)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.priceRed,
                ),
              ),
              if (p.wholesalePrice > 0)
                Text(
                  '批 ¥${fmtPrice(p.wholesalePrice)}',
                  style: const TextStyle(
                      fontSize: AppTheme.fontCaption,
                      color: AppTheme.textSecondary),
                ),
            ],
          ),
          // 整行点击 = 按零售价记；填过批发价的商品额外给一个「批发」快捷按钮
          if (p.wholesalePrice > 0) ...[
            const SizedBox(width: 4),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryText,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => Navigator.pop(
                    context, PickedProduct(p, SalePriceMode.wholesale)),
                child: const Text('批发',
                    style: TextStyle(fontSize: AppTheme.fontCaption)),
              ),
            ),
          ],
        ],
      ),
      onTap: () =>
          Navigator.pop(context, PickedProduct(p, SalePriceMode.retail)),
      ),
    );
  }
}
