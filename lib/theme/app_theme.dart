import 'package:flutter/material.dart';

/// 店铺管家全局视觉规范（唯一颜色 / 字号 / 圆角 / 间距来源）。
///
/// 所有页面引用本文件常量，禁止散落硬编码颜色。
/// 暖色系主题贴合小卖部烟火气；目标用户中老年：字号偏大、触控区 ≥48dp。
abstract final class AppTheme {
  // ==================== 色板 ====================

  /// 主题种子色（暖橙）
  static const Color seed = Color(0xFFF57C00);

  /// 主色（略深一档的橙，用于按钮 / 选中态）
  static const Color primary = Color(0xFFEF6C00);

  /// 页面底色（暖米白）
  static const Color background = Color(0xFFFFF8F0);

  /// 卡片底色
  static const Color cardBackground = Colors.white;

  /// 价格红（沿用基座习惯）
  static const Color priceRed = Color(0xFFE53935);

  /// 成功绿
  static const Color success = Color(0xFF2E7D32);

  /// 警示黄（缺进价提醒）
  /// 警示黄（保留：图表/图标备用）
  static const Color warningYellow = Color(0xFFF9A825);

  /// 低库存橙 —— 库存功能已移除，仅保留常量以免遗漏引用
  static const Color lowStockOrange = Color(0xFFF57C00);

  /// 负库存红
  static const Color negativeStockRed = Color(0xFFC62828);

  /// 浅橙（图表普通柱 / 选中背景）
  static const Color chartOrange = Color(0xFFFB8C00);

  /// 图表峰值高亮（深橙）
  static const Color chartPeak = Color(0xFFE65100);

  /// 日合计卡渐变两端
  ///
  /// 原来是 [chartOrange, primary]，白字对比度仅 2.37:1 / 3.08:1 —— 全 App
  /// 最需要一眼看清的数字反而最不清楚。换成这两个深橙后为 3.79:1 / 5.60:1。
  static const Color totalGradientStart = Color(0xFFE65100);
  static const Color totalGradientEnd = Color(0xFFBF360C);

  /// 主文本
  static const Color textPrimary = Color(0xFF33302B);

  /// 次要文本
  ///
  /// 原值 #8A857E 在白底上只有 3.66:1、米白底 3.48:1，都低于 WCAG AA 正文
  /// 要求的 4.5:1；而它承载着商品行第二行、卡片标签等大量 11-13px 信息，
  /// 正是老花眼用户最难看的部分。加深到 #5F5A54 后为 6.82:1。
  static const Color textSecondary = Color(0xFF5F5A54);

  /// 主色的「文字版」
  ///
  /// [primary] 本身当小字只有 3.08:1，不适合做文字色；需要橙色文字（标签、
  /// 链接、选中态文字）时用这个（白底 4.70:1）。[primary] 继续用于填充、
  /// 图标和指示器。
  static const Color primaryText = Color(0xFFC25100);

  /// 分割线 / 边框
  static const Color divider = Color(0xFFEFE7DC);

  /// 浅橙底（提示条 / Chip 选中底）
  static const Color orangeSurface = Color(0xFFFFF3E0);

  /// 警示黄底（缺进价提示条）
  static const Color warningSurface = Color(0xFFFFFDE7);

  // ==================== 字号 ====================

  /// 页标题
  static const double fontPageTitle = 22;

  /// 区块标题
  static const double fontSectionTitle = 17;

  /// 正文
  static const double fontBody = 15;

  /// 辅助文字（原为 12，对中老年用户偏小；代码里散落的 10/11px 一律并入这里）
  static const double fontCaption = 13;

  /// 日合计大字
  static const double fontBigTotal = 32;

  // ==================== 圆角 / 间距 ====================

  /// 卡片圆角
  static const double radiusCard = 14;

  /// 小圆角（输入框 / Chip）
  static const double radiusSmall = 10;

  /// 内容卡片水平内边距
  static const double pagePadding = 16;

  // ==================== 文本样式 ====================

  static const TextStyle pageTitle = TextStyle(
    fontSize: fontPageTitle,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: fontSectionTitle,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: fontBody,
    color: textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: fontCaption,
    color: textSecondary,
  );

  static const TextStyle bigTotal = TextStyle(
    fontSize: fontBigTotal,
    fontWeight: FontWeight.w700,
    color: primary,
  );

  // ==================== 组件样式 ====================

  /// 白色圆角卡片装饰
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(radiusCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// 浅色主题（唯一来源）
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      primary: primary,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      // 桌面 / Web 上 Material 默认切到 compact 密度，会把 Material 控件的
      // 触控区压到 32-40dp（本主题自己承诺 ≥48dp）。显式钉住标准密度。
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      fontFamilyFallback: const [
        'sans-serif',
        'Roboto',
        'PingFang SC',
        'Microsoft YaHei',
      ],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0.5,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: orangeSurface,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 26);
          }
          return const IconThemeData(color: textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryText,
            );
          }
          return const TextStyle(fontSize: 12, color: textSecondary);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
    );
  }

  // 说明：本类只提供一套浅色主题（light）。
  //
  // 之所以不提供深色主题，是因为全部页面的颜色都直接取自上方常量
  // （米白底 / 白卡片 / 深棕文字），若让 Material 组件跟随系统转深色，
  // 会出现「页面浅、组件深」的错乱配色。故 App 锁定 ThemeMode.light，
  // 详见 lib/main.dart。
}

/// 宽屏断点：> 720 用表格式 / 侧栏布局，否则卡片式 / Chips。
const double kWideBreakpoint = 720;
