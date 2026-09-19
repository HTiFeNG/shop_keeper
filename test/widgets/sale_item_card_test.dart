// 销售明细卡片测试：计价方式切换（零售 ⇄ 批发）、手动标记。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/models/product.dart';
import 'package:shop_keeper/models/sale.dart';
import 'package:shop_keeper/widgets/sale_item_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('填过批发价的商品：卡片出现「零售价」标签，点一下切成批发', (tester) async {
    final p = Product(
      id: 'SP0001',
      name: '整箱矿泉水',
      retailPrice: 2,
      wholesalePrice: 1.5,
      purchasePrice: 1,
    );
    SaleItem? changed;

    await tester.pumpWidget(_wrap(SaleItemCard(
      item: SaleItem.fromProduct(p),
      onChanged: (v) => changed = v,
      onDelete: () {},
    )));

    expect(find.text('零售价'), findsOneWidget);

    await tester.tap(find.text('零售价'));
    await tester.pump();

    expect(changed, isNotNull);
    expect(changed!.priceMode, SalePriceMode.wholesale);
    expect(changed!.unitPrice, 1.5);
    expect(changed!.totalPrice, 1.5);
  });

  testWidgets('已在批发价：标签显示「批发价」，再点切回零售', (tester) async {
    final p = Product(
      id: 'SP0001',
      name: '整箱矿泉水',
      retailPrice: 2,
      wholesalePrice: 1.5,
    );
    SaleItem? changed;

    await tester.pumpWidget(_wrap(SaleItemCard(
      item: SaleItem.fromProduct(p, mode: SalePriceMode.wholesale),
      onChanged: (v) => changed = v,
      onDelete: () {},
    )));

    expect(find.text('批发价'), findsOneWidget);

    await tester.tap(find.text('批发价'));
    await tester.pump();

    expect(changed!.priceMode, SalePriceMode.retail);
    expect(changed!.unitPrice, 2);
  });

  testWidgets('没填批发价的商品 / 手输行：不出现计价切换入口', (tester) async {
    final noWholesale = Product(id: 'SP0001', name: '没批发价', retailPrice: 5);
    await tester.pumpWidget(_wrap(SaleItemCard(
      item: SaleItem.fromProduct(noWholesale),
      onChanged: (_) {},
      onDelete: () {},
    )));
    expect(find.text('零售价'), findsNothing);
    expect(find.text('批发价'), findsNothing);

    // 手输行（没有关联商品）
    await tester.pumpWidget(_wrap(SaleItemCard(
      item: SaleItem(id: 'm1', name: '散装糖', quantity: 1, unitPrice: 2, totalPrice: 2),
      onChanged: (_) {},
      onDelete: () {},
    )));
    expect(find.text('零售价'), findsNothing);
    expect(find.text('批发价'), findsNothing);
  });

  testWidgets('手动改过总价：出现「手动」标记', (tester) async {
    final p = Product(id: 'SP0001', name: '可乐', retailPrice: 3);
    await tester.pumpWidget(_wrap(SaleItemCard(
      item: SaleItem.fromProduct(p)
        ..isManualMode = true
        ..totalPrice = 5,
      onChanged: (_) {},
      onDelete: () {},
    )));

    expect(find.text('手动'), findsOneWidget);
    expect(find.text('零售价'), findsNothing); // 没填批发价 → 无切换入口
  });

  testWidgets('删除按钮回调生效', (tester) async {
    var deleted = false;
    await tester.pumpWidget(_wrap(SaleItemCard(
      item: SaleItem(id: 'm1', name: 'X', quantity: 1, unitPrice: 1, totalPrice: 1),
      onChanged: (_) {},
      onDelete: () => deleted = true,
    )));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(deleted, isTrue);
  });
}
