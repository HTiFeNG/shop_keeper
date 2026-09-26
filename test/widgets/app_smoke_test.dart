// 界面冒烟测试（小屏手机 360x640 dp）：
// 启动链路、Tab 切换、关键入口、以及「改动后仍然不报错」的回归保护。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/services/store_service.dart';
import 'package:shop_keeper/theme/app_theme.dart';
import 'package:shop_keeper/utils/date_utils.dart' as du;
import 'package:shop_keeper/utils/format.dart';
import 'package:shop_keeper/widgets/sale_item_card.dart';

import '../helpers/store_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStore();
  });

  testWidgets('启动 / 切 Tab / 打开新增商品表单都不报错，且表单已无库存', (tester) async {
    useSmallPhone(tester);
    await pumpApp(tester);

    // 首页核心入口在位
    expect(find.text('添加商品'), findsOneWidget);

    // 切到「商品」Tab
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    expect(find.text('商品管理'), findsOneWidget);

    // 打开新增商品表单
    // 顶栏动作是纯图标按钮（靠 tooltip 说明用途），不再有「新增」文字
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();
    expect(find.text('新增商品'), findsOneWidget); // AppBar 标题
    expect(find.text('请输入商品名称'), findsOneWidget); // 表单已渲染
    // 库存输入框应彻底消失（旧版这里是「请输入库存数量」）
    expect(find.text('请输入库存数量'), findsNothing);

    // 布局溢出等异常若发生，会在这里暴露
    expect(tester.takeException(), isNull);
  });

  testWidgets('当日合计固定在列表上方：明细很多并滚动后仍然可见', (tester) async {
    useSmallPhone(tester);

    // 造 12 行明细，确保列表一定需要滚动
    final today = du.todayKey();
    final items = [
      for (var i = 0; i < 12; i++)
        {
          'id': 'r$i',
          'name': '商品$i',
          'quantity': 1,
          'unitPrice': 2,
          'totalPrice': 2,
          'isManualMode': false,
          'productId': null,
        },
    ];
    await resetStoreWith({
      'sk_seeded': true, // 跳过首启询问弹窗
      'sk_sales': jsonEncode({
        today: {'date': today, 'items': items},
      }),
    });

    await pumpApp(tester);

    // 12 行 × 2 元 = 24 元，只应出现在悬浮合计条里
    final totalText = formatCurrency(24);
    expect(find.text(totalText), findsOneWidget);

    // 向上滚动明细列表
    await tester.drag(find.text('商品0'), const Offset(0, -400));
    await tester.pumpAndSettle();

    // 合计条在列表之外固定，滚动后仍必须可见
    expect(find.text(totalText), findsOneWidget,
        reason: '当日合计应固定在列表上方，不应随明细滚动消失');
    expect(tester.takeException(), isNull);
  });

  testWidgets('商品页不再显示「进价未填」提示', (tester) async {
    useSmallPhone(tester);
    await resetStoreWith({
      'sk_seeded': true,
      'sk_products': jsonEncode([
        {
          'id': 'SP0001',
          'name': '没填进价的商品',
          'barcode': '',
          'wholesalePrice': 0,
          'purchasePrice': 0, // 进价为空 —— 旧版这里会标注「进价未填」
          'retailPrice': 5,
          'isFavorite': false,
        }
      ]),
    });

    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    expect(find.text('没填进价的商品'), findsOneWidget);
    expect(find.text('进价未填'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('商品页搜索支持按品牌匹配', (tester) async {
    useSmallPhone(tester);
    await resetStoreWith({
      'sk_seeded': true,
      'sk_products': jsonEncode([
        {
          'id': 'SP0001',
          'name': '矿泉水',
          'brand': '农夫山泉',
          'barcode': '6901',
          'wholesalePrice': 0,
          'purchasePrice': 1,
          'retailPrice': 2,
          'isFavorite': false,
        },
        {
          'id': 'SP0002',
          'name': '苏打水',
          'brand': '娃哈哈',
          'barcode': '6902',
          'wholesalePrice': 0,
          'purchasePrice': 1,
          'retailPrice': 3,
          'isFavorite': false,
        },
      ]),
    });

    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    expect(find.text('矿泉水'), findsOneWidget);
    expect(find.text('苏打水'), findsOneWidget);

    // 输入的是品牌名，商品名里并不含「农夫」二字
    await tester.enterText(find.byType(TextField).first, '农夫');
    await tester.pumpAndSettle();

    expect(find.text('矿泉水'), findsOneWidget,
        reason: '应按品牌「农夫山泉」匹配到该商品');
    expect(find.text('苏打水'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('商品页搜索支持拼音首字母（输 kl 找到可乐）', (tester) async {
    useSmallPhone(tester);
    await resetStoreWith({
      'sk_seeded': true,
      'sk_products': jsonEncode([
        {
          'id': 'SP0001',
          'name': '可乐',
          'barcode': '',
          'wholesalePrice': 0,
          'purchasePrice': 1,
          'retailPrice': 3,
          'isFavorite': false,
        },
        {
          'id': 'SP0002',
          'name': '矿泉水',
          'barcode': '',
          'wholesalePrice': 0,
          'purchasePrice': 1,
          'retailPrice': 2,
          'isFavorite': false,
        },
      ]),
    });

    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'kl');
    await tester.pumpAndSettle();

    expect(find.text('可乐'), findsOneWidget, reason: '拼音首字母 kl 应命中「可乐」');
    expect(find.text('矿泉水'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('欠账本可以从「更多」菜单进入并渲染', (tester) async {
    useSmallPhone(tester);
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('欠账本'));
    await tester.pumpAndSettle();

    expect(find.text('欠账本'), findsOneWidget);
    expect(find.text('还没收回来的钱'), findsOneWidget);
    expect(find.text('没有未结清的欠账'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨端同步设置页可以从「更多」菜单进入并渲染', (tester) async {
    // 这一页内容较高，用加高的视口避免依赖滚动定位（滚动会让断言变脆）
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跨端同步（坚果云）'));
    await tester.pumpAndSettle();

    expect(find.text('跨端同步'), findsOneWidget);
    expect(find.text('怎么拿到应用密码'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('上传到云端（本机 → 云端）'), findsOneWidget);
    expect(find.text('从云端恢复（云端 → 本机）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('查账页可以从首页搜索图标进入并渲染', (tester) async {
    useSmallPhone(tester);
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.manage_search));
    await tester.pumpAndSettle();

    expect(find.text('查账'), findsOneWidget);
    expect(find.text('这段时间没有记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记账后视图自动滚到新增的那一行', (tester) async {
    useSmallPhone(tester);

    // 商品0..商品23；其中 商品1..商品8 当天已有明细（8 行，远超一屏）
    final products = [
      for (var i = 0; i < 24; i++)
        {
          'id': 'SP${(i + 1).toString().padLeft(4, '0')}',
          'name': '商品$i',
          'barcode': '',
          'wholesalePrice': 0,
          'purchasePrice': 1,
          'retailPrice': 2,
          'isFavorite': false,
        },
    ];
    final today = du.todayKey();
    final existing = [
      for (var i = 1; i <= 8; i++)
        {
          'id': 'r$i',
          'name': '商品$i',
          'quantity': 1,
          'unitPrice': 2,
          'totalPrice': 2,
          'isManualMode': false,
          'productId': 'SP${(i + 1).toString().padLeft(4, '0')}',
        },
    ];
    await resetStoreWith({
      'sk_seeded': true,
      'sk_products': jsonEncode(products),
      'sk_sales': jsonEncode({
        today: {'date': today, 'items': existing},
      }),
    });

    await pumpApp(tester);

    // 商品0 当天还没有明细 → 添加它会追加到明细列表末尾（视口之外）
    await tester.tap(find.text('添加商品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('商品0').last);
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('商品0'),
      matching: find.byType(SaleItemCard),
    );
    expect(row, findsOneWidget);

    final screenH =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final rect = tester.getRect(row);
    expect(rect.top, lessThan(screenH),
        reason: '新增在列表末尾的行应被自动滚动到可视区域内');
    expect(rect.bottom, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据层单例在 App 启动后处于 ready 状态', (tester) async {
    useSmallPhone(tester);
    await pumpApp(tester);
    expect(StoreService.instance.ready, isTrue);
  });

  // ==================== 4.1：标题栏 / 分类交互的回归保护 ====================

  testWidgets('商品页标题完整显示，不会被右侧按钮挤成「商品…」', (tester) async {
    useSmallPhone(tester);
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('商品管理'),
    );
    expect(title, findsOneWidget);

    // 直接用渲染对象判断「有没有被截断」：Text 设了 maxLines + ellipsis 时，
    // 一旦可用宽度不够，RenderParagraph 会把 didExceedMaxLines 置为 true。
    final para = tester.renderObject<RenderParagraph>(title);
    expect(para.didExceedMaxLines, isFalse,
        reason: '标题被挤压截断了（旧版这里会显示成「商品…」）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('商品页与其他页共用同一套顶栏标题样式', (tester) async {
    useSmallPhone(tester);
    await pumpApp(tester);

    // 营业额页（Tab 1）。限定在 AppBar 内：底部导航栏的标签也叫「营业额」。
    final salesTitle = tester.renderObject<RenderParagraph>(find.descendant(
      of: find.byType(AppBar),
      matching: find.text('营业额'),
    ));
    final salesSize = salesTitle.text.style?.fontSize;
    expect(salesSize, AppTheme.fontAppBarTitle);

    // 商品页（Tab 2）
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    final productTitle = tester.renderObject<RenderParagraph>(find.descendant(
      of: find.byType(AppBar),
      matching: find.text('商品管理'),
    ));
    expect(productTitle.text.style?.fontSize, salesSize,
        reason: '两个主线页面的标题字号必须一致，否则切页时标题会「跳」一下');
  });

  testWidgets('点商品行的分类标签 → 选分类，两次点击完成改分类', (tester) async {
    useSmallPhone(tester);
    await resetStoreWith({
      'sk_seeded': true,
      'sk_products': jsonEncode([
        {
          'id': 'SP0001',
          'name': '矿泉水',
          'category': '',
          'brand': '农夫山泉',
          'barcode': '',
          'wholesalePrice': 0,
          'purchasePrice': 1,
          'retailPrice': 2,
          'isFavorite': false,
        }
      ]),
      'sk_categories': <String>['饮料', '零食'],
    });
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    // 第一次点击：商品行上的分类标签（此时是「未分类」）
    // 注意分类 Chips 里那个是「未分类（1）」，带计数，不会和它撞上
    await tester.tap(find.text('未分类'));
    await tester.pumpAndSettle();

    // 分类选择面板弹出
    expect(find.textContaining('归到哪个分类'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);

    // 第二次点击：面板里选「饮料」
    await tester.tap(find.descendant(
      of: sheet,
      matching: find.text('饮料'),
    ));
    await tester.pumpAndSettle();

    expect(StoreService.instance.findById('SP0001')!.category, '饮料');
    expect(find.text('已归到「饮料」'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类「管理」入口打开管理面板，可用拖拽排序', (tester) async {
    useSmallPhone(tester);
    await resetStoreWith({
      'sk_seeded': true,
      'sk_categories': <String>['饮料', '零食'],
    });
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    // 分类栏的「管理」现在是纯图标按钮（带 tooltip），点图标本身
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('管理分类'), findsOneWidget);
    expect(find.textContaining('拖动'), findsOneWidget,
        reason: '要明确告诉用户「按住右侧手柄拖动」，否则中老年用户不会去试');
    // 每行都有改名 / 删除入口
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('营业额明细行会显示品牌，同名商品可区分', (tester) async {
    useSmallPhone(tester);
    final today = du.todayKey();
    await resetStoreWith({
      'sk_seeded': true,
      'sk_products': jsonEncode([
        {
          'id': 'SP0001',
          'name': '矿泉水',
          'brand': '农夫山泉',
          'barcode': '',
          'wholesalePrice': 0,
          'purchasePrice': 1,
          'retailPrice': 2,
          'isFavorite': false,
        }
      ]),
      // 老明细：有 productId 但没有 brand 快照，考验回查兜底
      'sk_sales': jsonEncode({
        today: {
          'date': today,
          'items': [
            {
              'id': 'r1',
              'name': '矿泉水',
              'quantity': 1,
              'unitPrice': 2,
              'totalPrice': 2,
              'isManualMode': false,
              'productId': 'SP0001',
            }
          ],
        },
      }),
    });
    await pumpApp(tester);

    // 商品名在明细卡片里是输入框（EditableText），而首页「最近常卖」快捷条
    // 也有一份同名文字 —— 所以限定在明细卡片内断言，别跟别处混。
    expect(
      find.descendant(
          of: find.byType(SaleItemCard), matching: find.text('矿泉水')),
      findsOneWidget,
    );
    expect(find.text('农夫山泉'), findsOneWidget,
        reason: '老明细没有品牌快照，也要能按 productId 回查显示出来');
    expect(tester.takeException(), isNull);
  });
}
