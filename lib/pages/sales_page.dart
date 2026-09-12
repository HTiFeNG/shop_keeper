import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../models/product.dart';
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
import '../widgets/scan_page.dart';
import 'monthly_stats_page.dart';

/// 营业额首页（Tab 1）。
///
/// 布局自上而下：
/// 1. 标题栏（导出 / 备份恢复入口）
/// 2. 日期选择条 + 日合计大字
/// 3. 内部 Tab：明细记录 / 月度统计
/// 4. 常用商品快捷条（明细 Tab 底部）+「+ 添加」主按钮
///
/// 交互：选品带价、扫码记账、手动改总价解绑、删除 5 秒撤销。
///
/// 注：库存已随「库存功能」移除（3.0.0）。
class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final store = StoreService.instance;
  late final TabController _tabCtrl;

  String _date = du.todayKey();

  /// 是否跟随「今天」。
  ///
  /// 柜台手机常常整夜开着，而 RootPage 用 IndexedStack 让本页常驻、`_date`
  /// 只在创建时算一次 —— 旧实现里第二天早上的营业额会全部记进昨天。
  /// 这里在回到前台时重新对表；用户手动翻到别的日期后不再自动跟随。
  bool _followToday = true;

  /// 扫码按钮只在手机端显示（Web 无摄像头）
  bool get _canScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 删除行「已删除」SnackBar 的兜底关闭定时器（部分机型带 action 时不自动消失）
  Timer? _snackTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    // 商品页「记一笔」→ 预填一行（RootPage 已负责切 Tab）
    store.salePrefill.addListener(_onPrefill);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncToday();
      _onPrefill();
      _maybeAskSampleData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snackTimer?.cancel();
    store.salePrefill.removeListener(_onPrefill);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台回到前台是对表的关键时机（跨零点）
    if (state == AppLifecycleState.resumed) _syncToday();
  }

  /// 仍在「跟随今天」且日期已变 → 自动切到新的一天
  void _syncToday() {
    if (!mounted) return;
    final today = du.todayKey();
    if (_followToday && _date != today) {
      setState(() => _date = today);
    }
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
      _followToday = true;
      _tabCtrl.index = 0;
    });
    store.recordSaleFromProduct(_date, product);
    _toast('已记一笔「${product.name}」，可继续调整数量');
  }

  // ==================== 明细操作 ====================

  void _changeDate(String date) {
    setState(() {
      _date = date;
      // 手动翻到别的日期后不再自动跟随今天
      _followToday = date == du.todayKey();
    });
  }

  /// 所有「记账」入口都先对一次日期，再记到当前这一天
  void _record(Product p) {
    _syncToday();
    store.recordSaleFromProduct(_date, p);
  }

  Future<void> _addFromLibrary() async {
    final p = await showProductPickerDialog(context);
    if (p == null || !mounted) return;
    _record(p);
    _toast('已添加「${p.name}」');
  }

  /// 扫码直接记账：条码已在商品库 → 记一笔；不在 → 提示先去新建
  Future<void> _scanToSell() async {
    final code = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code is! String || code.isEmpty || !mounted) return;
    final p = store.findByBarcode(code);
    if (p == null) {
      _toastErr('商品库里没有条码 $code，请先到「商品」页新增');
      return;
    }
    _record(p);
    _toast('已记一笔「${p.name}」');
  }

  void _addManualRow() {
    _syncToday();
    store.upsertSaleItem(_date, SaleItem(id: SaleItem.newId(), quantity: 1));
  }

  void _updateItem(SaleItem item) {
    store.upsertSaleItem(_date, item);
  }

  /// 删除一行 + 5 秒撤销（带兜底定时关闭，防止部分机型不自动消失）
  ///
  /// `date` 必须在删除的当下就固定下来。旧实现在撤销回调里重新读 `_date`，
  /// 于是「删一行 → 5 秒内翻到另一天 → 点撤销」会把这一行还原到**新的一天**
  /// （原日期凭空少一行、新日期凭空多一行），并让该商品被重复扣一次库存。
  void _deleteItem(SaleItem item) {
    final date = _date;
    store.deleteSaleItem(date, item.id);
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
            store.upsertSaleItem(date, item);
          },
        ),
      ));
    // 兜底：5 秒后强制关闭（无障碍/辅助模式下带 action 的 SnackBar 可能不自动消失）
    _snackTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) messenger.hideCurrentSnackBar();
    });
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
    } catch (_) {
      _toastErr('导出没成功，请检查手机存储空间后重试', retry: _exportSales);
    }
  }

  Future<void> _exportBackup() async {
    try {
      await ExportService.exportBackup(store.exportBackup());
      store.markBackedUp();
      _toast('备份已导出，请把这个文件保存好');
    } catch (_) {
      _toastErr('备份没成功，请检查手机存储空间后重试', retry: _exportBackup);
    }
  }

  /// 普通提示
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  /// 失败提示：一句人话 + 停留更久 + 可重试。
  ///
  /// 旧实现把 `'导出失败：$e'` 这样的裸异常丢给用户看 2 秒 —— 对中老年店主
  /// 既读不懂也来不及看，而且没有任何补救入口。
  void _toastErr(String msg, {Future<void> Function()? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 6),
        action: retry == null
            ? null
            : SnackBarAction(label: '重试', onPressed: () => retry()),
      ));
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
            // 纵向留白从 12 收到 8：把空间还给明细行本身
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              DateSelector(dateKey: _date, onChanged: _changeDate),
              const SizedBox(height: 8),
              _dailyTotalCard(total, qty, items.length),
              ..._warnings(),
              const SizedBox(height: 8),
              if (items.isEmpty)
                _emptyState()
              else if (wide)
                SaleItemTable(
                  items: items,
                  onChanged: _updateItem,
                  onDelete: _deleteItem,
                )
              else
                for (final item in items)
                  SaleItemCard(
                    key: ValueKey(item.id),
                    item: item,
                    onChanged: _updateItem,
                    onDelete: () => _deleteItem(item),
                  ),
            ],
          ),
        ),
        // 底部：常用/常卖快捷条 + 添加按钮
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FavoriteQuickBar(
                  favorites: store.favoriteProducts(),
                  recent: store.recentProducts(limit: 8),
                  onPick: (p) => _record(p),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _addFromLibrary,
                        icon: const Icon(Icons.add),
                        label: const Text('添加商品',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    if (_canScan) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton.filledTonal(
                          tooltip: '扫码记账',
                          onPressed: _scanToSell,
                          icon: const Icon(Icons.qr_code_scanner, size: 22),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryText,
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

  /// 顶部提醒：数据损坏 / 保存失败 / 该备份了。
  ///
  /// 这些都属于「不主动说、用户就永远不知道」的问题（比如 Web 端存储写满后
  /// 改动其实没保存），所以必须显式提示，而不是安静地继续。
  List<Widget> _warnings() {
    final out = <Widget>[];
    if (store.loadError != null) {
      out.add(_banner(
        icon: Icons.error_outline,
        color: AppTheme.negativeStockRed,
        text: '${store.loadError}。请先不要再录入，用备份文件恢复数据。',
      ));
    } else if (store.droppedOnLoad > 0) {
      out.add(_banner(
        icon: Icons.warning_amber_outlined,
        color: AppTheme.primaryText,
        text: '启动时有 ${store.droppedOnLoad} 条数据损坏、已跳过。建议尽快备份并核对账目。',
      ));
    }
    if (store.saveError != null) {
      out.add(_banner(
        icon: Icons.save_outlined,
        color: AppTheme.negativeStockRed,
        text: '${store.saveError}（最近的改动可能没写进手机）',
      ));
    }
    // 备份提醒只对「已经有数据」的用户显示，避免新装用户被反复打扰
    if (store.products.isNotEmpty) {
      final days = store.daysSinceBackup;
      if (days == null) {
        out.add(_banner(
          icon: Icons.backup_outlined,
          color: AppTheme.primaryText,
          text: '还没有备份过。数据只存在这台手机里，建议现在就备份一次。',
          action: _exportBackup,
          actionLabel: '立即备份',
        ));
      } else if (days >= 7) {
        out.add(_banner(
          icon: Icons.backup_outlined,
          color: AppTheme.primaryText,
          text: '已经 $days 天没备份了，建议现在备份一次。',
          action: _exportBackup,
          actionLabel: '立即备份',
        ));
      }
    }
    return out;
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String text,
    Future<void> Function()? action,
    String? actionLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: AppTheme.fontCaption,
                      color: AppTheme.textPrimary)),
            ),
            if (action != null && actionLabel != null)
              TextButton(
                onPressed: () => action(),
                child: Text(actionLabel,
                    style: const TextStyle(fontSize: AppTheme.fontCaption)),
              ),
          ],
        ),
      ),
    );
  }

  /// 日合计大字卡片
  ///
  /// 渐变改用更深的两个橙（原 #FB8C00→#EF6C00 上白字只有 2.37:1，
  /// 全 App 最该一眼看清的数字反而最糊）；统计合并成一行也比原来矮一截。
  Widget _dailyTotalCard(double total, int qty, int kinds) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        gradient: const LinearGradient(
          colors: [AppTheme.totalGradientStart, AppTheme.totalGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.totalGradientEnd.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${du.dayLabel(_date)} 合计',
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
                const SizedBox(height: 2),
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
          Text('$kinds 种 · $qty 件',
              style: const TextStyle(fontSize: 14, color: Colors.white)),
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
              size: 56, color: AppTheme.textSecondary.withValues(alpha: 0.45)),
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
            '点下方「添加商品」选货自动带价，\n或「手动输入」直接记一笔',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: AppTheme.fontCaption, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
