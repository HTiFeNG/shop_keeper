// 统计口径测试：按月（含毛利快照、跨年环比）+ 自定义区间 + 按年。
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/models/product.dart';
import 'package:shop_keeper/models/sale.dart';
import 'package:shop_keeper/services/store_service.dart';

import '../helpers/store_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStore();
  });

  group('按月统计与毛利口径', () {
    test('聚合 / 日均 / 最高日 / 件数 / 环比 / 排行', () {
      final store = StoreService.instance;
      final p =
          Product(id: 'SP0006', name: '牛奶', retailPrice: 3.5, purchasePrice: 2.2);
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
      expect(stats.label, '2026年7月');

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
      final p = Product(
          id: 'SP0001', name: '清仓饼干', retailPrice: 1, purchasePrice: 2);
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

  group('自定义区间统计', () {
    void seed() {
      final store = StoreService.instance;
      // 区间内两天
      store.upsertSaleItem('2026-07-05',
          SaleItem(id: 'a', name: 'A', quantity: 1, unitPrice: 10, totalPrice: 10));
      store.upsertSaleItem('2026-07-18',
          SaleItem(id: 'b', name: 'B', quantity: 2, unitPrice: 5, totalPrice: 10));
      // 紧邻其前的等长区间（6/16 ~ 7/4）里的一天
      store.upsertSaleItem('2026-06-20',
          SaleItem(id: 'c', name: 'C', quantity: 1, unitPrice: 7, totalPrice: 7));
      // 区间之后的一天，不应被算进来
      store.upsertSaleItem('2026-07-25',
          SaleItem(id: 'd', name: 'D', quantity: 1, unitPrice: 99, totalPrice: 99));
    }

    test('只统计闭区间内，按天聚合', () {
      seed();
      final s = StoreService.instance
          .statsForRange('2026-07-01', '2026-07-20', label: '测试区间');
      expect(s.recordCount, 2);
      expect(s.totalRevenue, 20);
      expect(s.totalItems, 3);
      expect(s.averageRevenue, 10);
      expect(s.label, '测试区间');
    });

    test('环比对象是「紧邻其前的等长区间」', () {
      seed();
      final s = StoreService.instance.statsForRange('2026-07-01', '2026-07-20');
      // 7/01–7/20 共 20 天 → 上一区间 6/11–6/30，其中有 6/20 的 7 元
      expect(s.prevMonthRevenue, 7);
      expect(s.prevLabel, '上一区间');
      expect(s.momGrowth, closeTo((20 - 7) / 7, 0.001));
    });

    test('区间内无记录时返回零值而不是崩', () {
      final s = StoreService.instance
          .statsForRange('2026-09-01', '2026-09-30');
      expect(s.recordCount, 0);
      expect(s.totalRevenue, 0);
      expect(s.maxRevenueDate, isNull);
      expect(s.productRanking, isEmpty);
    });
  });

  group('年度统计', () {
    test('12 个月完整列出，没有账的月补 0', () {
      final store = StoreService.instance;
      store.upsertSaleItem('2026-03-10',
          SaleItem(id: 'a', name: 'A', quantity: 1, unitPrice: 10, totalPrice: 10));
      store.upsertSaleItem('2026-08-20',
          SaleItem(id: 'b', name: 'B', quantity: 2, unitPrice: 30, totalPrice: 60));
      // 前一年不应被算进来
      store.upsertSaleItem('2025-08-20',
          SaleItem(id: 'c', name: 'C', quantity: 1, unitPrice: 999, totalPrice: 999));

      final y = store.yearlyStats('2026');
      expect(y.months.length, 12);
      expect(y.totalRevenue, 70);
      expect(y.totalItems, 3);
      expect(y.activeMonths, 2);
      expect(y.recordCount, 2);
      expect(y.bestMonth, '2026-08');
      expect(y.bestMonthRevenue, 60);
      expect(y.averageRevenue, 35); // 70 / 2 个有账的月
    });

    test('图表数据 12 项，标签为「1月…12月」', () {
      final store = StoreService.instance;
      store.upsertSaleItem('2026-01-05',
          SaleItem(id: 'a', name: 'A', quantity: 1, unitPrice: 1, totalPrice: 1));
      final chart = store.yearlyStats('2026').chartData;
      expect(chart.length, 12);
      expect(chart.first.label, '1月');
      expect(chart.last.label, '12月');
      expect(chart.first.tooltipLabel, '2026年1月');
      expect(chart.first.date.length, 7); // YYYY-MM，图表不能按 substring(8) 截取
    });

    test('全年无记录时 bestMonth 为 null，不报错', () {
      final y = StoreService.instance.yearlyStats('2030');
      expect(y.totalRevenue, 0);
      expect(y.bestMonth, isNull);
      expect(y.activeMonths, 0);
      expect(y.averageRevenue, 0);
    });

    test('全年商品排行按营收合并', () {
      final store = StoreService.instance;
      store.upsertSaleItem('2026-02-01',
          SaleItem(id: 'a', name: '矿泉水', quantity: 1, unitPrice: 2, totalPrice: 2));
      store.upsertSaleItem('2026-09-01',
          SaleItem(id: 'b', name: '矿泉水', quantity: 3, unitPrice: 2, totalPrice: 6));
      final y = store.yearlyStats('2026');
      expect(y.productRanking.single.name, '矿泉水');
      expect(y.productRanking.single.quantity, 4);
      expect(y.productRanking.single.revenue, 8);
    });
  });
}
