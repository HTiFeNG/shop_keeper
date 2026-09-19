import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/credit.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart' as du;
import '../utils/format.dart';

/// 欠账本（赊账台账）。
///
/// 村里小卖部的日常：熟客拿了货说「月底一起给」。这里负责登记与催收，
/// **不参与营业额统计** —— 赊出去的货不算当天收入，收回来的钱也不算当天
/// 收入，否则同一笔钱会被记两次。
///
/// 三个视图：
/// - 未结清：按挂账日期升序（挂得最久的最该催）
/// - 已结清：最近结清的在前，可撤销
/// - 按人汇总：谁一共欠多少，点开看明细
class CreditPage extends StatefulWidget {
  const CreditPage({super.key});

  @override
  State<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends State<CreditPage> {
  final store = StoreService.instance;

  /// 0 未结清 / 1 已结清 / 2 按人汇总
  int _view = 0;

  /// 超过这个天数还没还，就在列表里标红提醒去催一下
  static const int _overdueDays = 30;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('欠账本', style: AppTheme.pageTitle),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('记一笔欠账', style: TextStyle(fontSize: 15)),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              _summaryCard(),
              const SizedBox(height: 12),
              _viewSwitcher(),
              const SizedBox(height: 12),
              ..._content(),
            ],
          );
        },
      ),
    );
  }

  // ==================== 汇总 ====================

  Widget _summaryCard() {
    final total = store.unsettledCreditTotal;
    final count = store.unsettledCredits().length;
    final people = store.creditsByCustomer().length;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        gradient: const LinearGradient(
          colors: [AppTheme.totalGradientStart, AppTheme.totalGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('还没收回来的钱',
              style: TextStyle(fontSize: 14, color: Colors.white)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatCurrency(total),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('$count 笔 · 涉及 $people 人',
              style: const TextStyle(fontSize: 13, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _viewSwitcher() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('未结清')),
        ButtonSegment(value: 1, label: Text('已结清')),
        ButtonSegment(value: 2, label: Text('按人汇总')),
      ],
      selected: {_view},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _view = s.first),
    );
  }

  // ==================== 内容 ====================

  List<Widget> _content() {
    if (_view == 0) {
      final list = store.unsettledCredits();
      if (list.isEmpty) {
        return [_empty('没有未结清的欠账')];
      }
      return [for (final c in list) _creditTile(c)];
    }
    if (_view == 1) {
      final list = store.settledCredits();
      if (list.isEmpty) return [_empty('还没有结清过的记录')];
      return [for (final c in list) _creditTile(c)];
    }

    final byCustomer = store.creditsByCustomer();
    if (byCustomer.isEmpty) return [_empty('没有未结清的欠账')];
    return [for (final g in byCustomer) _customerGroup(g)];
  }

  Widget _empty(String text) => Container(
        padding: const EdgeInsets.symmetric(vertical: 44),
        decoration: AppTheme.cardDecoration,
        child: Column(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 52,
                color: AppTheme.textSecondary.withValues(alpha: 0.45)),
            const SizedBox(height: 10),
            Text(text, style: AppTheme.body),
            const SizedBox(height: 4),
            const Text('点右下角「记一笔欠账」开始登记',
                style: AppTheme.caption),
          ],
        ),
      );

  Widget _creditTile(Credit c) {
    final overdue = c.isOverdue(_overdueDays);
    final age = c.ageInDays();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.customer.isEmpty ? '（未填写姓名）' : c.customer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (c.settled) ...[
                        const SizedBox(width: 6),
                        _tag('已结清', AppTheme.success),
                      ] else if (overdue) ...[
                        const SizedBox(width: 6),
                        _tag('挂了 $age 天', AppTheme.negativeStockRed),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${du.dayLabel(c.date)}'
                    '${c.note.isEmpty ? '' : ' · ${c.note}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                  if (c.settled && c.settledDate != null) ...[
                    const SizedBox(height: 2),
                    Text('${du.dayLabel(c.settledDate!)} 已收',
                        style: const TextStyle(
                            fontSize: AppTheme.fontCaption,
                            color: AppTheme.success)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '¥${fmtPrice(c.amount)}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: c.settled ? AppTheme.success : AppTheme.priceRed,
                  ),
                ),
                const SizedBox(height: 2),
                if (c.settled)
                  TextButton(
                    onPressed: () => store.unsettleCredit(c.id),
                    child: const Text('撤销结清',
                        style: TextStyle(fontSize: AppTheme.fontCaption)),
                  )
                else
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => _confirmSettle(c),
                    child: const Text('已收钱',
                        style: TextStyle(fontSize: AppTheme.fontCaption)),
                  ),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert,
                  size: 20, color: AppTheme.textSecondary),
              onSelected: (v) {
                if (v == 'edit') _openEditor(c);
                if (v == 'delete') _confirmDelete(c);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerGroup(CreditByCustomer g) {
    final overdue = du.parseDateKey(g.oldestDate)
        .difference(DateTime.now())
        .inDays
        .abs();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTile 默认不带分隔线，这里去掉多余的边框让卡片更干净
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        // ExpansionTile 内部用 ListTile 绘制，水波纹会落到最近的 Material 上；
        // 卡片是带底色的 DecoratedBox，会挡住水波纹（Flutter 会抛断言），
        // 故垫一层透明 Material。
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          title: Row(
            children: [
              Expanded(
                child: Text(g.customer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Text('¥${fmtPrice(g.total)}',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.priceRed)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${g.count} 笔 · 最早一笔挂了 $overdue 天',
              style: AppTheme.caption,
            ),
          ),
          children: [
            for (final c in store
                .unsettledCredits()
                .where((e) =>
                    (e.customer.trim().isEmpty
                        ? '（未填写姓名）'
                        : e.customer.trim()) ==
                    g.customer))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${du.dayLabel(c.date)}'
                        '${c.note.isEmpty ? '' : ' · ${c.note}'}',
                        style: AppTheme.caption,
                      ),
                    ),
                    Text('¥${fmtPrice(c.amount)}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () => _confirmSettle(c),
                      child: const Text('已收钱',
                          style: TextStyle(fontSize: AppTheme.fontCaption)),
                    ),
                  ],
                ),
              ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: AppTheme.fontCaption,
                color: color,
                fontWeight: FontWeight.w600)),
      );

  // ==================== 交互 ====================

  Future<void> _confirmSettle(Credit c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认「${c.customer}」已还 ¥${fmtPrice(c.amount)}？'),
        content: const Text('确认后这一笔会移到「已结清」，不影响营业额统计（赊账本来就不算收入）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认已收'),
          ),
        ],
      ),
    );
    if (ok == true) {
      store.settleCredit(c.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('已收「${c.customer}」¥${fmtPrice(c.amount)}'),
            duration: const Duration(seconds: 3),
          ));
      }
    }
  }

  Future<void> _confirmDelete(Credit c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔欠账'),
        content: Text('确定删除「${c.customer}」¥${fmtPrice(c.amount)} 吗？此操作不可恢复。'),
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
    if (ok == true) store.deleteCredit(c.id);
  }

  Future<void> _openEditor([Credit? editing]) async {
    final result = await showModalBottomSheet<Credit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreditEditor(editing: editing),
    );
    if (result == null) return;
    if (editing == null) {
      store.addCredit(result);
    } else {
      store.updateCredit(result);
    }
  }
}

