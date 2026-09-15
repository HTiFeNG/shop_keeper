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

  /// 已成功保存（用于放行返回手势）
  bool _saved = false;

  /// 是否改过任何字段：返回时提醒，避免误划退出丢掉半天输入
  bool get _hasChanges {
    final p = widget.product;
    if (p == null) {
      return _nameCtrl.text.trim().isNotEmpty ||
          _brandCtrl.text.trim().isNotEmpty ||
          _barcodeCtrl.text.trim().isNotEmpty ||
          _wholesaleCtrl.text.trim().isNotEmpty ||
          _purchaseCtrl.text.trim().isNotEmpty ||
          _retailCtrl.text.trim().isNotEmpty;
    }
    return _nameCtrl.text.trim() != p.name ||
        _brandCtrl.text.trim() != p.brand ||
        _barcodeCtrl.text.trim() != p.barcode ||
        _category != (p.category.isEmpty ? null : p.category) ||
        parsePrice(_wholesaleCtrl.text) != p.wholesalePrice ||
        parsePrice(_purchaseCtrl.text) != p.purchasePrice ||
        parsePrice(_retailCtrl.text) != p.retailPrice;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _barcodeCtrl.dispose();
    _wholesaleCtrl.dispose();
    _purchaseCtrl.dispose();
    _retailCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v) => fmtPrice(v);

  // ---------------- 保存 ----------------

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 零售价为 0 会被记成「0 元卖出」，多半是漏填，先确认一次
    if (parsePrice(_retailCtrl.text) <= 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('零售价是 0'),
          content: const Text('零售价没填或填成了 0，卖出去会记成 0 元。仍要保存吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('返回修改')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('仍然保存')),
          ],
        ),
      );
      if (go != true) return;
    }

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
      // 库存已废弃：编辑旧商品时沿用原值，避免抹掉历史数据
      stock: widget.product?.stock ?? 0,
    );

    final ok =
        isEdit ? store.updateProduct(product) : store.addProduct(product);
    if (!ok) {
      // 条码重复会让扫码永远只命中第一个商品，必须挡住
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('这个条码已经被别的商品用了，请换一个'),
            duration: Duration(seconds: 4)));
      return;
    }

    _saved = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
            content: Text('商品信息已保存'), duration: Duration(seconds: 2)),
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
    return PopScope(
      // 有未保存改动时拦一下返回（Android 返回键 / 侧滑手势）
      canPop: _saved || !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 先取好 Navigator，避免 await 之后再碰 context
        final navigator = Navigator.of(context);
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('还没保存'),
            content: const Text('这个商品的修改还没保存，确定离开吗？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('继续编辑')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('放弃修改')),
            ],
          ),
        );
        if (leave == true) navigator.pop();
      },
      child: Scaffold(
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
                autofocus: !isEdit,
                textInputAction: TextInputAction.next,
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
            if (isEdit) ...[
              const SizedBox(height: 12),
              _favoriteCard(),
            ],
            const SizedBox(height: 32),
          ],
        ),
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
      // 卡片底色同样会挡住 ListTile 的水波纹，按官方建议垫一层透明 Material
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          p.isFavorite ? Icons.star : Icons.star_border,
          color: p.isFavorite
              ? AppTheme.chartPeak
              : AppTheme.textSecondary,
          size: 28,
        ),
        title: const Text('常用商品（星标）',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: const Text('点亮后记账时优先展示，首页可一键添加',
            style: TextStyle(fontSize: AppTheme.fontCaption)),
        trailing: Switch(
          value: p.isFavorite,
          activeThumbColor: AppTheme.chartPeak,
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
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        // "1.2.3"、"12元" 这类输入会被 parsePrice 归 0；旧实现没有校验，
        // 会静默存成 ¥0 还提示「已保存」。这里直接拦住。
        validator: (v) {
          final s = (v ?? '').trim();
          if (s.isEmpty) return null; // 留空按 0 处理
          final n = double.tryParse(s);
          if (n == null || !n.isFinite || n < 0) return '请填数字金额，如 3.50';
          return null;
        },
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
