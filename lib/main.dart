import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/root_page.dart';
import 'theme/app_theme.dart';

void main() {
  // 状态栏图标默认用深色（配合下方锁定的浅色主题）。
  // 扫码页是黑底，它自己的 AppBar 会覆盖成浅色图标，不受此处影响。
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  runApp(const ShopKeeperApp());
}

/// 店铺管家：商品管理 × 营业额记录 合并 App（Android + Web）。
class ShopKeeperApp extends StatelessWidget {
  const ShopKeeperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '店铺管家',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 固定浅色：本 App 只有这一套为「中老年店主体验」设计的暖色浅色主题。
      // 注意：不要改回 ThemeMode.system —— 页面颜色是硬编码浅色，
      // 一旦跟随系统切深色，Material 组件（导航栏 / 弹窗 / 输入框 / 默认图标）
      // 会单独变深，出现「半深半浅」的错乱配色，夜间尤其刺眼。
      themeMode: ThemeMode.light,
      home: const RootPage(),
    );
  }
}
