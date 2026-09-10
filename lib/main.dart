import 'package:flutter/material.dart';

import 'pages/root_page.dart';
import 'theme/app_theme.dart';

void main() {
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
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system, // 深浅色跟随系统（浅色精致优先）
      home: const RootPage(),
    );
  }
}
