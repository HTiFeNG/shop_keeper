import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/root_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ShopKeeperApp());
}

/// 店铺管家：商品管理 × 营业额记录 合并 App（Android + Web）。
///
/// **深浅色跟随系统**（`ThemeMode.system`）。要两件事一起做才成立：
/// 1. 把系统亮度同步给 [AppTheme] —— 页面里的颜色是 `AppTheme.textPrimary`
///    这类静态引用，靠这个全局状态解析出该用哪套色板；
/// 2. 亮度变化时 setState 重建整棵树 —— 静态引用自己不会更新。
///
/// 这也是本类从 StatelessWidget 变成 StatefulWidget 的原因：需要一个能监听
/// `didChangePlatformBrightness` 的地方。
class ShopKeeperApp extends StatefulWidget {
  const ShopKeeperApp({super.key});

  @override
  State<ShopKeeperApp> createState() => _ShopKeeperAppState();
}

class _ShopKeeperAppState extends State<ShopKeeperApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧就要对齐：AppTheme 的默认值是浅色，而系统此刻可能已经是深色
    _syncTheme(_systemIsDark());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // 用户在系统里切了深浅色
    if (_syncTheme(_systemIsDark())) setState(() {});
  }

  bool _systemIsDark() =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;

  /// 把亮度同步给全局色板 + 状态栏图标；返回 true 表示确实变了（需要重建）。
  bool _syncTheme(bool dark) {
    final changed = AppTheme.syncBrightness(dark);
    // 状态栏图标要跟着反色：浅底用深图标、深底用浅图标。
    // （扫码页整页黑底，它自己的 AppBar 会把图标覆盖成浅色，不受这里影响。）
    SystemChrome.setSystemUIOverlayStyle(
      dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );
    return changed;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '店铺管家',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const RootPage(),
    );
  }
}