/// 新增 / 编辑一笔欠账。
class _CreditEditor extends StatefulWidget {
  const _CreditEditor({this.editing});

  final Credit? editing;

  @override
  State<_CreditEditor> createState() => _CreditEditorState();
}

class _CreditEditorState extends State<_CreditEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late String _date;

  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.editing;
    _nameCtrl = TextEditingController(text: c?.customer ?? '');
    _amountCtrl = TextEditingController(
        text: c == null || c.amount == 0 ? '' : fmtPrice(c.amount));
    _noteCtrl = TextEditingController(text: c?.note ?? '');
    _date = c?.date ?? du.todayKey();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: du.parseDateKey(_date),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = du.dateKey(picked));
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final amount = parsePrice(_amountCtrl.text);
    if (name.isEmpty) {
      setState(() => _error = '请填写客户称呼，方便以后核对是谁欠的');
      return;
    }
    if (amount <= 0) {
      setState(() => _error = '请填写欠款金额');
      return;
    }
    final c = widget.editing;
    Navigator.pop(
      context,
      c == null
          ? Credit(
              id: Credit.newId(),
              customer: name,
              amount: amount,
              date: _date,
              note: _noteCtrl.text.trim(),
            )
          : c.copyWith(
              customer: name,
              amount: amount,
              date: _date,
              note: _noteCtrl.text.trim(),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(widget.editing == null ? '记一笔欠账' : '编辑欠账',
                        style: AppTheme.sectionTitle),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _nameCtrl,
                  autofocus: widget.editing == null,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '客户称呼',
                    hintText: '如：王婶、小学门口张老师',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '欠了多少钱',
                    suffixText: '元',
                    prefixIcon: Icon(Icons.currency_yuan),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '什么时候欠的',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text('${du.dayLabel(_date)}'
                        '${_date == du.todayKey() ? '（今天）' : ''}'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    hintText: '如：两包烟 + 一瓶酒',
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppTheme.priceRed,
                          fontSize: AppTheme.fontCaption)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submit,
                  child: Text(widget.editing == null ? '记下来' : '保存',
                      style: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
