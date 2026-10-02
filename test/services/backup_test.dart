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

  group('恢复保护（评审后补）', () {
    test('v2 老备份不含欠账：默认拒绝，确认后才清空', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '白菜'));
      store.addCredit(Credit(
          id: 'c1', customer: '王婶', amount: 100, date: '2026-07-01'));
      expect(store.credits.length, 1);

      // 一份合法的 v2 备份（v2 没有 credits 字段）
      final v2 = jsonEncode({
        'version': 2,
        'exportedAt': '2026-07-02T00:00:00.000',
        'products': [
          {'id': 'SP0009', 'name': '备份里的商品'}
        ],
        'categories': <String>[],
        'sales': <String, dynamic>{},
      });

      // 默认拒绝，且数据完全没动 —— 欠账不能被静默清空
      final blocked = await store.importBackup(v2);
      expect(blocked.ok, isFalse);
      expect(blocked.needsConfirm, isTrue);
      expect(store.credits.length, 1);
      expect(store.products.single.name, '白菜');

      // 用户确认后才真的恢复，并清空欠账
      final forced = await store.importBackup(v2, allowDataLoss: true);
      expect(forced.ok, isTrue);
      expect(store.credits, isEmpty);
      expect(store.products.single.name, '备份里的商品');
    });

    test('items 里混入坏元素：只跳过它，不再让整份备份作废', () async {
      final store = StoreService.instance;
      final text = jsonEncode({
        'version': 3,
        'products': [
          {'id': 'SP0001', 'name': '好商品'}
        ],
        'categories': <String>[],
        'sales': {
          '2026-07-01': {
            'date': '2026-07-01',
            'items': [
              '坏行', // 不是对象
              42, // 也不是
              {
                'id': 'ok1',
                'name': '正常行',
                'quantity': 1,
                'unitPrice': 2,
                'totalPrice': 2,
              },
            ],
          },
        },
      });

      final r = await store.importBackup(text);
      expect(r.ok, isTrue);
      expect(store.itemsOf('2026-07-01').length, 1);
      expect(store.itemsOf('2026-07-01').single.name, '正常行');
      expect(r.skipped, greaterThanOrEqualTo(2));
    });

    test('导入校验：重复编号 / 负金额 / 非法日期都会被跳过', () async {
      final store = StoreService.instance;
      final text = jsonEncode({
        'version': 3,
        'products': [
          {'id': 'SP0001', 'name': 'A', 'retailPrice': 3},
          {'id': 'SP0001', 'name': '重复编号的B', 'retailPrice': 9},
        ],
        'categories': <String>[],
        'sales': {
          // 键不是合法日期
          '不是日期': {
            'date': '不是日期',
            'items': [
              {
                'id': 'x',
                'name': '脏行',
                'quantity': 1,
                'unitPrice': 1,
                'totalPrice': 1,
              },
            ],
          },
          // 负金额的行
          '2026-07-02': {
            'date': '2026-07-02',
            'items': [
              {
                'id': 'y',
                'name': '负金额',
                'quantity': 1,
                'unitPrice': -2,
                'totalPrice': -2,
              },
            ],
          },
        },
        'credits': [
          {'id': 'c1', 'customer': '甲', 'amount': -50, 'date': '2026-07-01'},
          {'id': 'c2', 'customer': '乙', 'amount': 20, 'date': '乱日期'},
          {'id': 'c3', 'customer': '丙', 'amount': 30, 'date': '2026-07-01'},
        ],
      });

      final r = await store.importBackup(text);
      expect(r.ok, isTrue);
      expect(store.products.length, 1, reason: '重复编号只保留第一份');
      expect(store.products.single.name, 'A');
      expect(store.sales, isEmpty, reason: '非法日期/负金额的日子应被丢弃');
      expect(store.credits.length, 1, reason: '只有丙那笔合法');
      expect(store.credits.single.customer, '丙');
      expect(r.skipped, greaterThan(0));
    });

    test('恢复被打断（残留标记 + 快照）→ 启动时自动回滚', () async {
      final store = StoreService.instance;
      // 先造一份「恢复前」的完整快照
      store.addProduct(Product(id: 'SP0001', name: '原有的商品'));
      final snapshot = store.exportBackup();

      // 模拟「恢复写到一半被杀进程」：磁盘上已是撕裂状态，标记还在
      SharedPreferences.setMockInitialValues({
        'sk_seeded': true,
        'sk_products': jsonEncode([
          {'id': 'SP9999', 'name': '备份里的新商品'}
        ]),
        'sk_sales': '{}',
        'sk_credits': '[]',
        'sk_restoring': true,
        'sk_restore_snapshot': snapshot,
      });
      await store.load();

      expect(store.restoreInterrupted, isTrue);
      expect(store.products.single.name, '原有的商品',
          reason: '必须回滚到恢复前的快照，而不是留在撕裂状态');
    });
  });

  group('4.2.3 修复回归', () {
    test('中断自愈：回滚结果必须写回磁盘，不能只改内存', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '原有的商品'));
      final snapshot = store.exportBackup();

      SharedPreferences.setMockInitialValues({
        'sk_seeded': true,
        'sk_products': jsonEncode([
          {'id': 'SP9999', 'name': '撕裂状态的新商品'}
        ]),
        'sk_sales': '{}',
        'sk_credits': '[]',
        'sk_restoring': true,
        'sk_restore_snapshot': snapshot,
      });
      await store.load();

      expect(store.restoreInterrupted, isTrue);
      expect(store.products.single.name, '原有的商品');

      // 关键：磁盘也得改成回滚后的数据。旧实现只换内存、直接清标记，
      // 用户重启后读到的是「新商品 + 旧营业额」的撕裂状态。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sk_restoring'), isFalse, reason: '写盘成功才清标记');
      final onDisk = jsonDecode(prefs.getString('sk_products')!) as List;
      expect(onDisk.single['name'], '原有的商品',
          reason: '磁盘上不能还留着撕裂状态的数据');
    });

    test('v3 备份缺 credits / 类型不对 → 同样要确认，不能静默清空欠账', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '白菜'));
      store.addCredit(
          Credit(id: 'c1', customer: '王婶', amount: 100, date: '2026-07-01'));

      // 一份「version 是 3、但 credits 键被裁掉」的备份：
      // 工具裁剪、手工编辑、传输截断都可能造成这种文件。
      final v3NoCredits = jsonEncode({
        'version': 3,
        'exportedAt': '2026-07-02T00:00:00.000',
        'products': [
          {'id': 'SP0009', 'name': '备份里的商品'}
        ],
        'categories': <String>[],
        'sales': {
          '2026-07-01': {
            'date': '2026-07-01',
            'items': [
              {
                'id': 's1',
                'name': '旧账',
                'quantity': 1,
                'unitPrice': 3,
                'totalPrice': 3,
              },
            ],
          },
        },
      });

      final blocked = await store.importBackup(v3NoCredits);
      expect(blocked.ok, isFalse, reason: 'version 是 3 也不能绕过确认');
      expect(blocked.needsConfirm, isTrue);
      expect(store.credits.length, 1, reason: '欠账不能被静默清空');
      expect(store.products.single.name, '白菜');

      // credits 存在但类型不对（不是数组）→ 同样要确认
      final wrongType = jsonEncode({
        'version': 3,
        'products': [
          {'id': 'SP0009', 'name': '备份里的商品'}
        ],
        'categories': <String>[],
        'sales': {
          '2026-07-01': {
            'date': '2026-07-01',
            'items': [
              {
                'id': 's1',
                'name': '旧账',
                'quantity': 1,
                'unitPrice': 3,
                'totalPrice': 3,
              },
            ],
          },
        },
        'credits': {'oops': true},
      });
      final blocked2 = await store.importBackup(wrongType);
      expect(blocked2.needsConfirm, isTrue);
      expect(store.credits.length, 1);

      // 用户确认后才真的清空
      final forced = await store.importBackup(v3NoCredits, allowDataLoss: true);
      expect(forced.ok, isTrue);
      expect(store.credits, isEmpty);
    });

    test('备份里没有任何营业额记录 → 拒绝恢复，不能静默清空营业额', () async {
      final store = StoreService.instance;
      store.addProduct(Product(id: 'SP0001', name: '白菜'));
      store.upsertSaleItem(
          '2026-07-01',
          SaleItem(
              id: 's1',
              name: '白菜',
              quantity: 2,
              unitPrice: 3,
              totalPrice: 6));
      expect(store.sales.length, 1);

      final noSales = jsonEncode({
        'version': 3,
        'exportedAt': '2026-07-02T00:00:00.000',
        'products': [
          {'id': 'SP0009', 'name': '备份里的商品'}
        ],
        'categories': <String>[],
        'sales': <String, dynamic>{},
        'credits': <dynamic>[],
      });

      final blocked = await store.importBackup(noSales);
      expect(blocked.ok, isFalse);
      expect(blocked.needsConfirm, isTrue);
      expect(store.sales.length, 1, reason: '营业额不能被静默清空');
      expect(store.products.single.name, '白菜');

      // 确认后确实能恢复成「没有营业额」的状态
      final forced = await store.importBackup(noSales, allowDataLoss: true);
      expect(forced.ok, isTrue);
      expect(store.sales, isEmpty);
      expect(store.products.single.name, '备份里的商品');
    });

    test('非法日期键（2026-02-31）整条丢弃，不会跑到别的日期', () async {
      final store = StoreService.instance;
      final text = jsonEncode({
        'version': 3,
        'products': [
          {'id': 'SP0001', 'name': '白菜'}
        ],
        'categories': <String>[],
        'sales': {
          '2026-02-31': {
            'date': '2026-02-31',
            'items': [
              {
                'id': 'x',
                'name': '白菜',
                'quantity': 1,
                'unitPrice': 2,
                'totalPrice': 2,
              },
            ],
          },
          '2026-07-01': {
            'date': '2026-07-01',
            'items': [
              {
                'id': 'y',
                'name': '白菜',
                'quantity': 1,
                'unitPrice': 3,
                'totalPrice': 3,
              },
            ],
          },
        },
        'credits': <dynamic>[],
      });

      final r = await store.importBackup(text);
      expect(r.ok, isTrue);
      expect(store.sales.keys, ['2026-07-01'],
          reason: '2 月没有 31 号，那天整条应被丢弃');
    });

    test('CSV 导入：名称 / 分类 / 品牌为空时不覆盖原值', () {
      final store = StoreService.instance;
      store.addProduct(Product(
        id: 'SP0001',
        name: '农夫山泉',
        category: '饮料',
        brand: '农夫',
        barcode: '6901',
        retailPrice: 2,
        purchasePrice: 1,
      ));

      // 条码对得上、但其余文本列都是空的 CSV 行
      final r = store.importProducts([
        Product(id: '', name: '', category: '', brand: '', barcode: '6901'),
      ]);

      expect(r.overwritten, 1);
      expect(store.products.single.name, '农夫山泉', reason: '空名称不能把原名清掉');
      expect(store.products.single.category, '饮料');
      expect(store.products.single.brand, '农夫');
      expect(store.products.single.retailPrice, 2, reason: '价格空值同样保留');
      expect(store.products.single.purchasePrice, 1);
    });

    test('分类不存在时 renameCategory 返回 false，不抛 RangeError', () {
      final store = StoreService.instance;
      expect(store.renameCategory('不存在的分类', '新名字'), isFalse);
    });

    test('CSV 公式注入防护：= 开头的名称导出后被中和，导入能还原', () {
      final p = Product(id: 'SP1', name: '=SUM(A1:A9)', barcode: '');
      final row = p.toCsvRow();
      expect(row[1], "'=SUM(A1:A9)",
          reason: 'Excel 会把 = 开头的内容当公式执行，必须前置单引号');
      // 往返一致：App 自己导入时要能还原成原名
      expect(Product.fromCsvRow(row).name, '=SUM(A1:A9)');
    });
  });
}
