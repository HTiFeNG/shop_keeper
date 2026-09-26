// 商品列表项：品牌的呈现方式、可直接点的分类入口、批量模式下的行为差异。
import 'package:flutter/material.dart';
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

  testWidgets('品牌跟在条码同一行显示', (tester) async {
    await pumpTile(
      tester,
      product: Product(
          id: 'SP0001', name: '矿泉水', brand: '农夫山泉', retailPrice: 2),
    );
    expect(find.text('矿泉水'), findsOneWidget);
    // 品牌**不是**独立标签：这一列在 360dp 屏上只有约 100dp，
    // 品牌 + 分类两个标签并排会直接溢出 24px。它并进「条码 · 品牌」一行。
    expect(find.textContaining('农夫山泉'), findsOneWidget);
  });

  testWidgets('没有品牌时那一行只显示条码，不会多出空位', (tester) async {
    await pumpTile(
      tester,
      product: Product(id: 'SP0001', name: '矿泉水', retailPrice: 2),
    );
    expect(find.text('条码：—'), findsOneWidget);
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
