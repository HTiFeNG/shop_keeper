// StoreService 单元测试：合并记账、商品管理、加载容错、导入导出。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/models/product.dart';
import 'package:shop_keeper/models/sale.dart';
import 'package:shop_keeper/services/store_service.dart';
import 'package:shop_keeper/utils/csv_codec.dart';
import 'package:shop_keeper/utils/date_utils.dart' as du;

import '../helpers/store_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStore();
  });

  group('recordSaleFromProduct（合并记账）', () {
    test('重复添加同商品：数量合并、只留一行、金额按单价累加', () {
      final store = StoreService.instance;
      final p = Product(id: 'SP1001', name: '农夫山泉', retailPrice: 2);
      store.addProduct(p);

      store.recordSaleFromProduct('2026-07-01', p);
      store.recordSaleFromProduct('2026-07-01', p);
      store.recordSaleFromProduct('2026-07-01', p);

      final items = store.itemsOf('2026-07-01');
      expect(items.length, 1); // 合并为一行
      expect(items.first.quantity, 3);
      expect(items.first.totalPrice, closeTo(6, 0.001)); // 3 × 2
    });

    test('手动改过总价的行再合并：金额按原单价等比放大，不再漏记', () {
      final store = StoreService.instance;
      final p = Product(id: 'SP1002', name: '可乐', retailPrice: 3);
      store.addProduct(p);

      // 先手动建一行：数量 1，手动改总价 5（抹零）
      store.upsertSaleItem(
          '2026-07-01',
          SaleItem(
              id: 'manual1',
              name: '可乐',
              quantity: 1,
              unitPrice: 3,
              totalPrice: 5,
              isManualMode: true,
              productId: 'SP1002'));

      store.recordSaleFromProduct('2026-07-01', p);

      final items = store.itemsOf('2026-07-01');
      expect(items.length, 1);
      expect(items.first.quantity, 2);
      expect(items.first.isManualMode, isTrue);
      // 旧实现总价一直是 5：件数 +1 但营业额一分没涨，等于漏记
      expect(items.first.totalPrice, closeTo(10, 0.001));
      // 单价要同步成「实际单价」，让 单价 × 数量 = 总价 重新自洽。
      // 否则单价还停在商品原价 ¥3 上，用户之后一按数量加减就会把 ¥10 改掉。
      expect(items.first.unitPrice, closeTo(5, 0.001));
      expect(items.first.unitPrice * items.first.quantity,
          closeTo(items.first.totalPrice, 0.001));
    });

    test('零售与批发不互相合并（两套价是两笔账）', () {
      final store = StoreService.instance;
      final p = Product(
          id: 'SP1003', name: '整箱可乐', retailPrice: 3, wholesalePrice: 2.4);
      store.addProduct(p);

      store.recordSaleFromProduct('2026-07-01', p);
      store.recordSaleFromProduct('2026-07-01', p,
          mode: SalePriceMode.wholesale);

      final items = store.itemsOf('2026-07-01');
      expect(items.length, 2);
      expect(items[0].unitPrice, 3);
      expect(items[0].priceMode, SalePriceMode.retail);
      expect(items[1].unitPrice, 2.4);
      expect(items[1].priceMode, SalePriceMode.wholesale);
      expect(store.dayTotal('2026-07-01'), closeTo(5.4, 0.001));
    });

    test('同计价方式重复扫码仍然合并成一行', () {
      final store = StoreService.instance;
      final p = Product(id: 'SP1004', name: '啤酒', retailPrice: 4);
      store.addProduct(p);

      store.recordSaleFromProduct('2026-07-01', p);
      store.recordSaleFromProduct('2026-07-01', p);
      expect(store.itemsOf('2026-07-01').length, 1);
      expect(store.itemsOf('2026-07-01').first.quantity, 2);
    });
  });

  group('商品管理', () {
    test('条码重复会被拒绝（否则扫码永远只命中第一个）', () {
      final store = StoreService.instance;
      expect(
          store.addProduct(
              Product(id: 'SP0001', name: 'A', barcode: '6900001')),
          isTrue);
      expect(
          store.addProduct(
              Product(id: 'SP0002', name: 'B', barcode: '6900001')),
          isFalse);
      expect(store.products.length, 1);
      // 空条码不参与判重
      expect(store.addProduct(Product(id: 'SP0003', name: 'C')), isTrue);
    });

    test('商品编号不回收：删掉编号最大的商品后新编号不撞老账', () {
      final store = StoreService.instance;
      final id1 = store.nextId();
      store.addProduct(Product(id: id1, name: 'A'));
      final id2 = store.nextId();
      store.addProduct(Product(id: id2, name: 'B'));

      store.deleteProduct(id2);
      final id3 = store.nextId();
      // 旧实现按「现有最大编号 +1」生成 → 这里会重新发出 id2，
      // 让历史销售里指向 id2 的行静默改指到新商品
      expect(id3, isNot(id2));
    });

    test('编辑商品不会误清星标', () {
      final store = StoreService.instance;
      final p = Product(id: 'SP0001', name: '常卖货', isFavorite: true);
      store.addProduct(p);
      // 编辑页不带 isFavorite 时以内存现值为准
      store.updateProduct(Product(id: 'SP0001', name: '常卖货(改)')); 
      expect(store.products.first.isFavorite, isTrue);
      expect(store.products.first.name, '常卖货(改)');
    });

    test('批量改分类 / 批量删除', () {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: 'A'));
      store.addProduct(Product(id: 'SP0002', name: 'B'));
      store.batchSetCategory(['SP0001', 'SP0002'], '饮料');
      expect(store.products.every((p) => p.category == '饮料'), isTrue);
      store.batchDelete(['SP0001']);
      expect(store.products.single.id, 'SP0002');
    });

    test('分类重命名会联动商品，删除分类会把商品归入未分类', () {
      final store = StoreService.instance;
      store.addCategory('饮料');
      store.addProduct(Product(id: 'SP0001', name: 'A', category: '饮料'));
      store.renameCategory('饮料', '酒水饮料');
      expect(store.products.first.category, '酒水饮料');
      store.deleteCategory('酒水饮料');
      expect(store.products.first.category, kCategoryNone);
    });

    test('最近常卖：按售出件数排序，只含卖过的商品', () {
      final store = StoreService.instance;
      final a = Product(id: 'SP0001', name: '卖得多', retailPrice: 1);
      final b = Product(id: 'SP0002', name: '卖得少', retailPrice: 1);
      final c = Product(id: 'SP0003', name: '没卖过', retailPrice: 1);
      store.addProduct(a);
      store.addProduct(b);
      store.addProduct(c);

      final today = du.todayKey();
      store.recordSaleFromProduct(today, a);
      store.recordSaleFromProduct(today, a);
      store.recordSaleFromProduct(today, b);

      expect(store.recentProducts(limit: 8).map((p) => p.name).toList(),
          ['卖得多', '卖得少']);
    });
  });

  group('加载容错', () {
    test('加载时单条数据损坏：保留能解析的，只丢弃坏的那条', () async {
      // 旧实现用 as List + map().toList()，任意一条坏数据都会让整个列表
      // 抛异常并被 catch 清空，界面只显示「暂无商品」，之后还会把空数据写回。
      await loadStoreWith({
        'sk_products':
            '[{"id":"SP0001","name":"好商品"},"坏数据",{"id":"SP0002","name":"另一个"}]',
      });
      final store = StoreService.instance;
      expect(store.products.length, 2);
      expect(store.products.map((p) => p.name),
          containsAll(['好商品', '另一个']));
      expect(store.droppedOnLoad, 1);
      expect(store.loadError, isNull);
    });

    test('加载时整段 JSON 损坏：标记 loadError，不冒充「暂无商品」', () async {
      await loadStoreWith({'sk_products': '{不是数组'});
      final store = StoreService.instance;
      expect(store.products, isEmpty);
      expect(store.loadError, isNotNull);
    });

    test('销售记录键与内层 date 不一致时以键为准（否则统计不到）', () async {
      await loadStoreWith({
        'sk_sales':
            '{"2026-07-05":{"date":"2026-01-01","items":[{"id":"s1","name":"错位","quantity":1,"unitPrice":2,"totalPrice":2}]}}',
      });
      final store = StoreService.instance;
      expect(store.monthlyStats('2026-07').totalRevenue, 2);
      expect(store.monthlyStats('2026-01').totalRevenue, 0);
    });

    test('欠账段落损坏时不吞掉整份数据，只计入 droppedOnLoad', () async {
      await loadStoreWith({
        'sk_products': '[{"id":"SP0001","name":"好商品"}]',
        'sk_credits': '[{"id":"c1","customer":"王婶","amount":10,'
            '"date":"2026-07-01"},"坏数据"]',
      });
      final store = StoreService.instance;
      expect(store.products.length, 1);
      expect(store.credits.single.customer, '王婶');
      expect(store.droppedOnLoad, 1);
    });
  });

  group('商品 CSV 导入 / 导出', () {
    test('importProducts 合并：条码覆盖 / 新条码追加 / 空行跳过', () {
      final store = StoreService.instance;
      store.addProduct(Product(
          id: 'SP9101', name: '旧名', barcode: '6900001', retailPrice: 1));

      final r = store.importProducts([
        Product(id: '', name: '新名', barcode: '6900001', retailPrice: 2), // 覆盖
        Product(id: '', name: '全新品', barcode: '6900002', retailPrice: 5), // 追加
        Product(id: '', name: '', barcode: ''), // 跳过
      ]);

      expect(r.overwritten, 1);
      expect(r.added, 1);
      expect(r.skipped, 1);
      expect(store.products.length, 2);
      final p = store.findByBarcode('6900001')!;
      expect(p.id, 'SP9101');
      expect(p.name, '新名');
      expect(store.findByBarcode('6900002')!.id, 'SP9102');
    });

    test('导入会带上批发价（字段不再是被忽略的摆设）', () {
      final store = StoreService.instance;
      store.importProducts([
        Product(
            id: '',
            name: '整件水',
            barcode: '6900009',
            retailPrice: 2,
            wholesalePrice: 1.5),
      ]);
      expect(store.findByBarcode('6900009')!.wholesalePrice, 1.5);
    });

    test('CSV 里价格留空不会把已有价格清零', () {
      final store = StoreService.instance;
      store.addProduct(Product(
          id: 'SP9201',
          name: '老商品',
          barcode: '6900003',
          retailPrice: 8,
          purchasePrice: 5,
          wholesalePrice: 6));

      // 空单元格经 parsePrice 得到 0 —— 直接覆盖会把价格静默清零
      store.importProducts([
        Product(id: '', name: '老商品', barcode: '6900003'),
      ]);

      final p = store.findByBarcode('6900003')!;
      expect(p.retailPrice, 8, reason: '价格留空应保留原值');
      expect(p.purchasePrice, 5);
      expect(p.wholesalePrice, 6);

      // 真给了价格才覆盖
      store.importProducts([
        Product(id: '', name: '老商品', barcode: '6900003', retailPrice: 9),
      ]);
      expect(store.findByBarcode('6900003')!.retailPrice, 9);
    });

    test('导出 CSV 表头可被识别，且不再包含库存列', () {
      final store = StoreService.instance;
      store.addProduct(
          Product(id: 'SP0008', name: '牙膏', retailPrice: 9.9, stock: 5));

      final rows = const CsvCodec().decode(store.exportCsv());
      expect(rows.first.first, '编号');
      expect(rows.first.length, Product.csvHeader.length);
      expect(rows.first, isNot(contains('库存')));

      rows.removeAt(0);
      final incoming = rows.map(Product.fromCsvRow).toList();
      expect(incoming.length, 1);
      expect(store.products.any((p) => p.name == '名称'), isFalse);
    });
  });

  group('查账检索范围', () {
    test('recordsInRange 按闭区间过滤并按日期倒序', () {
      final store = StoreService.instance;
      store.upsertSaleItem('2026-07-01',
          SaleItem(id: 'a', name: 'A', quantity: 1, unitPrice: 1, totalPrice: 1));
      store.upsertSaleItem('2026-07-15',
          SaleItem(id: 'b', name: 'B', quantity: 1, unitPrice: 1, totalPrice: 1));
      store.upsertSaleItem('2026-08-01',
          SaleItem(id: 'c', name: 'C', quantity: 1, unitPrice: 1, totalPrice: 1));

      final r = store.recordsInRange('2026-07-01', '2026-07-31');
      expect(r.length, 2);
      expect(r.first.date, '2026-07-15'); // 倒序
      expect(r.last.date, '2026-07-01');
      expect(jsonEncode(store.recordsInRange('2026-09-01', '2026-09-30')),
          '[]');
    });
  });
}
