import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart' as du;
import '../utils/format.dart';
import '../utils/search.dart';
import '../widgets/brand_tag.dart';

/// 查账页：在历史明细里按关键字 / 日期区间翻找。
///
/// 为什么需要它：明细页一次只能看一天。想回答「这个月雪碧一共卖了多少」
/// 「上周三谁买了两条烟」这类问题，靠翻日子是翻不出来的。
///
/// 检索能力与商品页共用一套（[SearchIndex]）：商品名的汉字全拼、拼音首字母
/// 都能命中；另外**输入数字会同时匹配单价和总价**，方便「找那笔 25 块的账」。
///
/// 返回被点中的日期（`String`），由调用方切到当天明细。
class SalesSearchPage extends StatefulWidget {
  const SalesSearchPage({super.key, required this.initialDate});

  /// 进入时默认的日期（一般是首页当前看的那天）
  final String initialDate;

  @override
  State<SalesSearchPage> createState() => _SalesSearchPageState();
}

class _SalesSearchPageState extends State<SalesSearchPage> {
  final store = StoreService.instance;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  String _query = '';
  int _preset = 2; // 0 今天 / 1 本周 / 2 本月 / 3 近 30 天 / 4 自定义
  late String _start;
  late String _end;

  static const List<String> _presetLabels = ['今天', '本周', '本月', '近30天', '自定义'];

  @override
  void initState() {
    super.initState();
    _applyPreset(2, notify: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ==================== 日期区间 ====================

  void _applyPreset(int p, {bool notify = true}) {
    final today = DateTime.now();
    final todayKey = du.dateKey(today);
    switch (p) {
      case 0:
        _start = todayKey;
        _end = todayKey;
        break;
      case 1:
        // 周一为一周之始
        final monday = today.subtract(Duration(days: today.weekday - 1));
        _start = du.dateKey(monday);
        _end = todayKey;
        break;
      case 2:
        _start = '${du.monthKey(today)}-01';
        _end = todayKey;
        break;
      case 3:
        _start = du.dateKey(today.subtract(const Duration(days: 29)));
        _end = todayKey;
        break;
      default:
        break; // 自定义：保持现有起止
    }
    if (notify) setState(() => _preset = p);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: du.parseDateKey(_start),
        end: du.parseDateKey(_end),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = 4;
      _start = du.dateKey(picked.start);
      _end = du.dateKey(picked.end);
    });
  }

  // ==================== 检索 ====================

  /// 一行明细是否命中关键字。
  ///
  /// 纯数字输入时额外比单价 / 总价的文本形式 —— 店主常常记得金额不记得名字。
  bool _match(SaleItem it, String q) {
    if (SearchIndex.matches(query: q, name: it.name)) return true;
    if (RegExp(r'^[\d.]+$').hasMatch(q)) {
      if (fmtPrice(it.totalPrice).contains(q)) return true;
      if (fmtPrice(it.unitPrice).contains(q)) return true;
    }
    return false;
  }

  /// 命中结果：[日期 → 该天命中的明细]
  List<MapEntry<String, List<SaleItem>>> _results() {
    final q = _query.trim();
    final records = store.recordsInRange(_start, _end);
    final out = <MapEntry<String, List<SaleItem>>>[];
    for (final rec in records) {
      final hit = q.isEmpty
          ? rec.items
          : rec.items.where((it) => _match(it, q)).toList();
      if (hit.isNotEmpty) out.add(MapEntry(rec.date, hit));
    }
    return out;
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('查账'),
        centerTitle: false,
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final results = _results();
          var itemCount = 0;
          var total = 0.0;
          for (final e in results) {
            for (final it in e.value) {
              itemCount++;
              total += it.totalPrice;
            }
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: '商品名 / 拼音首字母 / 金额，留空看全部',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空',
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
              _presetChips(),
              _summaryBar(results.length, itemCount, total),
              Expanded(
                child: results.isEmpty
                    ? _empty()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          for (final e in results) _dayGroup(e.key, e.value),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _presetChips() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < _presetLabels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  _presetLabels[i],
                  style: TextStyle(
                    fontSize: AppTheme.fontCaption,
                    fontWeight:
                        _preset == i ? FontWeight.w600 : FontWeight.normal,
                    color: _preset == i
                        ? AppTheme.primaryText
                        : AppTheme.textPrimary,
                  ),
                ),
                selected: _preset == i,
                selectedColor: AppTheme.orangeSurface,
                backgroundColor: Colors.white,
                onSelected: (_) {
                  if (i == 4) {
                    _pickRange();
                  } else {
                    _applyPreset(i);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryBar(int days, int items, double total) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${du.dayLabel(_start)} – ${du.dayLabel(_end)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text('命中 $items 条明细 · $days 天有记录', style: AppTheme.caption),
              ],
            ),
          ),
          Text(
            formatCurrency(total),
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.priceRed),
          ),
        ],
      ),
    );
  }

  Widget _dayGroup(String date, List<SaleItem> items) {
    var dayTotal = 0.0;
    var dayQty = 0;
    for (final it in items) {
      dayTotal += it.totalPrice;
      dayQty += it.quantity;
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: AppTheme.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 点日期标题 → 跳到当天明细
          InkWell(
            onTap: () => Navigator.pop(context, date),
            child: Container(
              color: AppTheme.orangeSurface,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.event, size: 16, color: AppTheme.primaryText),
                  const SizedBox(width: 6),
                  Text(du.dayLabel(date),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryText)),
                  const Spacer(),
                  Text('$dayQty 件 · ${formatCurrency(dayTotal)}',
                      style: const TextStyle(
                          fontSize: AppTheme.fontCaption,
                          color: AppTheme.primaryText)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppTheme.primaryText),
                ],
              ),
            ),
          ),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 商品名 + 品牌：查账时常常是「这个名字有好几种货」，
                        // 没有品牌就没法确认查到的是不是自己要找的那一笔
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                it.name.isEmpty ? '未命名商品' : it.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (store.brandOf(it).isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                  child: BrandTag(store.brandOf(it), dense: true)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${it.quantity} 件 × ¥${fmtPrice(it.unitPrice)}'
                          '${it.priceMode == SalePriceMode.wholesale ? ' · 批发' : ''}',
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '¥${fmtPrice(it.totalPrice)}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.priceRed),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 52, color: AppTheme.textSecondary.withValues(alpha: 0.45)),
            const SizedBox(height: 10),
            Text(_query.isEmpty ? '这段时间没有记录' : '没有找到「$_query」',
                style: AppTheme.body),
            const SizedBox(height: 4),
            const Text('换个商品名，或把日期范围放宽一点',
                style: AppTheme.caption),
          ],
        ),
      );
}
