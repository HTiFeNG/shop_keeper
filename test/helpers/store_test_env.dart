import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_keeper/main.dart';
import 'package:shop_keeper/services/nutstore_sync.dart';
import 'package:shop_keeper/services/store_service.dart';

/// 测试公共环境：把全局单例 StoreService 恢复成干净状态。
///
/// 为什么需要它：StoreService 是进程内单例，用例之间会互相污染
/// （上一个用例加的商品会出现在下一个用例的列表里）。
/// 每个 `setUp` 里调用一次 [resetStore] 即可。
Future<void> resetStore({Map<String, Object>? initial}) async {
  SharedPreferences.setMockInitialValues(initial ?? {});
  final store = StoreService.instance;
  await store.load();

  // load() 只负责读盘，这里把所有可变状态显式抹平
  store.products = [];
  store.categories = [];
  store.sales = {};
  store.credits = [];
  store.seeded = false;
  store.droppedOnLoad = 0;
  store.loadError = null;
  store.saveError = null;
  store.hasRestoreSnapshot = false;
  store.lastBackupAt = null;
  store.syncConfig = const NutstoreConfig();
  store.lastSyncAt = null;
  store.lastSyncError = null;
  store.dismissPendingRemote();
}

/// 常规模拟环境：清空存储 + 干净单例
Future<void> resetStoreWith(Map<String, Object> initial) =>
    resetStore(initial: initial);

/// 只设置存储并 load()，**不做内存清理**。
///
/// 专用于「验证 load() 本身的行为」的用例（例如坏数据是否被计入
/// [StoreService.droppedOnLoad] / [StoreService.loadError]）——
/// 那些字段正是 load() 的产物，后续清理会把结论抹掉。
Future<void> loadStoreWith(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  await StoreService.instance.load();
}

/// 小屏手机尺寸（1080x1920 @3x = 360x640 dp，覆盖绝大多数机型）
void useSmallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 启动整个 App 并跳过首启示例数据弹窗。
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ShopKeeperApp());
  await tester.pumpAndSettle();
  // load() 是异步的，首帧回调时 seeded 可能还是 false，故这里做兜底关闭
  if (find.text('从空开始').evaluate().isNotEmpty) {
    await tester.tap(find.text('从空开始'));
    await tester.pumpAndSettle();
  }
}
