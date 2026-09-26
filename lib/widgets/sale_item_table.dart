import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sale.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'brand_tag.dart';

/// 宽屏（Web / 桌面）销售明细表格行。交互逻辑与 SaleItemCard 一致：
/// 数量 ± 步进恢复自动联动；手动改总价进入手动模式（解绑图标 + 红色）。
class SaleItemTableRow extends StatefulWidget {
  const SaleItemTableRow({
    super.key,
    required this.index,
    required this.item,
    required this.onChanged,
    required this.onDelete,
    this.brand = '',
  });

  final int index; // 行号（1 起）
  final SaleItem item;
  final ValueChanged<SaleItem> onChanged;
  final VoidCallback onDelete;

  /// 该行要显示的品牌（由父层经 `StoreService.brandOf` 取，含老数据的回查兜底）
  final String brand;

  @override
  State<SaleItemTableRow> createState() => _SaleItemTableRowState();
}

class _SaleItemTableRowState extends State<SaleItemTableRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _totalCtrl;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _qtyFocus = FocusNode();
  final FocusNode _unitFocus = FocusNode();
  final FocusNode _totalFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.name);
    _qtyCtrl = TextEditingController(text: widget.item.quantity.toString());
    _unitCtrl = TextEditingController(
        text: widget.item.unitPrice == 0 ? '' : fmtPrice(widget.item.unitPrice));
    _totalCtrl = TextEditingController(
        text: widget.item.totalPrice == 0 ? '' : fmtPrice(widget.item.totalPrice));
  }

  @override
  void didUpdateWidget(SaleItemTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final it = widget.item;
    if (!_nameFocus.hasFocus && _nameCtrl.text != it.name) {
      _nameCtrl.text = it.name;
    }
    if (!_qtyFocus.hasFocus && _qtyCtrl.text != it.quantity.toString()) {
      _qtyCtrl.text = it.quantity.toString();
    }
    final unitText = it.unitPrice == 0 ? '' : fmtPrice(it.unitPrice);
    if (!_unitFocus.hasFocus && _unitCtrl.text != unitText) {
      _unitCtrl.text = unitText;
    }
    final totalText = it.totalPrice == 0 ? '' : fmtPrice(it.totalPrice);
    if (!_totalFocus.hasFocus && _totalCtrl.text != totalText) {
      _totalCtrl.text = totalText;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _totalCtrl.dispose();
    _nameFocus.dispose();
    _qtyFocus.dispose();
    _unitFocus.dispose();
    _totalFocus.dispose();
    super.dispose();
  }

  void _changeQuantity(int qty, {bool syncText = true}) {
    final q = qty < 0 ? 0 : qty;
    // 用户正在输入时不要回写文本框，否则清空会被立刻写成 "0"
    if (syncText) _qtyCtrl.text = q.toString();
    final next = widget.item.copy()
      ..quantity = q
      ..totalPrice = q * widget.item.unitPrice
      ..isManualMode = false;
    widget.onChanged(next);
  }

  void _onQtyInput(String raw) {
    final q = int.tryParse(raw.trim());
    if (q == null) return;
    _changeQuantity(q, syncText: false);
  }

  void _changeUnitPrice(String raw) {
    final price = parsePrice(raw);
    final next = widget.item.copy()
      ..unitPrice = price
      ..totalPrice = price * widget.item.quantity
      ..isManualMode = false;
    widget.onChanged(next);
  }

  void _changeTotalPrice(String raw) {
    final next = widget.item.copy()
      ..totalPrice = parsePrice(raw)
      ..isManualMode = true;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('${widget.index}',
                style: AppTheme.caption, textAlign: TextAlign.center),
          ),
          // 名称 + 品牌
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cellField(
                  ctrl: _nameCtrl,
                  focus: _nameFocus,
                  hint: '商品名称',
                  onChanged: (v) {
                    final next = it.copy()..name = v;
                    widget.onChanged(next);
                  },
                ),
                // 品牌放名称下方一行：宽屏行高有富余，竖排比横排更好读，
                // 也不会把名称输入框挤窄。
                if (widget.brand.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, top: 2),
                    child: BrandTag(widget.brand, dense: true),
                  ),
              ],
            ),
          ),
          // 计价方式（零售 / 批发）
          SizedBox(
            width: 72,
            child: it.canSwitchPriceMode
                ? Center(child: _priceModeChip())
                : const SizedBox.shrink(),
          ),
          // 数量步进
          SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepBtn(Icons.remove,
                    it.quantity <= 0 ? null : () => _changeQuantity(it.quantity - 1)),
                SizedBox(
                  width: 48,
                  child: _cellField(
                    ctrl: _qtyCtrl,
                    focus: _qtyFocus,
                    align: TextAlign.center,
                    keyboardType: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: _onQtyInput,
                  ),
                ),
                _stepBtn(Icons.add, () => _changeQuantity(it.quantity + 1)),
              ],
            ),
          ),
          // 单价
          SizedBox(
            width: 110,
            child: _cellField(
              ctrl: _unitCtrl,
              focus: _unitFocus,
              align: TextAlign.end,
              hint: '0.00',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: _changeUnitPrice,
            ),
          ),
          // 总价 + 联动图标
          SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Tooltip(
                  message: it.isManualMode
                      ? '手动模式：总价已手动改过，不再跟随数量'
                      : '联动：总价 = 单价 × 数量',
                  child: Icon(
                    it.isManualMode ? Icons.link_off : Icons.link,
                    size: 18,
                    // 纯图标对读屏软件是无意义的，补上语义标签
                    semanticLabel: it.isManualMode ? '手动总价' : '自动总价',
                    color:
                        it.isManualMode ? AppTheme.priceRed : AppTheme.success,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 90,
                  child: _cellField(
                    ctrl: _totalCtrl,
                    focus: _totalFocus,
                    align: TextAlign.end,
                    hint: '0.00',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: it.isManualMode
                          ? AppTheme.priceRed
                          : AppTheme.textPrimary,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    onChanged: _changeTotalPrice,
                  ),
                ),
              ],
            ),
          ),
          // 删除
          SizedBox(
            width: 48,
            child: IconButton(
              tooltip: '删除此行',
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppTheme.textSecondary),
              onPressed: widget.onDelete,
            ),
          ),
        ],
      ),
    );
  }

  /// 计价方式切换（零售价 ⇄ 批发价），逻辑与手机端卡片一致
  Widget _priceModeChip() {
    final it = widget.item;
    final wholesale = it.priceMode == SalePriceMode.wholesale;
    return Tooltip(
      message: wholesale
          ? '按批发价 ¥${fmtPrice(it.unitPrice)}，点一下改回零售价'
          : '按零售价 ¥${fmtPrice(it.unitPrice)}，'
              '点一下改按批发价 ¥${fmtPrice(it.wholesalePrice ?? 0)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onChanged(it.withPriceMode(
            wholesale ? SalePriceMode.retail : SalePriceMode.wholesale)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: wholesale ? AppTheme.orangeSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: wholesale ? AppTheme.primaryText : AppTheme.divider,
            ),
          ),
          child: Text(
            wholesale ? '批发' : '零售',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              fontWeight: FontWeight.w600,
              color: wholesale ? AppTheme.primaryText : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cellField({
    required TextEditingController ctrl,
    required FocusNode focus,
    required ValueChanged<String> onChanged,
    String? hint,
    TextAlign align = TextAlign.start,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    TextStyle? style,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focus,
      textAlign: align,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      style: style ?? const TextStyle(fontSize: AppTheme.fontBody),
      decoration: InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onChanged: onChanged,
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onPressed) {
    // 48dp：与主题承诺的触控区一致（原为 34dp，很容易点空/点错）
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.orangeSurface,
          foregroundColor: AppTheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
      ),
    );
  }
}

