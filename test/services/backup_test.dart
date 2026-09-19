// 备份文件测试：v3 编解码、v2 向后兼容、恢复失败时数据必须原样不动、一键撤销。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_keeper/models/credit.dart';
import 'package:shop_keeper/models/product.dart';
import 'package:shop_keeper/models/sale.dart';
import 'package:shop_keeper/services/backup_codec.dart';
import 'package:shop_keeper/services/store_service.dart';

import '../helpers/store_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStore();
  });

  group('导出 / 恢复', () {
    test('导出 → 清空 → 恢复后商品、分类、销售一致', () async {
      final store = StoreService.instance;
      store.addProduct(Product(
          id: 'SP0007',
          name: '剪刀',
          category: '文具',
          retailPrice: 5,
          purchasePrice: 3,
          wholesalePrice: 4,
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
      store.credits = [];

      final r = await store.importBackup(backup);
      expect(r.ok, isTrue);
      expect(r.productCount, 1);
      expect(r.dayCount, 1);
      expect(store.products.first.isFavorite, isTrue);
      expect(store.products.first.purchasePrice, 3);
      expect(store.products.first.wholesalePrice, 4);
      expect(store.categories, contains('文具'));
      expect(store.itemsOf('2026-07-01').length, 1);
    });

    test('欠账台账随备份一起走（v3 新增）', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '烟'));
      store.addCredit(Credit(
        id: Credit.newId(),
        customer: '王婶',
        amount: 25.5,
        date: '2026-07-01',
        note: '两包烟',
      ));
      store.addCredit(Credit(
        id: Credit.newId(),
        customer: '张老师',
        amount: 10,
        date: '2026-07-02',
        settled: true,
        settledDate: '2026-07-05',
      ));

      final backup = store.exportBackup();
      expect(store.previewBackup(backup)!.creditCount, 2);
      expect(jsonDecode(backup)['version'], kBackupVersion);

      store.products = [];
      store.credits = [];

      final r = await store.importBackup(backup);
      expect(r.ok, isTrue);
      expect(r.creditCount, 2);
      expect(store.credits.length, 2);
      expect(store.unsettledCreditTotal, 25.5);
      expect(store.unsettledCredits().single.customer, '王婶');
    });

    test('v2 老备份文件仍能恢复（只是没有欠账）', () async {
      final store = StoreService.instance;
      final v2 = jsonEncode({
        'version': 2,
        'exportedAt': '2026-07-01T10:00:00.000',
        'products': [
          {'id': 'SP0001', 'name': '老商品', 'retailPrice': 3}
        ],
        'categories': ['老分类'],
        'sales': {
          '2026-07-01': {
            'date': '2026-07-01',
            'items': [
              {
                'id': 'i1',
                'name': '老商品',
                'quantity': 1,
                'unitPrice': 3,
                'totalPrice': 3,
                'productId': 'SP0001',
              }
            ],
          }
        },
      });

      final r = await store.importBackup(v2);
      expect(r.ok, isTrue);
      expect(store.products.single.name, '老商品');
      expect(store.categories, contains('老分类'));
      expect(store.credits, isEmpty);
      expect(store.dayTotal('2026-07-01'), 3);
    });

    test('备份带 BOM 也能恢复（记事本另存过的文件不再失效）', () async {
      final store = StoreService.instance;
      final withBom = '\uFEFF${jsonEncode({
            'version': 2,
            'products': [
              {'id': 'SP0001', 'name': '带BOM的商品', 'retailPrice': 3}
            ],
            'categories': <String>[],
            'sales': <String, dynamic>{},
          })}';

      // 预览也不能因为 BOM 就判成「不是备份文件」
      expect(store.previewBackup(withBom), isNotNull);

      final r = await store.importBackup(withBom);
      expect(r.ok, isTrue);
      expect(store.products.single.name, '带BOM的商品');
    });

    test('撤销恢复：把数据还原成恢复之前的模样', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '我原来就有的'));

      // 造一份"另一台设备"的备份并恢复进去
      final other = jsonEncode({
        'version': 3,
        'products': [
          {'id': 'SP9999', 'name': '别人的商品'}
        ],
        'categories': <String>[],
        'sales': <String, dynamic>{},
        'credits': <dynamic>[],
      });
      final r = await store.importBackup(other);
      expect(r.ok, isTrue);
      expect(store.products.single.name, '别人的商品');

      // 撤销回到的是「执行那次恢复之前」的状态
      final undone = await store.undoLastRestore();
      expect(undone, isTrue);
      expect(store.products.single.name, '我原来就有的');
    });

    test('写盘中途失败时，内存和磁盘必须一起回滚', () async {
      final store = StoreService.instance;
      // 直接铺一份「原有数据」到存储，避免 addProduct 的发射后不管写入干扰时序。
      // 用 loadStoreWith 而不是 resetStoreWith —— 后者会把内存状态显式抹平。
      await loadStoreWith({
        'sk_seeded': true,
        'sk_products': jsonEncode([
          {'id': 'SP0001', 'name': '原有商品', 'retailPrice': 5}
        ]),
        'sk_categories': <String>['原有分类'],
        'sk_sales': jsonEncode({
          '2026-07-01': {
            'date': '2026-07-01',
            'items': [
              {
                'id': 'a',
                'name': '原有商品',
                'quantity': 1,
                'unitPrice': 5,
                'totalPrice': 5,
                'productId': 'SP0001',
              }
            ],
          }
        }),
      });
      expect(store.products.single.name, '原有商品');
      addTearDown(() => store.debugFailWriteStep = 0);

      final backup = jsonEncode({
        'version': 3,
        'products': [
          {'id': 'SP9999', 'name': '备份商品', 'retailPrice': 9}
        ],
        'categories': <String>['备份分类'],
        'sales': <String, dynamic>{},
        'credits': <dynamic>[],
      });

      // 第 3 步是 sk_sales：商品与分类已经先写进去了，正好模拟「写了一半」
      store.debugFailWriteStep = 3;
      final r = await store.importBackup(backup);
      expect(r.ok, isFalse);

      // ① 内存已回滚
      expect(store.products.single.name, '原有商品');
      expect(store.categories, contains('原有分类'));
      expect(store.dayTotal('2026-07-01'), 5);
      expect(store.seeded, isTrue);

      // ② 磁盘也必须回到原状——这才是旧实现真正丢数据的地方：
      //    只回滚内存的话，重启后会读到「备份的商品 + 原有的营业额」
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString('sk_products'), contains('原有商品'));
      expect(prefs.getString('sk_products'), isNot(contains('备份商品')));
      expect(prefs.getStringList('sk_categories'), contains('原有分类'));
      expect(prefs.getString('sk_sales'), contains('原有商品'));
    });
  });

  group('恢复的安全护栏', () {
    test('失败的三类输入都不能改动已有数据', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '原有商品'));
      store.addCategory('原有分类');

      // 版本不对
      final bad = await store.importBackup('{"version":1}');
      expect(bad.ok, isFalse);
      expect(store.products.single.name, '原有商品');
      expect(store.categories, contains('原有分类'));

      // 不是 JSON
      final notJson = await store.importBackup('not json');
      expect(notJson.ok, isFalse);
      expect(store.products.single.name, '原有商品');

      // 备份里商品为空而本地有 → 取消恢复（多半选错文件）
      final emptyish = await store.importBackup(jsonEncode(
          {'version': 2, 'products': [], 'categories': [], 'sales': {}}));
      expect(emptyish.ok, isFalse);
      expect(store.products.single.name, '原有商品');
    });

    test('坏行被跳过但整体成功，绝不出现「商品换了、销售还是旧的」', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '原有商品'));

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

  group('预览与备份提醒', () {
    test('previewBackup 能识别非法文件', () {
      final store = StoreService.instance;
      expect(store.previewBackup('not json'), isNull);
      expect(store.previewBackup('{"version":1}'), isNull);
      expect(store.previewBackup('{"version":3}'), isNull); // 缺 products/sales
    });

    test('previewBackup 统计条数与导出时间', () {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: 'A'));
      store.upsertSaleItem('2026-07-01',
          SaleItem(id: 'a', name: 'A', quantity: 1, unitPrice: 1, totalPrice: 1));
      store.upsertSaleItem('2026-07-01',
          SaleItem(id: 'b', name: 'B', quantity: 1, unitPrice: 1, totalPrice: 1));

      final p = store.previewBackup(store.exportBackup())!;
      expect(p.productCount, 1);
      expect(p.dayCount, 1);
      expect(p.itemCount, 2);
      expect(p.exportedAt, isNotNull);
    });

    test('备份时间：markBackedUp 后可读出天数', () {
      final store = StoreService.instance;
      expect(store.daysSinceBackup, isNull);
      store.markBackedUp();
      expect(store.daysSinceBackup, 0);
    });
  });
}
