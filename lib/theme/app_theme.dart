import 'package:flutter/material.dart';

/// 店铺管家全局视觉规范（唯一颜色 / 字号 / 圆角 / 间距来源）。
///
/// 所有页面引用本文件，禁止散落硬编码颜色。
/// 暖色系主题贴合小卖部烟火气；目标用户中老年：字号偏大、触控区 ≥48dp。
///
/// **深浅色怎么工作**：颜色不是 `const`，而是按 [_dark] 解析的 **getter**，
/// 所以页面里照旧写 `AppTheme.textPrimary`，不必改成 `Theme.of(context)...`
/// —— 四百多处引用一处都不用动。当前亮度由 [syncBrightness] 同步（见
/// lib/main.dart 的 `didChangePlatformBrightness`），切换时重建整棵树取新值。
///
/// ⚠️ 因此 `AppTheme.<颜色>` **不能再出现在 const 上下文里**：
/// `const TextStyle(color: AppTheme.textPrimary)` 会编译失败，去掉 `const` 即可。
abstract final class AppTheme {
  // ==================== 深浅色状态 ====================

  static bool _dark = false;

  /// 当前是否深色（极少数需要分支的地方用，例如状态栏图标颜色）
  static bool get isDark => _dark;

  /// 由 App 根节点在「启动首帧」与「系统亮度变化」时调用。
  ///
  /// 返回 true 表示亮度确实变了 —— 调用方据此决定要不要 setState 重建整棵树
  /// （页面里是静态引用，不重建就拿不到新颜色）。
  static bool syncBrightness(bool dark) {
    if (_dark == dark) return false;
    _dark = dark;
    return true;
  }

  // ==================== 色板 ====================
  //
  // 浅色：暖米白底 + 白卡片 + 深棕文字。
  // 深色：**暖调**深灰，不用纯黑 —— 纯黑配白字对比过强，夜里长时间盯着反而更累；
  //       卡片比底色亮一档来区分层次（而不是靠阴影，暗底上阴影看不出来）。

  static const Color _lightBackground = Color(0xFFFFF8F0);
  static const Color _darkBackground = Color(0xFF1A1816);

  static const Color _lightCard = Colors.white;
  static const Color _darkCard = Color(0xFF24211E);

  static const Color _lightTextPrimary = Color(0xFF33302B);
  static const Color _darkTextPrimary = Color(0xFFEDE7DF);

  static const Color _lightTextSecondary = Color(0xFF5F5A54);
  static const Color _darkTextSecondary = Color(0xFFA9A29A);

  static const Color _lightPrimaryText = Color(0xFFC25100);
  static const Color _darkPrimaryText = Color(0xFFFFA657);

  static const Color _lightDivider = Color(0xFFEFE7DC);
  static const Color _darkDivider = Color(0xFF37332E);

  static const Color _lightOrangeSurface = Color(0xFFFFF3E0);
  static const Color _darkOrangeSurface = Color(0xFF3A2A18);

  static const Color _lightWarningSurface = Color(0xFFFFFDE7);
  static const Color _darkWarningSurface = Color(0xFF38321A);

  /// 主题种子色（暖橙）。品牌色，深浅共用。
  static const Color seed = Color(0xFFF57C00);

  /// 主色（按钮 / 选中态）。深底上对比度依然够（约 4.5:1），**两套共用同一个值**
  /// —— 按钮在两个模式下变个颜色，用户会以为是两个 App。
  static const Color primary = Color(0xFFEF6C00);

  /// 页面底色
  static Color get background => _dark ? _darkBackground : _lightBackground;

  /// 卡片底色
  static Color get cardBackground => _dark ? _darkCard : _lightCard;

  /// 价格红
  static Color get priceRed =>
      _dark ? const Color(0xFFFF7B72) : const Color(0xFFE53935);

  /// 成功绿
  static Color get success =>
      _dark ? const Color(0xFF6BC46F) : const Color(0xFF2E7D32);

  /// 警示黄（保留：图表 / 图标备用）
  static const Color warningYellow = Color(0xFFF9A825);

  /// 低库存橙 —— 库存功能已移除，仅保留常量以免遗漏引用
  static const Color lowStockOrange = Color(0xFFF57C00);

  /// 负库存红
  static const Color negativeStockRed = Color(0xFFC62828);

  /// 浅橙（图表普通柱 / 选中背景）
  static Color get chartOrange =>
      _dark ? const Color(0xFFFFA657) : const Color(0xFFFB8C00);

