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
import 'credit_page.dart';
import 'monthly_stats_page.dart';
import 'sales_search_page.dart';
import 'sync_settings_page.dart';

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

  /// 明细列表滚动控制器（新增一行后要把视图滚到它那里）
  final ScrollController _listCtrl = ScrollController();

  /// 每行一个 GlobalKey，用于记账后定位到对应行。
  ///
  /// 明细列表刻意用「Column + SingleChildScrollView」而不是 ListView：
  /// ListView 是懒构建的，视口外的行根本不在 widget 树里，
  /// `Scrollable.ensureVisible` 拿不到 context —— 而新增的行在末尾，
  /// 恰恰经常就在视口外，定位会失败。
  final Map<String, GlobalKey> _rowKeys = {};

  GlobalKey _rowKey(String itemId) =>
      _rowKeys.putIfAbsent(itemId, () => GlobalKey());

  /// 记账后把视图滚到刚新增（或合并进去）的那一行
  Future<void> _scrollToRow(String? itemId) async {
    if (itemId == null) return;
    // 等这一帧把新行布局出来，否则取不到 context
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final ctx = _rowKeys[itemId]?.currentContext;
    // ctx 自己的 mounted 检查（跨 await 之后不能复用 State.mounted 来保它）
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.5, // 居中显示，上下都留一点上下文
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

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
      _checkRemoteBackup();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snackTimer?.cancel();
    _listCtrl.dispose();
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
    final id = store.recordSaleFromProduct(_date, product);
    unawaited(_scrollToRow(id));
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

  /// 所有「记账」入口都先对一次日期，再记到当前这一天，
  /// 最后把视图滚到刚变动的那一行。
  void _record(Product p, {SalePriceMode mode = SalePriceMode.retail}) {
    _syncToday();
    final id = store.recordSaleFromProduct(_date, p, mode: mode);
    unawaited(_scrollToRow(id));
  }

  Future<void> _addFromLibrary() async {
    final picked = await showProductPickerDialog(context);
    if (picked == null || !mounted) return;
    _record(picked.product, mode: picked.mode);
    final tag = picked.mode == SalePriceMode.wholesale ? '（批发价）' : '';
    _toast('已添加「${picked.product.name}」$tag');
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
    final item = SaleItem(id: SaleItem.newId(), quantity: 1);
    store.upsertSaleItem(_date, item);
    unawaited(_scrollToRow(item.id));
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
    _rowKeys.remove(item.id);
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

  // ==================== 查账 / 欠账 / 跨端同步 ====================

  /// 查账：在历史明细里按关键字 + 日期区间翻找；点中某天则切回那天的明细
  Future<void> _openSearch() async {
    final date = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => SalesSearchPage(initialDate: _date)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _date = date;
      _followToday = date == du.todayKey();
      _tabCtrl.index = 0;
    });
  }

  void _openCredits() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CreditPage()));
  }

  void _openSync() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SyncSettingsPage()));
  }

  /// 启动时检查云端是否有更新的备份（只提示，不静默覆盖本地）
  Future<void> _checkRemoteBackup() async {
    await store.checkRemote();
  }

  /// 应用启动时挂起的云端备份 → 用户确认后恢复
  Future<void> _applyRemoteBackup() async {
    final preview = store.pendingRemotePreview;
    final when = preview?.exportedAt == null
        ? '未记录'
        : preview!.exportedAt!.replaceFirst('T', ' ').split('.').first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('云端有更新的备份'),
        content: Text('云端那份备份（$when）是在别的设备上保存的：\n'
            '· ${preview?.productCount ?? 0} 个商品\n'
            '· ${preview?.dayCount ?? 0} 天的营业额\n'
            '· ${preview?.creditCount ?? 0} 笔欠账\n\n'
            '恢复会用云端的【完全覆盖】本机数据。\n'
            '恢复前会自动存一份当前数据，之后可以一键撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('先用本机的')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('用云端的')),
        ],
      ),
    );
    if (ok != true) {
      store.dismissPendingRemote();
      return;
    }
    final r = await store.applyPendingRemote();
    if (!mounted) return;
    if (r.ok) {
      _toast('已从云端恢复：${r.productCount} 个商品、${r.dayCount} 天记录');
    } else {
      _toastErr('恢复失败：${r.reason}');
    }
  }

  /// 普通提示
  void _toast(String msg) {    if (!mounted) return;
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
            tooltip: '查账（按商品名或金额翻历史明细）',
            icon: const Icon(Icons.manage_search),
            onPressed: _openSearch,
          ),
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
              if (v == 'credits') _openCredits();
              if (v == 'sync') _openSync();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'credits',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('欠账本'),
                  subtitle: Text(
                    store.unsettledCredits().isEmpty
                        ? '记录谁赊了账'
                        : '未收回 ¥${fmtPrice(store.unsettledCreditTotal)}'
                            '(${store.unsettledCredits().length} 笔)',
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'sync',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cloud_sync_outlined),
                  title: Text('跨端同步（坚果云）'),
                  subtitle: Text('手机与电脑共用同一份数据'),
                ),
              ),
              const PopupMenuItem(
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
        // 悬浮的当日合计：固定在列表上方，不随滚动消失 ——
        // 明细多到需要上下翻时也始终能看到当天金额。
        // 日期一并写在条里，所以往下翻时仍知道看的是哪一天。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: _floatingTotalBar(total, qty, items.length),
        ),
        Expanded(
          // 用 SingleChildScrollView + Column（非懒构建）而不是 ListView：
          // 明细行会持有 GlobalKey，懒构建时视口外的行不在树里，
          // 新增到末尾的行就定位不到（详见 _rowKeys 的说明）。
          child: SingleChildScrollView(
            controller: _listCtrl,
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DateSelector(dateKey: _date, onChanged: _changeDate),
                const SizedBox(height: 8),
                ..._warnings(),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  _emptyState()
                else if (wide)
                  SaleItemTable(
                    items: items,
                    keyOf: _rowKey,
                    onChanged: _updateItem,
                    onDelete: _deleteItem,
                  )
                else
                  for (final item in items)
                    SaleItemCard(
                      key: _rowKey(item.id),
                      item: item,
                      onChanged: _updateItem,
                      onDelete: () => _deleteItem(item),
                    ),
              ],
            ),
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

    // 云端有更新的备份（启动时检查出来的）——只提示，覆盖与否由用户决定
    final pending = store.pendingRemotePreview;
    if (pending != null) {
      final when = pending.exportedAt == null
          ? '未知时间'
          : pending.exportedAt!.replaceFirst('T', ' ').split('.').first;
      out.add(_banner(
        icon: Icons.cloud_download_outlined,
        color: AppTheme.primaryText,
        text: '云端有一份更新的备份（$when），'
            '${pending.productCount} 个商品 / ${pending.dayCount} 天记录。',
        action: _applyRemoteBackup,
        actionLabel: '查看',
      ));
    }

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

  /// 悬浮的当日合计条
  ///
  /// 取代原先放在列表里的「日合计大字卡片」：那张卡会随列表一起滚走，
  /// 明细一多就看不到当天金额。这条固定在列表上方，而且更矮
  /// （约 54dp，原卡片约 78dp），等于把高度还给了明细行。
  ///
  /// 渐变用较深的两个橙：白字在 #BF360C 上是 5.6:1，
  /// 原来 #FB8C00 只有 2.37:1（全 App 最该看清的数字反而最糊）。
  Widget _floatingTotalBar(double total, int qty, int kinds) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        gradient: const LinearGradient(
          colors: [AppTheme.totalGradientStart, AppTheme.totalGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        // 阴影偏下，视觉上「浮」在下方列表之上
        boxShadow: [
          BoxShadow(
            color: AppTheme.totalGradientEnd.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 左侧说明可压缩：金额很大（¥1,234.00）或系统字号调大时，
          // 让说明先省略，而不是把这一行挤到溢出。
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${du.dayLabel(_date)} 合计',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
                const SizedBox(height: 2),
                Text('$kinds 种 · $qty 件',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 金额优先保证完整可见；极端情况下按比例缩小而不是截断
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                formatCurrency(total),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
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
