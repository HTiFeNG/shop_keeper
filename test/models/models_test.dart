// 数据模型单元测试：序列化往返、字段语义、边界值。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/models/credit.dart';
import 'package:shop_keeper/models/product.dart';
import 'package:shop_keeper/models/sale.dart';

void main() {
  group('Product', () {
    test('CSV 表头不含库存列（库存功能已移除）', () {
      expect(Product.csvHeader.first, '编号');
      expect(Product.csvHeader, isNot(contains('库存')));
    });

    test('CSV 行 → 模型：非法数字一律归零', () {
      final p = Product.fromCsvRow(
          ['SP0001', '怪价商品', '', '', '', 'Infinity', 'NaN', '1e400']);
      expect(p.wholesalePrice, 0);
      expect(p.purchasePrice, 0);
      expect(p.retailPrice, 0);
      // 非有限数进不了模型，jsonEncode 才不会在保存时永久失败
      expect(() => jsonEncode([p.toJson()]), returnsNormally);
    });

    test('模型 → CSV 行 → 模型 往返一致', () {
      final p = Product(
        id: 'SP0002',
        name: '牙膏',
        category: '日化',
        brand: '云南白药',
        barcode: '6900002',
        wholesalePrice: 8,
        purchasePrice: 9.9,
        retailPrice: 12.5,
        isFavorite: true,
      );
      final back = Product.fromCsvRow(p.toCsvRow());
      expect(back.id, p.id);
      expect(back.name, p.name);
      expect(back.wholesalePrice, p.wholesalePrice);
      expect(back.purchasePrice, p.purchasePrice);
      expect(back.retailPrice, p.retailPrice);
    });

    test('JSON 往返：缺失字段用安全默认值', () {
      final p = Product.fromJson({'id': 'SP0003', 'name': '只有名字'});
      expect(p.category, '');
      expect(p.wholesalePrice, 0);
      expect(p.isFavorite, isFalse);
    });
  });

  group('SaleItem', () {
    test('行 id 唯一：同毫秒内连续生成 2000 个不重复', () {
      final ids = {for (var i = 0; i < 2000; i++) SaleItem.newId()};
      expect(ids.length, 2000);
    });

    test('fromProduct 零售：带零售价 + 进价快照', () {
      final p = Product(
          id: 'SP0001', name: '牛奶', retailPrice: 3.5, purchasePrice: 2.2);
      final it = SaleItem.fromProduct(p);
      expect(it.unitPrice, 3.5);
      expect(it.totalPrice, 3.5);
      expect(it.costPrice, 2.2);
      expect(it.priceMode, SalePriceMode.retail);
      expect(it.canSwitchPriceMode, isFalse); // 没填批发价 → 不显示切换入口
    });

    test('fromProduct 批发：用批发价，并保存两套价以便来回切', () {
      final p = Product(
          id: 'SP0001',
          name: '矿泉水',
          retailPrice: 2,
          wholesalePrice: 1.5,
          purchasePrice: 1);
      final it = SaleItem.fromProduct(p, mode: SalePriceMode.wholesale);
      expect(it.unitPrice, 1.5);
      expect(it.priceMode, SalePriceMode.wholesale);
      expect(it.canSwitchPriceMode, isTrue);
      expect(it.retailPrice, 2);

      // 切回零售
      final back = it.withPriceMode(SalePriceMode.retail);
      expect(back.unitPrice, 2);
      expect(back.totalPrice, 2);
      expect(back.priceMode, SalePriceMode.retail);
      expect(back.isManualMode, isFalse);
    });

    test('选了批发但商品没填批发价：退回零售价，不产生 0 元账', () {
      final p = Product(id: 'SP0001', name: '没批发价', retailPrice: 5);
      final it = SaleItem.fromProduct(p, mode: SalePriceMode.wholesale);
      expect(it.unitPrice, 5);
      expect(it.priceMode, SalePriceMode.retail);
    });

    test('withPriceMode 按数量重算总价并恢复自动联动', () {
      final p = Product(
          id: 'SP0001', name: '整箱奶', retailPrice: 60, wholesalePrice: 48);
      final it = SaleItem.fromProduct(p)
        ..quantity = 3
        ..isManualMode = true
        ..totalPrice = 100;
      final w = it.withPriceMode(SalePriceMode.wholesale);
      expect(w.totalPrice, 144); // 48 × 3
      expect(w.isManualMode, isFalse);
    });

    test('JSON 往返：计价方式与两套价快照都保留', () {
      final p = Product(
          id: 'SP0001', name: '可乐', retailPrice: 3, wholesalePrice: 2.4);
      final it = SaleItem.fromProduct(p, mode: SalePriceMode.wholesale);
      final back = SaleItem.fromJson(jsonDecode(jsonEncode(it.toJson())));
      expect(back.priceMode, SalePriceMode.wholesale);
      expect(back.wholesalePrice, 2.4);
      expect(back.retailPrice, 3);
    });

    test('旧数据没有 priceMode 字段：按零售处理，不崩', () {
      final it = SaleItem.fromJson({
        'id': 'old1',
        'name': '老数据',
        'quantity': 2,
        'unitPrice': 5,
        'totalPrice': 10,
      });
      expect(it.priceMode, SalePriceMode.retail);
      expect(it.canSwitchPriceMode, isFalse);
    });

    test('brand 快照：fromProduct 带入品牌，JSON 往返保留', () {
      final p = Product(
          id: 'SP0001', name: '矿泉水', brand: '农夫山泉', retailPrice: 2);
      final it = SaleItem.fromProduct(p);
      expect(it.brand, '农夫山泉');
      final back = SaleItem.fromJson(jsonDecode(jsonEncode(it.toJson())));
      expect(back.brand, '农夫山泉');
    });

    test('copy 不会丢品牌', () {
      final it = SaleItem(id: 'x', name: '水', brand: '娃哈哈');
      final c = it.copy()..quantity = 3;
      expect(c.brand, '娃哈哈');
      expect(c.quantity, 3);
    });

    test('4.0.0 之前的老明细没有 brand 字段：读成空串，其它字段照旧', () {
      final it = SaleItem.fromJson({
        'id': 'old1',
        'name': '矿泉水',
        'quantity': 1,
        'unitPrice': 2,
        'totalPrice': 2,
        'productId': 'SP0001',
      });
      expect(it.brand, '');
      expect(it.name, '矿泉水');
      expect(it.productId, 'SP0001');
    });
  });

  group('Credit（欠账）', () {
    test('JSON 往返一致', () {
      const c = Credit(
        id: 'c1',
        customer: '王婶',
        amount: 25.5,
        date: '2026-07-01',
        note: '两包烟',
      );
      final back = Credit.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back.customer, '王婶');
      expect(back.amount, 25.5);
      expect(back.note, '两包烟');
      expect(back.settled, isFalse);
    });

    test('挂账天数与逾期判断', () {
      final c = Credit(
        id: 'c1',
        customer: '王婶',
        amount: 10,
        date: '2026-07-01',
      );
      expect(c.ageInDays(now: DateTime(2026, 7, 11)), 10);
      expect(c.isOverdue(30, now: DateTime(2026, 7, 11)), isFalse);
      expect(c.isOverdue(10, now: DateTime(2026, 7, 11)), isTrue);
    });

    test('已结清的账不再算逾期，账龄按结清日冻结', () {
      final c = Credit(
        id: 'c1',
        customer: '王婶',
        amount: 10,
        date: '2026-07-01',
        settled: true,
        settledDate: '2026-07-05',
      );
      expect(c.isOverdue(3, now: DateTime(2027, 1, 1)), isFalse);
      expect(c.ageInDays(now: DateTime(2027, 1, 1)), 4);
    });

    test('撤销结清会清掉结清日期', () {
      final c = Credit(
        id: 'c1',
        customer: '王婶',
        amount: 10,
        date: '2026-07-01',
        settled: true,
        settledDate: '2026-07-05',
      );
      final back = c.copyWith(settled: false, clearSettledDate: true);
      expect(back.settled, isFalse);
      expect(back.settledDate, isNull);
    });

    test('日期非法时账龄退回 0，不抛异常', () {
      const c = Credit(id: 'c1', customer: 'x', amount: 1, date: '坏日期');
      expect(c.ageInDays(), 0);
    });
  });
}
