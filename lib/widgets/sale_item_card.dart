import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sale.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 手机端销售明细卡片。
///
/// 交互模型移植自 sales-tracker ProductRow.tsx：
/// - 数量 ± 步进（编辑数量恢复自动联动）；
/// - 单价编辑（恢复自动联动）；
/// - 总价默认自动 = 单价 × 数量；手动改写 → isManualMode=true 并显示解绑图标；
/// - 关联商品行显示库存角标；
/// - 删除由父层负责撤销 SnackBar。
class SaleItemCard extends StatefulWidget {
  const SaleItemCard({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
    this.stock,
    this.autofocusName = false,
  });

  final SaleItem item;
  final ValueChanged<SaleItem> onChanged;
  final VoidCallback onDelete;

  /// 关联商品的当前库存（null 表示纯手输行）
  final int? stock;
  final bool autofocusName;

  @override
  State<SaleItemCard> createState() => _SaleItemCardState();
}

class _SaleItemCardState extends State<SaleItemCard> {
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
  void didUpdateWidget(SaleItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部数据变化（如步进 / 撤销）时同步控制器，正在编辑的输入框不打断
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

  SaleItem get _item => widget.item;

  /// 编辑数量 → 恢复自动联动
  void _changeQuantity(int qty) {
    final q = qty < 0 ? 0 : qty;
    _qtyCtrl.text = q.toString();
    final next = _item.copy()
      ..quantity = q
      ..totalPrice = q * _item.unitPrice
      ..isManualMode = false;
    _totalCtrl.text = next.totalPrice == 0 ? '' : fmtPrice(next.totalPrice);
    widget.onChanged(next);
  }

  /// 编辑单价 → 恢复自动联动并重算总价
  void _changeUnitPrice(String raw) {
    final price = parsePrice(raw);
    final next = _item.copy()
      ..unitPrice = price
      ..totalPrice = price * _item.quantity
      ..isManualMode = false;
    widget.onChanged(next);
  }

  /// 手动改总价 → 进入手动模式（解绑）
  void _changeTotalPrice(String raw) {
    final total = parsePrice(raw);
    final next = _item.copy()
      ..totalPrice = total
      ..isManualMode = true;
    widget.onChanged(next);
  }

  void _changeName(String name) {
    final next = _item.copy()..name = name;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final expected = it.unitPrice * it.quantity;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行1：名称 + 库存角标 + 删除
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  autofocus: widget.autofocusName,
                  style: const TextStyle(
                      fontSize: AppTheme.fontBody, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: '商品名称',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: _changeName,
                ),
              ),
              if (widget.stock != null) _stockBadge(widget.stock!),
              IconButton(
                tooltip: '删除此行',
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.textSecondary, size: 22),
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 2),
          // 行2：数量步进 + 单价
          Row(
            children: [
              const Text('数量', style: AppTheme.caption),
              const SizedBox(width: 8),
              _stepBtn(Icons.remove,
                  it.quantity <= 0 ? null : () => _changeQuantity(it.quantity - 1)),
              SizedBox(
                width: 44,
                child: TextField(
                  controller: _qtyCtrl,
                  focusNode: _qtyFocus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: AppTheme.fontBody),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: (v) => _changeQuantity(int.tryParse(v) ?? 0),
                ),
              ),
              _stepBtn(Icons.add, () => _changeQuantity(it.quantity + 1)),
              const Spacer(),
              const Text('单价', style: AppTheme.caption),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _unitCtrl,
                  textAlign: TextAlign.end,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: const TextStyle(fontSize: AppTheme.fontBody),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    suffixText: '元',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: _changeUnitPrice,
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
          const SizedBox(height: 2),
          // 行3：总价 + 联动图标
          Row(
            children: [
              const Text('总价', style: AppTheme.caption),
              const SizedBox(width: 12),
              Tooltip(
                message: it.isManualMode
                    ? '手动模式：总价已手动修改，不自动联动（联动值 ¥${fmtPrice(expected)}）'
                    : '联动模式：总价 = 单价 × 数量',
                child: Icon(
                  it.isManualMode ? Icons.link_off : Icons.link,
                  size: 18,
                  color: it.isManualMode
                      ? AppTheme.priceRed
                      : AppTheme.success,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _totalCtrl,
                  focusNode: _totalFocus,
                  textAlign: TextAlign.end,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: it.isManualMode
                        ? AppTheme.priceRed
                        : AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    suffixText: '元',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: _changeTotalPrice,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 库存角标：负数红色加粗、0<≤3 橙色、其余灰色
  Widget _stockBadge(int stock) {
    final Color color;
    final FontWeight weight;
    if (stock < 0) {
      color = AppTheme.negativeStockRed;
      weight = FontWeight.w700;
    } else if (stock <= 3) {
      color = AppTheme.lowStockOrange;
      weight = FontWeight.w600;
    } else {
      color = AppTheme.textSecondary;
      weight = FontWeight.normal;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '库存 $stock',
          style: TextStyle(fontSize: 11, color: color, fontWeight: weight),
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.orangeSurface,
          foregroundColor: AppTheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
      ),
    );
  }
}
