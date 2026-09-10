import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../services/export_service.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart' as du;
import '../utils/format.dart';
import '../widgets/date_selector.dart';
import '../widgets/favorite_quick_bar.dart';
import '../widgets/product_picker_dialog.dart';
import '../widgets/sale_item_card.dart';
import '../widgets/sale_item_table.dart';
import 'monthly_stats_page.dart';

/// 营业额首页（Tab 1）。
///
/// 布局自上而下：
/// 1. 标题栏（导出 / 备份恢复入口）
/// 2. 日期选择条 + 日合计大字
/// 3. 内部 Tab：明细记录 / 月度统计
/// 4. 常用商品快捷条（明细 Tab 底部）+「+ 添加」主按钮
///
/// 交互：选品带价、数量步进扣库存、手动改总价解绑、删除 5 秒撤销。
class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage>
    with SingleTickerProviderStateMixin {
  final store = StoreService.instance;
  late final TabController _tabCtrl;

  String _date = du.todayKey();

  /// 删除行「已删除」SnackBar 的兜底关闭定时器（部分机型带 action 时不自动消失）
  Timer? _snackTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // 商品页「记一笔」→ 预填一行（RootPage 已负责切 Tab）
    store.salePrefill.addListener(_onPrefill);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onPrefill();
      _maybeAskSampleData();
    });
  }

  @override
  void dispose() {
    _snackTimer?.cancel();
    store.salePrefill.removeListener(_onPrefill);
    _tabCtrl.dispose();
    super.dispose();
  }

  // ==================== 首启示例数据（P1-7） ====================

  void _maybeAskSampleData() {
    if (!mounted || store.seeded) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('欢迎使用店铺管家'),
        content: const Text('要不要载入一批示例商品（24 种小卖部常见商品）来熟悉一下？\n\n也可以从空开始，自己去「商品」页慢慢录入。'),
        actions: [
          TextButton(
            onPressed: () {
              store.markSeeded();
              Navigator.pop(ctx);
            },
            child: const Text('从空开始', style: TextStyle(fontSize: 15)),
          ),
          FilledButton(
            onPressed: () {
              store.seedSampleData();
              Navigator.pop(ctx);
              _toast('已载入示例商品，去「商品」页看看吧');
            },
            child: const Text('载入示例数据', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  // ==================== 预填（P0-7） ====================

  void _onPrefill() {
    if (!mounted) return;
    final prefill = store.consumePrefill();
    if (prefill == null) return;
    final product = store.findById(prefill.productId);
    if (product == null) return;
    setState(() {
      _date = du.todayKey();
      _tabCtrl.index = 0;
    });
    store.recordSaleFromProduct(_date, product);
    _toast('已记一笔「${product.name}」，可继续调整数量');
  }

  // ==================== 明细操作 ====================

  void _changeDate(String date) {
    setState(() => _date = date);
  }

  Future<void> _addFromLibrary() async {
    final p = await showProductPickerDialog(context);
    if (p == null || !mounted) return;
    store.recordSaleFromProduct(_date, p);
    _toast('已添加「${p.name}」');
  }

  void _addManualRow() {
    store.upsertSaleItem(_date, SaleItem(id: SaleItem.newId(), quantity: 1));
  }

  void _updateItem(SaleItem item) {
    store.upsertSaleItem(_date, item);
  }

  /// 删除一行 + 5 秒撤销（带兜底定时关闭，防止部分机型不自动消失）
  void _deleteItem(SaleItem item) {
    store.deleteSaleItem(_date, item.id);
    _snackTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('已删除「${item.name.isEmpty ? '未命名商品' : item.name}」'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            _snackTimer?.cancel();
            messenger.hideCurrentSnackBar();
            store.upsertSaleItem(_date, item);
          },
        ),
      ));
    // 兜底：5 秒后强制关闭（无障碍/辅助模式下带 action 的 SnackBar 可能不自动消失）
    _snackTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) messenger.hideCurrentSnackBar();
    });
  }

  int? _stockOf(String? productId) {
    if (productId == null) return null;
    return store.findById(productId)?.stock;
  }

  // ==================== 导出 / 备份 ====================

  Future<void> _exportSales() async {
    try {
      final items = store.itemsOf(_date);
      final rows = <List<String>>[
        for (final it in items)
          [it.name, '${it.quantity}', fmtPrice(it.unitPrice), fmtPrice(it.totalPrice)],
      ];
      final stats = store.monthlyStats(du.monthKey(du.parseDateKey(_date)));
      await ExportService.exportSales(date: _date, dayRows: rows, stats: stats);
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  Future<void> _exportBackup() async {
    try {
      await ExportService.exportBackup(store.exportBackup());
    } catch (e) {
      _toast('备份失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > kWideBreakpoint;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('营业额', style: AppTheme.pageTitle),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '导出当日明细 + 月度汇总',
            icon: const Icon(Icons.ios_share),
            onPressed: _exportSales,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'backup') _exportBackup();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.backup_outlined),
                  title: Text('备份全部数据'),
                  subtitle: Text('导出为文件，换机/重装可恢复'),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: '明细记录'),
            Tab(text: '月度统计'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final items = store.itemsOf(_date);
          return TabBarView(
            controller: _tabCtrl,
            children: [
              _dailyView(items, wide),
              MonthlyStatsPage(
                initialMonth: du.monthKey(du.parseDateKey(_date)),
                onJumpToDate: (date) {
                  setState(() => _date = date);
                  _tabCtrl.animateTo(0);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// 明细记录视图
  Widget _dailyView(List<SaleItem> items, bool wide) {
    final total = store.dayTotal(_date);
    final qty = items.fold(0, (s, e) => s + e.quantity);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              DateSelector(dateKey: _date, onChanged: _changeDate),
              const SizedBox(height: 12),
              _dailyTotalCard(total, qty, items.length),
              const SizedBox(height: 12),
              if (items.isEmpty)
                _emptyState()
              else if (wide)
                SaleItemTable(
                  items: items,
                  stockOf: _stockOf,
                  onChanged: _updateItem,
                  onDelete: _deleteItem,
                )
              else
                for (final item in items)
                  SaleItemCard(
                    key: ValueKey(item.id),
                    item: item,
                    stock: _stockOf(item.productId),
                    onChanged: _updateItem,
                    onDelete: () => _deleteItem(item),
                  ),
            ],
          ),
        ),
        // 底部：常用快捷条 + 添加按钮
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FavoriteQuickBar(
                  favorites: store.favoriteProducts(),
                  onPick: (p) {
                    store.recordSaleFromProduct(_date, p);
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _addFromLibrary,
                        icon: const Icon(Icons.add),
                        label: const Text('从商品库添加',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                        ),
                        onPressed: _addManualRow,
                        icon: const Icon(Icons.edit_note, size: 20),
                        label: const Text('手动输入',
                            style: TextStyle(fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 日合计大字卡片
  Widget _dailyTotalCard(double total, int qty, int kinds) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        gradient: const LinearGradient(
          colors: [Color(0xFFFB8C00), Color(0xFFEF6C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${du.dayLabel(_date)} 合计',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.9))),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(total),
                  style: const TextStyle(
                    fontSize: AppTheme.fontBigTotal,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$kinds 种商品',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9))),
              const SizedBox(height: 2),
              Text('共 $qty 件',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9))),
            ],
          ),
        ],
      ),
    );
  }

  /// 空状态：给下一步指引
  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: AppTheme.cardDecoration,
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            du.dateKey(DateTime.now()) == _date ? '今天还没记账' : '这一天没有记录',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            '点下方「从商品库添加」选货自动带价，\n或「手动输入」直接记一笔',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
