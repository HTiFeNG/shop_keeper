import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/product.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/scan_page.dart';

/// 商品编辑页 —— 新增 / 编辑共用。
///
/// - 新增：[product] 为 null，编号自动生成，类别默认不选，可传入 [presetBarcode]
///   （扫码发现无此商品时新建并自动填入条码）。
/// - 编辑：顶部有删除按钮 + 星标收藏开关（常用商品，记账时优先展示）。
class ProductEditPage extends StatefulWidget {
  const ProductEditPage({super.key, this.product, this.presetBarcode});

  final Product? product;
  final String? presetBarcode;

  @override
  State<ProductEditPage> createState() => _ProductEditPageState();
}

class _ProductEditPageState extends State<ProductEditPage> {
  final _formKey = GlobalKey<FormState>();
  final store = StoreService.instance;

  late final bool isEdit = widget.product != null;

  /// 类别：新商品默认不选（null）
  String? _category;

  /// 扫码仅 Android / iOS 显示
  bool get _canScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    final category = widget.product?.category ?? '';
    _category = category.isEmpty ? null : category;
  }

  late final _nameCtrl = TextEditingController(text: widget.product?.name ?? '');
  late final _brandCtrl =
      TextEditingController(text: widget.product?.brand ?? '');
  late final _barcodeCtrl = TextEditingController(
      text: widget.product?.barcode ?? widget.presetBarcode ?? '');
  late final _wholesaleCtrl = TextEditingController(
      text: widget.product == null ? '' : _fmt(widget.product!.wholesalePrice));
  late final _purchaseCtrl = TextEditingController(
      text: widget.product == null ? '' : _fmt(widget.product!.purchasePrice));
  late final _retailCtrl = TextEditingController(
      text: widget.product == null ? '' : _fmt(widget.product!.retailPrice));
  late final _stockCtrl = TextEditingController(
      text: widget.product == null ? '' : widget.product!.stock.toString());

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _barcodeCtrl.dispose();
    _wholesaleCtrl.dispose();
    _purchaseCtrl.dispose();
    _retailCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v) => fmtPrice(v);

  // ---------------- 保存 ----------------

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 库存：取整（允许负数，与销售超卖联动保持一致）
    int stock() => double.tryParse(_stockCtrl.text.trim())?.round() ?? 0;

    final product = Product(
      id: widget.product?.id ?? store.nextId(),
      name: _nameCtrl.text.trim(),
      category:
          (_category == null || _category!.isEmpty) ? kCategoryNone : _category!,
      brand: _brandCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim(),
      wholesalePrice: parsePrice(_wholesaleCtrl.text),
      purchasePrice: parsePrice(_purchaseCtrl.text),
      retailPrice: parsePrice(_retailCtrl.text),
      stock: stock(),
    );

    if (isEdit) {
      store.updateProduct(product);
    } else {
      store.addProduct(product);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
            content: Text('商品信息已保存'), duration: Duration(seconds: 1)),
      );
    Navigator.of(context).pop();
  }

  // ---------------- 删除（仅编辑模式） ----------------

  Future<void> _delete() async {
    final p = widget.product!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除商品'),
        content: Text('确定删除「${p.name}」吗？此操作不可恢复。'),
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
      store.deleteProduct(p.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// 扫码获取条码，自动填入条码栏
  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code is String && code.isNotEmpty && mounted) {
      setState(() => _barcodeCtrl.text = code);
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isEdit ? '编辑商品' : '新增商品'),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: '删除商品',
              icon:
                  const Icon(Icons.delete_outline, color: AppTheme.priceRed),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(children: [
              _readonlyRow('编号',
                  isEdit ? widget.product!.id : '${store.nextId()}（自动生成）'),
            ]),
            const SizedBox(height: 12),
            _card(children: [
              _label('商品名称', required: true),
              TextFormField(
                controller: _nameCtrl,
                decoration: _deco(hint: '请输入商品名称'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入商品名称' : null,
              ),
              const SizedBox(height: 16),
              _label('类别'),
              _categoryDropdown(),
              const SizedBox(height: 16),
              _label('品牌'),
              TextFormField(
                  controller: _brandCtrl, decoration: _deco(hint: '请输入品牌')),
              const SizedBox(height: 16),
              _label('条码'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeCtrl,
                      decoration: _deco(
                          hint: _canScan ? '请输入或扫描条码' : '请输入条码'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                    ),
                  ),
                  if (_canScan) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      height: 48,
                      child: IconButton(
                        tooltip: '扫描条码',
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.qr_code_scanner, size: 22),
                        onPressed: _scanBarcode,
                      ),
                    ),
                  ],
                ],
              ),
            ]),
            const SizedBox(height: 12),
            _card(children: [
              _label('批发价'),
              _priceField(_wholesaleCtrl),
              const SizedBox(height: 16),
              _label('参考进价'),
              _priceField(_purchaseCtrl),
              const SizedBox(height: 16),
              _label('零售价'),
              _priceField(_retailCtrl),
            ]),
            const SizedBox(height: 12),
            _card(children: [
              _label('库存'),
              TextFormField(
                controller: _stockCtrl,
                decoration: _deco(hint: '请输入库存数量'),
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
              ),
            ]),
            if (isEdit) ...[
              const SizedBox(height: 12),
              _favoriteCard(),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 星标收藏开关：点亮后进入「常用商品」，记账时优先展示、首页快捷条一键添加
  Widget _favoriteCard() {
    final p = widget.product!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: AppTheme.cardDecoration,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          p.isFavorite ? Icons.star : Icons.star_border,
          color: p.isFavorite
              ? AppTheme.warningYellow
              : AppTheme.textSecondary,
          size: 28,
        ),
        title: const Text('常用商品（星标）',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: const Text('点亮后记账时优先展示，首页可一键添加',
            style: TextStyle(fontSize: 12)),
        trailing: Switch(
          value: p.isFavorite,
          activeThumbColor: AppTheme.warningYellow,
          onChanged: (_) {
            store.toggleFavorite(p.id);
            setState(() {}); // 刷新开关与图标
          },
        ),
        onTap: () {
          store.toggleFavorite(p.id);
          setState(() {});
        },
      ),
    );
  }

  /// 类别下拉：选项 = 分类 + 未分类（商品类别可能因删除大类而不在分类栏中，也要兜底列出）
  Widget _categoryDropdown() {
    final options = <String>{...store.categories, kCategoryNone}.toList();
    final current = _category;
    if (current != null && current.isNotEmpty && !options.contains(current)) {
      options.add(current);
    }
    return DropdownButtonFormField<String>(
      initialValue: (current != null && current.isNotEmpty) ? current : null,
      isExpanded: true,
      decoration: _deco(hint: '请选择类别'),
      items: options
          .map((c) => DropdownMenuItem(
              value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (v) => setState(() => _category = v),
    );
  }

  Widget _priceField(TextEditingController ctrl) => TextFormField(
        controller: ctrl,
        decoration: _deco(hint: '0.00'),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: false),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
      );

  // ---------------- 基础组件 ----------------

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            text: text,
            style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500),
            children: required
                ? const [
                    TextSpan(
                        text: ' *',
                        style: TextStyle(color: AppTheme.priceRed))
                  ]
                : null,
          ),
        ),
      );

  Widget _readonlyRow(String label, String value) => Row(
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        ],
      );

  InputDecoration _deco({String? hint}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppTheme.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      );
}
