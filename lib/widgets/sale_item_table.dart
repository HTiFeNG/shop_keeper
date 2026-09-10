import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sale.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 宽屏（Web / 桌面）销售明细表格行。交互逻辑与 SaleItemCard 一致：
/// 数量 ± 步进恢复自动联动；手动改总价进入手动模式（解绑图标 + 红色）。
class SaleItemTableRow extends StatefulWidget {
  const SaleItemTableRow({
    super.key,
    required this.index,
    required this.item,
    required this.onChanged,
    required this.onDelete,
    this.stock,
  });

  final int index; // 行号（1 起）
  final SaleItem item;
  final ValueChanged<SaleItem> onChanged;
  final VoidCallback onDelete;
  final int? stock; // 关联商品库存（null = 手输行）

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

  void _changeQuantity(int qty) {
    final q = qty < 0 ? 0 : qty;
    _qtyCtrl.text = q.toString();
    final next = widget.item.copy()
      ..quantity = q
      ..totalPrice = q * widget.item.unitPrice
      ..isManualMode = false;
    widget.onChanged(next);
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
          // 名称 + 库存
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: _cellField(
                    ctrl: _nameCtrl,
                    focus: _nameFocus,
                    hint: '商品名称',
                    onChanged: (v) {
                      final next = it.copy()..name = v;
                      widget.onChanged(next);
                    },
                  ),
                ),
                if (widget.stock != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _stockBadge(widget.stock!),
                  ),
              ],
            ),
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
                    onChanged: (v) => _changeQuantity(int.tryParse(v) ?? 0),
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
                Icon(
                  it.isManualMode ? Icons.link_off : Icons.link,
                  size: 16,
                  color: it.isManualMode ? AppTheme.priceRed : AppTheme.success,
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

  Widget _stockBadge(int stock) {
    final Color color;
    if (stock < 0) {
      color = AppTheme.negativeStockRed;
    } else if (stock <= 3) {
      color = AppTheme.lowStockOrange;
    } else {
      color = AppTheme.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '库存$stock',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: stock <= 3 ? FontWeight.w700 : FontWeight.normal,
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
    return SizedBox(
      width: 34,
      height: 34,
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
    required this.stockOf,
    required this.onChanged,
    required this.onDelete,
  });

  final List<SaleItem> items;
  final int? Function(String? productId) stockOf;
  final ValueChanged<SaleItem> onChanged;
  final ValueChanged<SaleItem> onDelete;

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
                SizedBox(width: 150, child: Text('数量', style: AppTheme.caption, textAlign: TextAlign.center)),
                SizedBox(width: 110, child: Text('单价', style: AppTheme.caption, textAlign: TextAlign.end)),
                SizedBox(width: 150, child: Text('总价', style: AppTheme.caption, textAlign: TextAlign.end)),
                SizedBox(width: 48),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++)
            SaleItemTableRow(
              key: ValueKey(items[i].id),
              index: i + 1,
              item: items[i],
              stock: stockOf(items[i].productId),
              onChanged: onChanged,
              onDelete: () => onDelete(items[i]),
            ),
        ],
      ),
    );
  }
}