/// 宽屏明细表格（表头 + 行列表）。
class SaleItemTable extends StatelessWidget {
  const SaleItemTable({
    super.key,
    required this.items,
    required this.onChanged,
    required this.onDelete,
    this.keyOf,
    this.brandOf,
  });

  final List<SaleItem> items;
  final ValueChanged<SaleItem> onChanged;
  final ValueChanged<SaleItem> onDelete;

  /// 由外部提供每行的 key（首页用它持有 GlobalKey，好在记账后滚动定位到该行）
  final Key? Function(String itemId)? keyOf;

  /// 取该行品牌（首页传 `StoreService.brandOf`，含老数据回查兜底）
  final String Function(SaleItem item)? brandOf;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppTheme.orangeSurface,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: const Row(
              children: [
                SizedBox(width: 32, child: Text('序号', style: AppTheme.caption, textAlign: TextAlign.center)),
                Expanded(flex: 4, child: Text('商品', style: AppTheme.caption)),
                SizedBox(width: 72, child: Text('计价', style: AppTheme.caption, textAlign: TextAlign.center)),
                SizedBox(width: 150, child: Text('数量', style: AppTheme.caption, textAlign: TextAlign.center)),
                SizedBox(width: 110, child: Text('单价', style: AppTheme.caption, textAlign: TextAlign.end)),
                SizedBox(width: 150, child: Text('总价', style: AppTheme.caption, textAlign: TextAlign.end)),
                SizedBox(width: 48),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++)
            SaleItemTableRow(
              key: keyOf?.call(items[i].id) ?? ValueKey(items[i].id),
              index: i + 1,
              item: items[i],
              brand: brandOf?.call(items[i]) ?? '',
              onChanged: onChanged,
              onDelete: () => onDelete(items[i]),
            ),
        ],
      ),
    );
  }
}
