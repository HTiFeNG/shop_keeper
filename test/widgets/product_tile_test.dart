// 商品列表项：品牌的呈现方式、条码完整性、可直接点的分类入口、批量模式下的行为差异。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/models/product.dart';
import 'package:shop_keeper/widgets/product_tile.dart';

import '../helpers/store_test_env.dart';

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    required Product product,
    VoidCallback? onChangeCategory,
    VoidCallback? onSelectToggle,
  }) async {
    // 用 360×640 的真实小屏。默认测试视口是 800×600，比真机宽得多，
    // 会**掩盖**商品行右侧空间不足导致的溢出 —— 这个坑真的漏过一次
    // （在 app_smoke 里才被 360 视口抓到）。
    useSmallPhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductTile(
          product: product,
          onTap: () {},
          onDelete: () {},
          onChangeCategory: onChangeCategory,
          onSelectToggle: onSelectToggle,
        ),
      ),
    ));
  }

  testWidgets('品牌以独立标签显示，不再被长条码挤掉', (tester) async {
    await pumpTile(
      tester,
      product: Product(
        id: 'SP0001',
        name: '矿泉水',
        brand: '农夫山泉',
        barcode: '6901234567890',
        retailPrice: 2,
      ),
    );
    expect(find.text('矿泉水'), findsOneWidget);
    expect(find.text('农夫山泉'), findsOneWidget);
    // 回归点：品牌以前是拼在「条码：<13 位>」后面的纯文本，而这一列在
    // 360dp 屏上只有约 100dp —— 条码自己就占满了，品牌永远被省略号吃掉。
    // 现在条码独占一整行，可以完整显示。
    expect(find.text('6901234567890'), findsOneWidget);
  });

  testWidgets('品牌与分类同时存在：并排显示，不溢出', (tester) async {
    await pumpTile(
      tester,
      product: Product(
        id: 'SP0001',
        name: '矿泉水',
        brand: '农夫山泉',
        category: '饮料',
        retailPrice: 2,
      ),
      onChangeCategory: () {},
    );
    // 标签现在独占第二行（整行宽），两者能并排放下 —— 之前挤在第一行时
    // 只有约 90dp 可用，必然换行甚至溢出（组件测试里实测溢出过 24px）
    expect(tester.takeException(), isNull);
    expect(find.text('农夫山泉'), findsOneWidget);
    expect(find.text('饮料'), findsOneWidget);
  });

  testWidgets('品牌标签与分类标签尺寸一致（不能一大一小）', (tester) async {
    await pumpTile(
      tester,
      product: Product(
        id: 'SP0001',
        name: '矿泉水',
        brand: '农夫山泉',
        category: '饮料',
        retailPrice: 2,
      ),
      onChangeCategory: () {},
    );
    // 用户实际用过后反馈的问题：品牌标签当时是 21dp 高的 BrandTag，而分类标签
    // 是 32dp 高的自绘容器 —— 并排站着就是一大一小。现在两者共用同一个 _tag
    // 容器（同高 / 同内边距 / 同圆角 / 同字号 / 同图标尺寸），必须严格等高。
    final brand = tester.getSize(find.byKey(const ValueKey('tag-农夫山泉')));
    final category = tester.getSize(find.byKey(const ValueKey('tag-饮料')));
    expect(brand.height, category.height,
        reason: '两个标签并排显示，高度必须完全一致');
  });

  testWidgets('没填条码时不显示条码行，不占位置', (tester) async {
    await pumpTile(
      tester,
      product: Product(id: 'SP0001', name: '矿泉水', retailPrice: 2),
    );
    expect(find.byIcon(Icons.qr_code_2), findsNothing);
  });

  testWidgets('13 位条码完整显示，不被省略号截断', (tester) async {
    await pumpTile(
      tester,
      product: Product(
        id: 'SP0001',
        name: '矿泉水',
        barcode: '6901234567890',
        retailPrice: 2,
      ),
    );
    // 这是本次修复的核心断言：条码此前挤在左列（360dp 屏上约 100dp），
    // 而「条码：<13 位>」自身要约 130dp，永远被截成「条码：6901…」。
    final para =
        tester.renderObject<RenderParagraph>(find.text('6901234567890'));
    expect(para.didExceedMaxLines, isFalse,
        reason: '条码独占整行后，13 位数字必须完整显示');
  });

  testWidgets('点分类标签直接触发改分类（不必先进批量模式）', (tester) async {
    var tapped = 0;
    await pumpTile(
      tester,
      product: Product(
          id: 'SP0001', name: '矿泉水', category: '饮料', retailPrice: 2),
      onChangeCategory: () => tapped++,
    );

    expect(find.text('饮料'), findsOneWidget);
    await tester.tap(find.text('饮料'));
    expect(tapped, 1);
  });

  testWidgets('还没归类的商品，标签显示「未分类」且同样点得动', (tester) async {
    var tapped = 0;
    await pumpTile(
      tester,
      product: Product(id: 'SP0001', name: '矿泉水', retailPrice: 2),
      onChangeCategory: () => tapped++,
    );

    expect(find.text('未分类'), findsOneWidget);
    await tester.tap(find.text('未分类'));
    expect(tapped, 1);
  });

  testWidgets('不传 onChangeCategory 时分类只作展示，点了不会触发任何回调', (tester) async {
    await pumpTile(
      tester,
      product: Product(
          id: 'SP0001', name: '矿泉水', category: '饮料', retailPrice: 2),
      // 模拟「只想看不想改」的调用方
    );
    await tester.tap(find.text('饮料'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量模式下分类标签不可点（整行都是「选中」语义）', (tester) async {
    var categoryTapped = 0;
    var rowTapped = 0;
    await pumpTile(
      tester,
      product: Product(
          id: 'SP0001', name: '矿泉水', category: '饮料', retailPrice: 2),
      onChangeCategory: () => categoryTapped++,
      onSelectToggle: () => rowTapped++,
    );

    await tester.tap(find.text('饮料'));
    expect(categoryTapped, 0, reason: '批量模式下不该改分类');
    expect(rowTapped, 1, reason: '点击应该落到「选中该行」上');
  });

  testWidgets('长分类名 / 长品牌名不会撑破布局', (tester) async {
    await pumpTile(
      tester,
      product: Product(
        id: 'SP0001',
        name: '一个特别特别长的商品名称用来测试换行与省略',
        brand: '一个特别特别长的品牌名称',
        category: '一个特别特别长的分类名称',
        retailPrice: 1234.5,
      ),
      onChangeCategory: () {},
    );
    expect(tester.takeException(), isNull);
  });
}
