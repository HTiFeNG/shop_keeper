// 店铺管家核心数据层单元测试。
//
// 覆盖：合并记账、月度统计与毛利口径、数据安全（加载容错 / 编号不回收 /
// 恢复不半途生效）、商品导入导出、工具函数。
//
// 注：库存功能已于 3.0.0 移除，相关用例一并删除。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_keeper/main.dart';
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
    });
  });

  group('月度统计与毛利口径', () {
    test('聚合 / 日均 / 最高日 / 件数 / 环比 / 排行', () {
      final store = StoreService.instance;
      final p = Product(
          id: 'SP0006', name: '牛奶', retailPrice: 3.5, purchasePrice: 2.2);
      store.addProduct(p);

      store.upsertSaleItem(
          '2026-07-01',
          SaleItem(
              id: 'm1',
              name: '牛奶',
              quantity: 2,
              unitPrice: 3.5,
              totalPrice: 7,
              productId: 'SP0006'));
      store.upsertSaleItem(
          '2026-07-02',
          SaleItem(
              id: 'm2',
              name: '牛奶',
              quantity: 3,
              unitPrice: 3.5,
              totalPrice: 10.5,
              productId: 'SP0006'));
      store.upsertSaleItem(
          '2026-07-02',
          SaleItem(id: 'm3', name: '散装糖', quantity: 1, unitPrice: 2, totalPrice: 2));

      store.upsertSaleItem(
          '2026-06-15',
          SaleItem(
              id: 'm4',
              name: '牛奶',
              quantity: 1,
              unitPrice: 3.5,
              totalPrice: 3.5,
              productId: 'SP0006'));

      final stats = store.monthlyStats('2026-07');
      expect(stats.recordCount, 2);
      expect(stats.totalRevenue, 19.5);
      expect(stats.averageRevenue, 9.75);
      expect(stats.maxRevenue, 12.5);
      expect(stats.maxRevenueDate, '2026-07-02');
      expect(stats.totalItems, 6);
      expect(stats.prevMonthRevenue, 3.5);
      expect(stats.productRanking.first.name, '牛奶');
      expect(stats.productRanking.first.quantity, 5);

      final empty = store.monthlyStats('2026-08');
      expect(empty.recordCount, 0);
      expect(empty.totalRevenue, 0);
      expect(empty.maxRevenueDate, isNull);
    });

    test('毛利用「售出时的进价快照」：之后改进价不改写历史', () {
      final store = StoreService.instance;
      final p =
          Product(id: 'SP0001', name: '牛奶', retailPrice: 3.5, purchasePrice: 2.2);
      store.addProduct(p);

      store.recordSaleFromProduct('2026-07-01', p);
      final before = store.monthlyStats('2026-07').estimatedProfit;
      expect(before, closeTo(1.3, 0.001)); // 3.5 - 2.2

      // 事后把参考进价改掉：旧实现会把已经过去月份的毛利一起改掉
      p.purchasePrice = 3.0;
      final after = store.monthlyStats('2026-07').estimatedProfit;
      expect(after, closeTo(before, 0.001));
    });

    test('亏本销售计为负毛利，不再被静默丢弃', () {
      final store = StoreService.instance;
      // 清仓：售价 1 元，进价 2 元
      final p =
          Product(id: 'SP0001', name: '清仓饼干', retailPrice: 1, purchasePrice: 2);
      store.addProduct(p);
      store.recordSaleFromProduct('2026-07-01', p);
      store.recordSaleFromProduct('2026-07-01', p);

      final stats = store.monthlyStats('2026-07');
      expect(stats.totalRevenue, closeTo(2, 0.001));
      // 旧实现 margin > 0 才累加 → 结果为 0，利润被高估
      expect(stats.estimatedProfit, closeTo(-2, 0.001));
    });

    test('没填进价的明细会被计数，UI 才能提示毛利漏算了多少', () {
      final store = StoreService.instance;
      final withCost =
          Product(id: 'SP0001', name: '有进价', retailPrice: 3, purchasePrice: 1);
      final noCost = Product(id: 'SP0002', name: '没进价', retailPrice: 3);
      store.addProduct(withCost);
      store.addProduct(noCost);
      store.recordSaleFromProduct('2026-07-01', withCost);
      store.recordSaleFromProduct('2026-07-01', noCost);
      // 手输行（无关联商品）也算没进价
      store.upsertSaleItem('2026-07-01',
          SaleItem(id: 'x1', name: '散装', quantity: 1, unitPrice: 2, totalPrice: 2));

      final stats = store.monthlyStats('2026-07');
      expect(stats.estimatedProfit, closeTo(2, 0.001)); // 只有有进价那行计入
      expect(stats.profitMissingCostLines, 2);
    });

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
      expect(stats.totalItems, 1);
    });

    test('删除商品后 productId 悬空：统计与删行均不崩', () {
      final store = StoreService.instance;
      store.addProduct(
          Product(id: 'SP9001', name: '临期奶', retailPrice: 2, purchasePrice: 1));
      store.upsertSaleItem(
          '2026-07-01',
          SaleItem(
              id: 'd1',
              name: '临期奶',
              quantity: 2,
              unitPrice: 2,
              totalPrice: 4,
              productId: 'SP9001'));
      store.deleteProduct('SP9001');

      final stats = store.monthlyStats('2026-07');
      expect(stats.totalRevenue, 4);
      // 商品已删且该行没有成本快照 → 不计入毛利，但要计入缺失数
      expect(stats.estimatedProfit, 0);
      expect(stats.profitMissingCostLines, 1);
      expect(stats.productRanking.single.name, '临期奶');

      final removed = store.deleteSaleItem('2026-07-01', 'd1');
      expect(removed, isNotNull);
      expect(store.itemsOf('2026-07-01'), isEmpty);
    });
  });

  group('数据安全', () {
    test('加载时单条数据损坏：保留能解析的，只丢弃坏的那条', () async {
      // 旧实现用 as List + map().toList()，任意一条坏数据都会让整个列表
      // 抛异常并被 catch 清空，界面只显示「暂无商品」，之后还会把空数据写回。
      SharedPreferences.setMockInitialValues({
        'sk_products':
            '[{"id":"SP0001","name":"好商品"},"坏数据",{"id":"SP0002","name":"另一个"}]',
      });
      final store = StoreService.instance;
      await store.load();
      expect(store.products.length, 2);
      expect(store.products.map((p) => p.name), containsAll(['好商品', '另一个']));
      expect(store.droppedOnLoad, 1);
      expect(store.loadError, isNull);
    });

    test('加载时整段 JSON 损坏：标记 loadError，不冒充「暂无商品」', () async {
      SharedPreferences.setMockInitialValues({'sk_products': '{不是数组'});
      final store = StoreService.instance;
      await store.load();
      expect(store.products, isEmpty);
      expect(store.loadError, isNotNull);
    });

    test('销售记录键与内层 date 不一致时以键为准（否则统计不到）', () async {
      SharedPreferences.setMockInitialValues({
        'sk_sales':
            '{"2026-07-05":{"date":"2026-01-01","items":[{"id":"s1","name":"错位","quantity":1,"unitPrice":2,"totalPrice":2}]}}',
      });
      final store = StoreService.instance;
      await store.load();
      expect(store.monthlyStats('2026-07').totalRevenue, 2);
      expect(store.monthlyStats('2026-01').totalRevenue, 0);
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

    test('恢复失败不会半途替换内存数据', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '原有商品'));
      store.addCategory('原有分类');

      // 版本不对 → 直接失败，数据必须原样
      final bad = await store.importBackup('{"version":1}');
      expect(bad.ok, isFalse);
      expect(store.products.single.name, '原有商品');
      expect(store.categories, contains('原有分类'));

      // 不是 JSON → 失败
      final notJson = await store.importBackup('not json');
      expect(notJson.ok, isFalse);
      expect(store.products.single.name, '原有商品');

      // 备份里商品为空而本地有 → 取消恢复（多半选错文件）
      final emptyish = await store.importBackup(
          jsonEncode({'version': 2, 'products': [], 'categories': [], 'sales': {}}));
      expect(emptyish.ok, isFalse);
      expect(store.products.single.name, '原有商品');

      // 销售段是坏结构 → 整体成功但跳过坏行，绝不出现「商品换了、销售还是旧的」
      final withBadSales = await store.importBackup(jsonEncode({
        'version': 2,
        'products': [
          {'id': 'SP9999', 'name': '备份商品'}
        ],
        'categories': ['备份分类'],
        'sales': {'2026-07-01': '坏结构'},
      }));
      expect(withBadSales.ok, isTrue);
      expect(withBadSales.skipped, 1);
      expect(store.products.single.name, '备份商品');
      expect(store.categories, contains('备份分类'));
      expect(store.sales, isEmpty);
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
          purchasePrice: 3,
          isFavorite: true));
      store.addCategory('文具');
      store.upsertSaleItem(
          '2026-07-01',
          SaleItem(
              id: 'b1',
              name: '剪刀',
              quantity: 1,
              unitPrice: 5,
              totalPrice: 5,
              productId: 'SP0007'));

      final backup = store.exportBackup();
      expect(store.previewBackup(backup)!.productCount, 1);

      // 清空（模拟新设备）
      store.products = [];
      store.categories = [];
      store.sales = {};

      final r = await store.importBackup(backup);
      expect(r.ok, isTrue);
      expect(r.productCount, 1);
      expect(r.dayCount, 1);
      expect(store.products.first.isFavorite, isTrue);
      expect(store.products.first.purchasePrice, 3);
      expect(store.categories, contains('文具'));
      expect(store.itemsOf('2026-07-01').length, 1);
    });

    test('previewBackup 能识别非法文件', () {
      final store = StoreService.instance;
      expect(store.previewBackup('not json'), isNull);
      expect(store.previewBackup('{"version":1}'), isNull);
    });

    test('备份时间：markBackedUp 后可读出天数', () {
      final store = StoreService.instance;
      expect(store.daysSinceBackup, isNull);
      store.markBackedUp();
      expect(store.daysSinceBackup, 0);
    });
  });

  group('商品导入', () {
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

    test('导出 CSV 表头可被识别，且不再包含库存列', () {
      final store = StoreService.instance;
      store.addProduct(
          Product(id: 'SP0008', name: '牙膏', retailPrice: 9.9, stock: 5));

      final rows = const CsvCodec().decode(store.exportCsv());
      expect(rows.first.first, '编号');
      expect(rows.first.length, Product.csvHeader.length);
      expect(Product.csvHeader, isNot(contains('库存')));
      expect(rows.first, isNot(contains('库存')));

      rows.removeAt(0);
      final incoming = rows.map(Product.fromCsvRow).toList();
      expect(incoming.length, 1);
      expect(store.products.any((p) => p.name == '名称'), isFalse);
    });
  });

  group('工具函数', () {
    test('parsePrice 挡住非有限数（否则会让持久化永久静默失效）', () {
      // double.tryParse 接受 "Infinity"/"1e400"/"NaN"，它们不小于 0，
      // 能绕过旧判断；而 jsonEncode 遇到非有限数会抛异常 —— 一旦进了商品库，
      // 之后每次保存商品都会失败，且因为不 await，用户看不到任何报错。
      expect(parsePrice('Infinity'), 0);
      expect(parsePrice('1e400'), 0);
      expect(parsePrice('NaN'), 0);
      expect(parsePrice('1.2.3'), 0);
      expect(parsePrice('12元'), 0);
      expect(parsePrice('-5'), 0);
      expect(parsePrice('3.5'), 3.5);
    });

    test('带非有限价格的行不会让 jsonEncode 抛异常', () {
      final p = Product.fromCsvRow(
          ['', '怪价商品', '', '', '', 'Infinity', 'NaN', '1e400']);
      expect(p.wholesalePrice, 0);
      expect(p.purchasePrice, 0);
      expect(p.retailPrice, 0);
      expect(() => jsonEncode([p.toJson()]), returnsNormally);
    });

    test('formatCurrency 对非有限数不产生乱码', () {
      expect(formatCurrency(1234.5), '¥1,234.50');
      expect(formatCurrency(0), '¥0.00');
      expect(formatCurrency(-12.5), '-¥12.50');
      expect(formatCurrency(double.infinity), '¥—');
      expect(formatCurrency(double.nan), '¥—');
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

    test('销售行 id 唯一：同毫秒内连续生成不重复', () {
      final ids = {for (var i = 0; i < 2000; i++) SaleItem.newId()};
      expect(ids.length, 2000);
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

      final recent = store.recentProducts(limit: 8);
      expect(recent.map((p) => p.name).toList(), ['卖得多', '卖得少']);
    });
  });

  group('界面冒烟（小屏手机 1080x1920）', () {
    testWidgets('启动 / 切 Tab / 打开新增商品表单都不报错，且表单已无库存', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ShopKeeperApp());
      await tester.pumpAndSettle();

      // 首启询问弹窗 → 选「从空开始」
      if (find.text('从空开始').evaluate().isNotEmpty) {
        await tester.tap(find.text('从空开始'));
        await tester.pumpAndSettle();
      }

      // 首页核心入口在位
      expect(find.text('添加商品'), findsOneWidget);

      // 切到「商品」Tab
      await tester.tap(find.byIcon(Icons.inventory_2_outlined));
      await tester.pumpAndSettle();
      expect(find.text('商品管理'), findsOneWidget);

      // 打开新增商品表单
      await tester.tap(find.text('新增'));
      await tester.pumpAndSettle();
      expect(find.text('新增商品'), findsOneWidget); // AppBar 标题
      expect(find.text('请输入商品名称'), findsOneWidget); // 表单已渲染
      // 库存输入框应彻底消失（旧版这里是「请输入库存数量」）
      expect(find.text('请输入库存数量'), findsNothing);

      // 布局溢出等异常若发生，会在这里暴露
      expect(tester.takeException(), isNull);
    });

    testWidgets('当日合计固定在列表上方：明细很多并滚动后仍然可见', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

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
      SharedPreferences.setMockInitialValues({
        'sk_seeded': true, // 跳过首启询问弹窗
        'sk_sales': jsonEncode({
          today: {'date': today, 'items': items},
        }),
      });

      await tester.pumpWidget(const ShopKeeperApp());
      await tester.pumpAndSettle();

      // 首启询问弹窗：load() 是异步的，首帧回调时 seeded 可能还是 false，
      // 所以即便预置了 sk_seeded 也要兜底关掉它
      if (find.text('从空开始').evaluate().isNotEmpty) {
        await tester.tap(find.text('从空开始'));
        await tester.pumpAndSettle();
      }

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
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
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

      await tester.pumpWidget(const ShopKeeperApp());
      await tester.pumpAndSettle();

      if (find.text('从空开始').evaluate().isNotEmpty) {
        await tester.tap(find.text('从空开始'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byIcon(Icons.inventory_2_outlined));
      await tester.pumpAndSettle();

      expect(find.text('没填进价的商品'), findsOneWidget);
      expect(find.text('进价未填'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
