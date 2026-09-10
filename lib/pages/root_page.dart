import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/store_service.dart';
import 'product_manage_page.dart';
import 'sales_page.dart';
import 'search_page.dart';

/// 根页面：底部三 Tab（营业额 / 商品 / 搜索）。
///
/// - IndexedStack 保持各页状态，切换不丢失；
/// - 监听 [StoreService.salePrefill]：商品页「记一笔」→ 自动切到营业额首页，
///   由 SalesPage 消费预填（见 SalePage._consumePrefill）。
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;

  /// 上一次按返回键的时间戳（用于「再按一次退出」两级容错）
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    final store = StoreService.instance;
    store.load();
    // 商品页发起「记一笔」→ 切到营业额首页（SalesPage 监听 salePrefill 消费）
    store.salePrefill.addListener(_onPrefill);
  }

  void _onPrefill() {
    if (StoreService.instance.salePrefill.value != null && mounted) {
      setState(() => _tab = 0);
    }
  }

  /// 安卓返回键容错：防止误触直接退出。
  /// - 非营业额 Tab → 切回营业额（不弹提示）；
  /// - 已在营业额 → 首次提示「再按一次退出」，2.5 秒内再按才真正退出。
  void _handleBack() {
    if (_tab != 0) {
      setState(() => _tab = 0);
      _lastBackPress = null;
      return;
    }
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(milliseconds: 2500)) {
      _lastBackPress = null; // 退出前重置，避免退出动画期间误判
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('再按一次退出应用'),
        duration: Duration(seconds: 2),
      ));
  }

  @override
  void dispose() {
    StoreService.instance.salePrefill.removeListener(_onPrefill);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: ListenableBuilder(
          listenable: StoreService.instance,
          builder: (context, _) {
            final store = StoreService.instance;
            if (!store.ready) {
              // 首次加载数据时显示启动画面
              return const Center(child: CircularProgressIndicator());
            }
            return IndexedStack(
              index: _tab,
              children: const [
                SalesPage(),
                ProductManagePage(),
                SearchPage(),
              ],
            );
          },
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          height: 68,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: '营业额',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: '商品',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: '搜索',
            ),
          ],
        ),
      ),
    );
  }
}
