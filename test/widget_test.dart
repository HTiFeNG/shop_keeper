// 店铺管家核心数据层单元测试：库存差量联动、月度统计、备份恢复。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_keeper/models/product.dart';
import 'package:shop_keeper/models/sale.dart';
import 'package:shop_keeper/services/store_service.dart';
import 'package:shop_keeper/utils/csv_codec.dart';
import 'package:shop_keeper/utils/date_utils.dart' as du;
import 'package:shop_keeper/utils/format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = StoreService.instance;
    await store.load();
    store.products = [];
    store.categories = [];
    store.sales = {};
  });

  group('库存差量联动（允许负数）', () {
    test('记 3 件扣 3，改 5 再扣 2，删行回补', () async {
      final store = StoreService.instance;
      final p = Product(
          id: 'SP0001',
          name: '农夫山泉',
          retailPrice: 2,
          purchasePrice: 0.9,
          stock: 48);
      store.addProduct(p);

      // 记 3 件 → 48 - 3 = 45
      final item = SaleItem(
          id: 'r1',
          name: p.name,
          quantity: 3,
          unitPrice: 2,
          totalPrice: 6,
          productId: p.id);
      store.upsertSaleItem('2026-07-01', item);
      expect(store.findById('SP0001')!.stock, 45);

      // 改 5 → 再扣 2 = 43
      final item5 = item.copy()..quantity = 5..totalPrice = 10;
      store.upsertSaleItem('2026-07-01', item5);
      expect(store.findById('SP0001')!.stock, 43);

      // 删行 → 回补 5 = 48
      store.deleteSaleItem('2026-07-01', 'r1');
      expect(store.findById('SP0001')!.stock, 48);
    });

    test('手动改总价不影响库存', () {
      final store = StoreService.instance;
      final p = Product(id: 'SP0002', name: '可乐', retailPrice: 3, stock: 10);
      store.addProduct(p);
      final item = SaleItem(
          id: 'r2',
          name: p.name,
          quantity: 2,
          unitPrice: 3,
          totalPrice: 6,
          productId: p.id);
      store.upsertSaleItem('2026-07-01', item);
      expect(store.findById('SP0002')!.stock, 8);

      // 手动改总价（抹零）→ 数量未变 → 库存不动
      final manual = item.copy()
        ..totalPrice = 5
        ..isManualMode = true;
      store.upsertSaleItem('2026-07-01', manual);
      expect(store.findById('SP0002')!.stock, 8);
    });

    test('换绑商品：先回补旧商品再扣新商品；允许负库存', () {
      final store = StoreService.instance;
      final a = Product(id: 'SP0003', name: 'A', retailPrice: 1, stock: 1);
      final b = Product(id: 'SP0004', name: 'B', retailPrice: 1, stock: 1);
      store.addProduct(a);
      store.addProduct(b);

      final item = SaleItem(
          id: 'r3', name: 'A', quantity: 3, unitPrice: 1, totalPrice: 3, productId: 'SP0003');
      store.upsertSaleItem('2026-07-01', item);
      // 负库存允许：1 - 3 = -2
      expect(store.findById('SP0003')!.stock, -2);

      // 换绑到 B：回补 A 3 件 → 1，扣 B 3 件 → -2
      final rebound = item.copy()
        ..name = 'B'
        ..productId = 'SP0004';
      store.upsertSaleItem('2026-07-01', rebound);
      expect(store.findById('SP0003')!.stock, 1);
      expect(store.findById('SP0004')!.stock, -2);
    });

    test('撤销删除：重新 upsert 同一行再次扣库存', () {
      final store = StoreService.instance;
      final p = Product(id: 'SP0005', name: 'C', retailPrice: 5, stock: 20);
      store.addProduct(p);
      final item = SaleItem(
          id: 'r4', name: 'C', quantity: 2, unitPrice: 5, totalPrice: 10, productId: 'SP0005');
      store.upsertSaleItem('2026-07-01', item);
      expect(store.findById('SP0005')!.stock, 18);
      store.deleteSaleItem('2026-07-01', 'r4');
      expect(store.findById('SP0005')!.stock, 20);
      // 撤销 → 重新入账 → 再扣 2
      store.upsertSaleItem('2026-07-01', item);
      expect(store.findById('SP0005')!.stock, 18);
    });
  });

  group('recordSaleFromProduct（合并记账）', () {
    test('重复添加同商品：数量合并、只留一行、库存逐件扣减', () {
      final store = StoreService.instance;
      final p = Product(id: 'SP1001', name: '农夫山泉', retailPrice: 2, stock: 10);
      store.addProduct(p);

      store.recordSaleFromProduct('2026-07-01', p);
      store.recordSaleFromProduct('2026-07-01', p);
      store.recordSaleFromProduct('2026-07-01', p);

      final items = store.itemsOf('2026-07-01');
      expect(items.length, 1); // 合并为一行
      expect(items.first.quantity, 3);
      expect(items.first.totalPrice, closeTo(6, 0.001)); // 3 × 2
      expect(store.findById('SP1001')!.stock, 7); // 10 - 3
    });

    test('手动模式行合并：只加数量、不改总价', () {
      final store = StoreService.instance;
      final p = Product(id: 'SP1002', name: '可乐', retailPrice: 3, stock: 10);
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
      expect(items.first.quantity, 2); // 数量 +1
      expect(items.first.isManualMode, isTrue);
      expect(items.first.totalPrice, closeTo(5, 0.001)); // 总价不变
      expect(store.findById('SP1002')!.stock, 8); // 10 - 2
    });
  });

  group('月度统计', () {
    test('聚合 / 日均 / 最高日 / 件数 / 环比 / 排行 / 毛利', () {
      final store = StoreService.instance;
      final p = Product(
          id: 'SP0006', name: '牛奶', retailPrice: 3.5, purchasePrice: 2.2, stock: 100);
      store.addProduct(p);

      // 本月两天记录
      store.upsertSaleItem(
          '2026-07-01',
          SaleItem(
              id: 'm1', name: '牛奶', quantity: 2, unitPrice: 3.5, totalPrice: 7, productId: 'SP0006'));
      store.upsertSaleItem(
          '2026-07-02',
          SaleItem(
              id: 'm2', name: '牛奶', quantity: 3, unitPrice: 3.5, totalPrice: 10.5, productId: 'SP0006'));
      store.upsertSaleItem(
          '2026-07-02',
          SaleItem(id: 'm3', name: '散装糖', quantity: 1, unitPrice: 2, totalPrice: 2));

      // 上月一天记录（环比）
      store.upsertSaleItem(
          '2026-06-15',
          SaleItem(id: 'm4', name: '牛奶', quantity: 1, unitPrice: 3.5, totalPrice: 3.5, productId: 'SP0006'));

      final stats = store.monthlyStats('2026-07');
      expect(stats.recordCount, 2);
      expect(stats.totalRevenue, 19.5);
      expect(stats.averageRevenue, 9.75);
      expect(stats.maxRevenue, 12.5);
      expect(stats.maxRevenueDate, '2026-07-02');
      expect(stats.totalItems, 6);
      expect(stats.prevMonthRevenue, 3.5);
      // 毛利 = (3.5 - 2.2) * 5 = 6.5（散装糖无关联不计）
      expect(stats.estimatedProfit, closeTo(6.5, 0.001));
      // 排行第一为牛奶
      expect(stats.productRanking.first.name, '牛奶');
      expect(stats.productRanking.first.quantity, 5);

      // 空月
      final empty = store.monthlyStats('2026-08');
      expect(empty.recordCount, 0);
      expect(empty.totalRevenue, 0);
      expect(empty.maxRevenueDate, isNull);
    });
  });

  group('备份 / 恢复', () {
    test('导出 → 清空 → 恢复后数据一致', () async {
      final store = StoreService.instance;
      store.addProduct(Product(
          id: 'SP0007',
          name: '剪刀',
          category: '文具',
          retailPrice: 5,
          stock: 18,
          isFavorite: true));
      store.addCategory('文具');
      store.upsertSaleItem(
          '2026-07-01',
          SaleItem(
              id: 'b1', name: '剪刀', quantity: 1, unitPrice: 5, totalPrice: 5, productId: 'SP0007'));

      final backup = store.exportBackup();

      // 清空（模拟新设备）
      store.products = [];
      store.categories = [];
      store.sales = {};

      expect(store.importBackup(backup), isTrue);
      expect(store.products.length, 1);
      expect(store.products.first.isFavorite, isTrue);
      expect(store.categories, contains('文具'));
      expect(store.itemsOf('2026-07-01').length, 1);
      // 恢复时库存为备份时的快照（17 = 18 - 1）
      expect(store.findById('SP0007')!.stock, 17);

      // 非法 JSON → false
      expect(store.importBackup('not json'), isFalse);
      expect(store.importBackup('{"version":1}'), isFalse);
    });
  });

  group('QA 补充：回归缺口', () {
    test('跨年环比：1 月统计的上月营收取去年 12 月', () {
      final store = StoreService.instance;
      store.upsertSaleItem(
          '2025-12-31',
          SaleItem(id: 'y1', name: '年货', quantity: 2, unitPrice: 10, totalPrice: 20));
      store.upsertSaleItem(
          '2026-01-01',
          SaleItem(id: 'y2', name: '牛奶', quantity: 1, unitPrice: 3.5, totalPrice: 3.5));

      final stats = store.monthlyStats('2026-01');
      expect(stats.recordCount, 1);
      expect(stats.totalRevenue, 3.5);
      expect(stats.prevMonthRevenue, 20);
      // 12 月记录不得混入 1 月统计
      expect(stats.totalItems, 1);
    });

    test('删除商品后 productId 悬空：统计与删行均不崩', () {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP9001', name: '临期奶', retailPrice: 2, purchasePrice: 1, stock: 5));
      store.upsertSaleItem(
          '2026-07-01',
          SaleItem(
              id: 'd1', name: '临期奶', quantity: 2, unitPrice: 2, totalPrice: 4, productId: 'SP9001'));
      store.deleteProduct('SP9001');

      // 统计：商品已删，findById 返回 null → 毛利跳过、排行按 productId 聚合不崩
      final stats = store.monthlyStats('2026-07');
      expect(stats.totalRevenue, 4);
      expect(stats.estimatedProfit, 0);
      expect(stats.productRanking.single.name, '临期奶');

      // 删行：商品已删 → 回补被安全忽略，不抛异常
      final removed = store.deleteSaleItem('2026-07-01', 'd1');
      expect(removed, isNotNull);
      expect(store.itemsOf('2026-07-01'), isEmpty);
    });

    test('importProducts 合并：条码覆盖 / 新条码追加 / 空行跳过', () {
      final store = StoreService.instance;
      store.addProduct(Product(
          id: 'SP9101', name: '旧名', barcode: '6900001', retailPrice: 1, stock: 3));

      final r = store.importProducts([
        Product(id: '', name: '新名', barcode: '6900001', retailPrice: 2, stock: 9), // 覆盖
        Product(id: '', name: '全新品', barcode: '6900002', retailPrice: 5, stock: 7), // 追加
        Product(id: '', name: '', barcode: ''), // 跳过
      ]);

      expect(r.overwritten, 1);
      expect(r.added, 1);
      expect(r.skipped, 1);
      expect(store.products.length, 2);
      // 覆盖：保留原 id，字段更新
      final p = store.findByBarcode('6900001')!;
      expect(p.id, 'SP9101');
      expect(p.name, '新名');
      expect(p.stock, 9);
      // 追加：自动编号 SP9102
      expect(store.findByBarcode('6900002')!.id, 'SP9102');
    });

    test('导出 CSV 再导入：表头（9 列）应被识别剔除，不产生幻影商品', () {
      final store = StoreService.instance;
      store.addProduct(Product(
          id: 'SP9201', name: '矿泉水', barcode: '6901001', retailPrice: 2, stock: 24));

      final rows = const CsvCodec().decode(store.exportCsv());
      // 与 product_manage_page._import 相同的表头判定逻辑（首列「编号」对齐，不依赖列数）
      final headerRecognized =
          rows.isNotEmpty && rows.first.isNotEmpty && rows.first[0] == '编号';
      expect(headerRecognized, isTrue,
          reason: '自家导出表头首列应为「编号」（csvHeader=${Product.csvHeader.length} 列），'
              '导入页据此剔除表头，避免表头被当作幻影商品导入');
    });
  });

  group('工具函数', () {
    test('formatCurrency / fmtPrice', () {
      expect(formatCurrency(1234.5), '¥1,234.50');
      expect(formatCurrency(0), '¥0.00');
      expect(fmtPrice(2), '2');
      expect(fmtPrice(2.5), '2.50');
    });

    test('日期工具：跨年切月', () {
      expect(du.dateKey(DateTime(2026, 7, 26)), '2026-07-26');
      expect(du.prevMonth('2026-01'), '2025-12');
      expect(du.nextMonth('2026-12'), '2027-01');
      expect(du.monthLabel('2026-07'), '2026年7月');
    });

    test('CsvCodec 往返一致（含逗号 / 引号 / 换行）', () {
      const codec = CsvCodec();
      final rows = [
        ['a,b', 'c"d', 'e\nf'],
        ['plain', '', 'x'],
      ];
      final decoded = codec.decode(codec.encode(rows));
      expect(decoded, rows);
    });

    test('导出 CSV 再导入：表头（9 列）应被识别剔除，不产生幻影商品', () {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0008', name: '牙膏', retailPrice: 9.9, stock: 5));

      // 自家导出 → 解码
      final rows = const CsvCodec().decode(store.exportCsv());
      expect(rows.first.length, Product.csvHeader.length); // 表头为 9 列

      // 与导入页一致的表头识别逻辑（首列「编号」对齐）
      expect(rows.first.isNotEmpty && rows.first[0] == '编号', isTrue);
      rows.removeAt(0);

      final incoming = rows.map(Product.fromCsvRow).toList();
      expect(incoming.length, 1);
      final r = store.importProducts(incoming);
      // 原商品条码为空 → 追加为 1 条新商品；绝不能出现名为「名称」的幻影行
      expect(r.added, 1);
      expect(store.products.any((p) => p.name == '名称'), isFalse);
    });
  });
}