  /// 图表峰值高亮
  static Color get chartPeak =>
      _dark ? const Color(0xFFFF8A3D) : const Color(0xFFE65100);

  /// 日合计卡渐变两端。
  ///
  /// 浅色下是深橙（白字对比度 3.79:1 / 5.60:1；比原来的 [chartOrange]+[primary]
  /// 好得多）。深色下压暗一档，既保持「一块突出的暖色」，又不在暗环境里刺眼。
  static Color get totalGradientStart =>
      _dark ? const Color(0xFFC25100) : const Color(0xFFE65100);
  static Color get totalGradientEnd =>
      _dark ? const Color(0xFF8F2D08) : const Color(0xFFBF360C);

  /// 主文本
  static Color get textPrimary => _dark ? _darkTextPrimary : _lightTextPrimary;

  /// 次要文本
  ///
  /// 浅色值的历史：原 #8A857E 在白底只有 3.66:1，低于 WCAG AA 正文要求的
  /// 4.5:1；而它承载着商品行第二行、卡片标签等大量小字，正是老花眼用户最难看
  /// 的部分。加深到 #5F5A54 后为 6.82:1。深色值在 #1A1816 底上约 7.4:1，同样留足余量。
  static Color get textSecondary =>
      _dark ? _darkTextSecondary : _lightTextSecondary;

  /// 主色的「文字版」。[primary] 本身当小字只有 3.08:1，不适合做文字色；
  /// 需要橙色文字（标签 / 链接 / 选中态文字）时用这个。
  static Color get primaryText =>
      _dark ? _darkPrimaryText : _lightPrimaryText;

  /// 分割线 / 边框
  static Color get divider => _dark ? _darkDivider : _lightDivider;

  /// 浅橙底（提示条 / Chip 选中底）
  static Color get orangeSurface =>
      _dark ? _darkOrangeSurface : _lightOrangeSurface;

  /// 警示黄底（缺进价提示条）
  static Color get warningSurface =>
      _dark ? _darkWarningSurface : _lightWarningSurface;

  // ==================== 深色底（扫码页）====================
  //
  // 扫码页整页黑底，与全局深浅模式无关 —— 摄像头取景必须用深底，
  // 所以它用自己那一套，不跟随主题。

  /// 深色底上的弱提示文字 / 图标
  static const Color onDarkHint = Color(0xFFBDBDBD);

  // ==================== 排行榜奖牌色 ====================

  /// 商品排行前三名的名次色（金 / 银 / 铜）。
  /// 深色下换成亮一档的同色相，否则在暗底上几乎看不清。
  static Color get medalGold =>
      _dark ? const Color(0xFFE0A33E) : const Color(0xFF8D5300);
  static Color get medalSilver =>
      _dark ? const Color(0xFFA8B4BC) : const Color(0xFF4E5A61);
  static Color get medalBronze =>
      _dark ? const Color(0xFFC08A5E) : const Color(0xFF6B4A33);

  // ==================== 字号 ====================
  //
  // 全 App 的字号只有这里一处定义，页面里**不要再写字面量**。
  // 历史遗留：散落过 11/12/14/16/20/28/30 共七种值，同一层级的文字在不同
  // 页面大小不一。下面每个值对应一个明确用途，新增界面时挑一个复用。

  /// 页标题
  static const double fontPageTitle = 22;

  /// 顶栏（AppBar）标题
  ///
  /// 统一收在这里的原因：改版前 4 个页面各自写 `style: AppTheme.pageTitle`
  /// （22px），而编辑页 / 扫码页用主题默认的 18px —— 同一个 App 里并存两套
  /// 标题大小，切页时肉眼可见地跳一下。现在所有 AppBar 只写 `Text('标题')`，
  /// 字号由 [AppBarTheme] 统一给。
  static const double fontAppBarTitle = 20;

  /// 统计数值（四宫格 / 汇总条里的数字）
  static const double fontStatValue = 20;

  /// 区块标题
  static const double fontSectionTitle = 17;

  /// 卡片 / 明细行标题
  static const double fontCardTitle = 16;

  /// 正文与按钮文字
  static const double fontBody = 15;

  /// 次要标签（行内小标签、对话框动作按钮）
  static const double fontLabel = 14;

  /// 辅助文字（原为 12，对中老年用户偏小；代码里散落的 10/11px 一律并入这里）
  static const double fontCaption = 13;

