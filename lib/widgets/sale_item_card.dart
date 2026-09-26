import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sale.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'brand_tag.dart';

/// 手机端销售明细卡片。
///
/// 交互模型移植自 sales-tracker ProductRow.tsx：
/// - 数量 ± 步进（编辑数量恢复自动联动）；
/// - 单价编辑（恢复自动联动）；
/// - 总价默认自动 = 单价 × 数量；手动改写 → isManualMode=true 并显示解绑图标；
/// - 删除由父层负责撤销 SnackBar。
///
/// 注：库存已随「库存功能」移除，本行不再显示库存角标。
class SaleItemCard extends StatefulWidget {
  const SaleItemCard({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
    this.brand = '',
    this.autofocusName = false,
  });

  final SaleItem item;
  final ValueChanged<SaleItem> onChanged;
  final VoidCallback onDelete;

  /// 该行要显示的品牌（由父层经 `StoreService.brandOf` 取，含老数据的回查兜底）
  final String brand;

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
  ///
  /// [syncText] = false 用于「用户正在输入框里打字」的场景：此时不要把
  /// 文本框内容回写，否则清空输入框会立刻被写成 "0"，数字永远改不掉。
  void _changeQuantity(int qty, {bool syncText = true}) {
    final q = qty < 0 ? 0 : qty;
    if (syncText) _qtyCtrl.text = q.toString();
    final next = _item.copy()
      ..quantity = q
      ..totalPrice = q * _item.unitPrice
      ..isManualMode = false;
    _totalCtrl.text = next.totalPrice == 0 ? '' : fmtPrice(next.totalPrice);
    widget.onChanged(next);
  }

  /// 数量输入框回调：清空/半成品输入时先不动数据，等用户敲出数字再算
  void _onQtyInput(String raw) {
    final q = int.tryParse(raw.trim());
    if (q == null) return;
    _changeQuantity(q, syncText: false);
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
          // 行1：名称 + 品牌 + 计价方式 + 手动标记 + 删除
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        autofocus: widget.autofocusName,
                        style: const TextStyle(
                            fontSize: AppTheme.fontBody,
                            fontWeight: FontWeight.w600),
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
                    // 品牌紧跟商品名：同名商品（如两种「矿泉水」）一眼分开。
                    //
                    // 这里刻意用「非弹性的 ConstrainedBox」而不是 Flexible：
                    // Row 里两个弹性子项会**均分**可用宽度，名称输入框会被
                    // 白白砍掉一半（哪怕品牌只占 4 个字）。品牌按内容取宽、
                    // 上限 96dp，剩下的全给名称。
                    if (widget.brand.trim().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 96),
                        child: BrandTag(widget.brand),
                      ),
                    ],
                  ],
                ),
              ),
              if (it.canSwitchPriceMode) _priceModeChip(),
              if (it.isManualMode) _manualTag(),
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
          //
          // 单价输入框用 Expanded 吃掉剩余宽度，而不是写死 88px —— 固定宽度在
          // 窄屏（360dp，也就是绝大多数手机）上会溢出：把步进按钮放大到 48dp
          // 后这一行正好超出 3px，debug 下会出现黄黑溢出条纹。
          Row(
            children: [
              const Text('数量', style: AppTheme.caption),
              const SizedBox(width: 6),
              _stepBtn(Icons.remove,
                  it.quantity <= 0 ? null : () => _changeQuantity(it.quantity - 1)),
              SizedBox(
                width: 40,
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
                  onChanged: _onQtyInput,
                ),
              ),
              _stepBtn(Icons.add, () => _changeQuantity(it.quantity + 1)),
              const SizedBox(width: 12),
              const Text('单价', style: AppTheme.caption),
              const SizedBox(width: 6),
              Expanded(
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

  /// 计价方式切换（零售价 ⇄ 批发价）。
  ///
  /// 只在「商品库来的行 + 该商品填过批发价」时出现 —— 手输行没有价格可切。
  /// 点一下就把单价换成另一套价，并恢复自动联动（总价 = 单价 × 数量）。
  ///
  /// 视觉规格与品牌标签**完全共用** `kTag*` 常量：两个标签在这一行里挨着显示，
  /// 字号/内边距/圆角差一点就能看出「一大一小」。左侧留 6dp 与品牌隔开。
  Widget _priceModeChip() {
    final wholesale = _item.priceMode == SalePriceMode.wholesale;
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 4),
      child: Tooltip(
        message: wholesale
            ? '当前按批发价 ¥${fmtPrice(_item.unitPrice)}，点一下改回零售价'
            : '当前按零售价 ¥${fmtPrice(_item.unitPrice)}，'
                '点一下改按批发价 ¥${fmtPrice(_item.wholesalePrice ?? 0)}',
        child: InkWell(
          borderRadius: BorderRadius.circular(kTagRadius),
          onTap: () => widget.onChanged(_item.withPriceMode(
              wholesale ? SalePriceMode.retail : SalePriceMode.wholesale)),
          child: Container(
            padding: kTagPadding,
            decoration: BoxDecoration(
              color: wholesale ? AppTheme.orangeSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(kTagRadius),
              border: Border.all(
                color: wholesale ? AppTheme.primaryText : AppTheme.divider,
              ),
            ),
            child: Text(
              wholesale ? '批发价' : '零售价',
              style: kTagTextStyle.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    wholesale ? AppTheme.primaryText : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 手动模式标签：让「总价被手动改过」这件事一眼可见（只靠一个 18px
  /// 图标很难注意到，而那正是这行数字不再跟着数量变的原因）
  Widget _manualTag() {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.priceRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '手动',
          style: TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.priceRed,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onPressed) {
    // 48dp：老花眼 + 手指粗的用户点 40dp 很容易点空
    return SizedBox(
      width: 48,
      height: 48,
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
