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
  static const Color warningYellow = Color(0xFFF9A825);

  /// 低库存橙（0 < stock ≤ 3）
  static const Color lowStockOrange = Color(0xFFF57C00);

  /// 负库存红
  static const Color negativeStockRed = Color(0xFFC62828);

  /// 浅橙（图表普通柱 / 选中背景）
  static const Color chartOrange = Color(0xFFFB8C00);

  /// 图表峰值高亮（深橙）
  static const Color chartPeak = Color(0xFFE65100);

  /// 主文本
  static const Color textPrimary = Color(0xFF33302B);

  /// 次要文本
  static const Color textSecondary = Color(0xFF8A857E);

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

  /// 辅助文字
  static const double fontCaption = 12;

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
              color: primary,
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

  /// 深色主题（P1-5 顺带支持，使用 Material 默认 dark scheme）
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          primary: const Color(0xFFFFA040),
          brightness: Brightness.dark,
        ),
        fontFamilyFallback: const [
          'sans-serif',
          'Roboto',
          'PingFang SC',
          'Microsoft YaHei',
        ],
      );
}

/// 宽屏断点：> 720 用表格式 / 侧栏布局，否则卡片式 / Chips。
const double kWideBreakpoint = 720;