  /// 更小的补充说明。
  ///
  /// ⚠️ 低于本类约定的 13px 下限，仅用于扫码页这类深色底上的次要文字 ——
  /// 新增界面不要用它，请直接用 [fontCaption]。
  static const double fontSmall = 12;
  static const double fontMicro = 11;

  /// 卡片主金额大字（日合计 / 欠账未收回总额）
  static const double fontAmountLarge = 28;

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
  //
  // 因为颜色随深浅色变，这几个**不能**再写成 `const TextStyle`。

  static TextStyle get pageTitle => TextStyle(
        fontSize: fontPageTitle,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  /// AppBar 标题样式（全站唯一来源，各页不要自行指定字号）
  static TextStyle get appBarTitle => TextStyle(
        fontSize: fontAppBarTitle,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  static TextStyle get sectionTitle => TextStyle(
        fontSize: fontSectionTitle,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  static TextStyle get body => TextStyle(
        fontSize: fontBody,
        color: textPrimary,
      );

  static TextStyle get caption => TextStyle(
        fontSize: fontCaption,
        color: textSecondary,
      );

  static TextStyle get bigTotal => TextStyle(
        fontSize: fontBigTotal,
        fontWeight: FontWeight.w700,
        color: primary,
      );

  // ==================== 组件样式 ====================

  /// 圆角卡片装饰
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(radiusCard),
        boxShadow: [
          BoxShadow(
            // 深色下反着来：暗底上的黑色投影看不见，反而糊成一团；
            // 改成极淡的白色高光，卡片边缘才「浮」得起来。
            color: _dark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      );

  // ==================== 主题 ====================

  // 只构建一次：ThemeData 的构建不便宜，而 MaterialApp 每次 build 都会读它。
  // static final 是懒初始化，且与 [_dark] 状态无关（见 _buildTheme 的说明）。
  static final ThemeData _lightTheme = _buildTheme(dark: false);
  static final ThemeData _darkTheme = _buildTheme(dark: true);

  /// 浅色主题
  static ThemeData get light => _lightTheme;

  /// 深色主题
  static ThemeData get dark => _darkTheme;

  /// 按给定亮度构建主题。
  ///
  /// ⚠️ 这里刻意**不读上面那些 getter** —— 它们读的是全局 [_dark]，
  /// 而构建 light 主题时 [_dark] 可能已经是 true，会拿错颜色。
  /// 必须按参数取固定的那套值。
  static ThemeData _buildTheme({required bool dark}) {
    final bg = dark ? _darkBackground : _lightBackground;
    final card = dark ? _darkCard : _lightCard;
    final fg = dark ? _darkTextPrimary : _lightTextPrimary;
    final fgMuted = dark ? _darkTextSecondary : _lightTextSecondary;
    final accentText = dark ? _darkPrimaryText : _lightPrimaryText;
    final line = dark ? _darkDivider : _lightDivider;
    final chip = dark ? _darkOrangeSurface : _lightOrangeSurface;

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: primary,
      surface: card,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
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
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        foregroundColor: fg,
        elevation: 0.5,
        // 滚动内容顶到顶栏下方时不要给顶栏染一层色：全 App 只有一套底色，
        // 一旦 Material 3 按默认叠 surfaceTint，切页时顶部会出现深浅不一的
        // 色块，正是「风格不统一」的来源之一。
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        // 标题统一左对齐：桌面端与安卓大屏更自然，也和商品页原来的自绘标题一致
        centerTitle: false,
        titleSpacing: 16,
        // 字号来源在这（页面只写 Text('标题')，不写 style）
        titleTextStyle: TextStyle(
          fontSize: fontAppBarTitle,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: chip,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 26);
          }
          return IconThemeData(color: fgMuted, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: fontSmall,
              fontWeight: FontWeight.w600,
              color: accentText,
            );
          }
          return TextStyle(fontSize: fontSmall, color: fgMuted);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          minimumSize: const Size(0, 48),
          textStyle:
              const TextStyle(fontSize: fontBody, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
        ),
      ),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: DividerThemeData(color: line, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(color: fgMuted),
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
      // 弹窗 / 底部面板跟着卡片色走，否则深色模式下会闪一下白底。
      // （Material 3 里这两类默认取 colorScheme 的 surface 系，显式钉一下更稳。）
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

/// 宽屏断点：> 720 用表格式 / 侧栏布局，否则卡片式 / Chips。
const double kWideBreakpoint = 720;
