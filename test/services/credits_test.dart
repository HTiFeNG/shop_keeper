// 欠账台账测试：登记 / 结清 / 撤销 / 按人汇总 / 备份。
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/models/credit.dart';
import 'package:shop_keeper/services/store_service.dart';

import '../helpers/store_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStore();
  });

  Credit credit(String id, String who, double amount, String date,
          {bool settled = false, String? settledDate}) =>
      Credit(
        id: id,
        customer: who,
        amount: amount,
        date: date,
        settled: settled,
        settledDate: settledDate,
      );

  test('未结清合计只算没还的', () {
    final store = StoreService.instance;
    store.addCredit(credit('c1', '王婶', 25.5, '2026-07-01'));
    store.addCredit(credit('c2', '张老师', 10, '2026-07-02'));
    store.addCredit(credit('c3', '老李', 99, '2026-06-01',
        settled: true, settledDate: '2026-06-10'));

    expect(store.unsettledCreditTotal, 35.5);
    expect(store.unsettledCredits().length, 2);
    expect(store.settledCredits().single.customer, '老李');
  });

  test('未结清按挂账日期升序（挂最久的排最前，便于催收）', () {
    final store = StoreService.instance;
    store.addCredit(credit('c1', '后来欠的', 10, '2026-07-20'));
    store.addCredit(credit('c2', '最早欠的', 10, '2026-07-01'));
    store.addCredit(credit('c3', '中间欠的', 10, '2026-07-10'));

    expect(store.unsettledCredits().map((c) => c.customer).toList(),
        ['最早欠的', '中间欠的', '后来欠的']);
  });

  test('结清 / 撤销结清：金额始终参与同一套合计', () {
    final store = StoreService.instance;
    store.addCredit(credit('c1', '王婶', 30, '2026-07-01'));
    expect(store.unsettledCreditTotal, 30);

    store.settleCredit('c1', date: '2026-07-08');
    expect(store.unsettledCreditTotal, 0);
    expect(store.settledCredits().single.settledDate, '2026-07-08');

    store.unsettleCredit('c1');
    expect(store.unsettledCreditTotal, 30);
    expect(store.settledCredits(), isEmpty);
  });

  test('按人汇总：合并同一客户的多笔，欠得多的排前面', () {
    final store = StoreService.instance;
    store.addCredit(credit('c1', '王婶', 10, '2026-07-01'));
    store.addCredit(credit('c2', '王婶', 15, '2026-07-05'));
    store.addCredit(credit('c3', '张老师', 5, '2026-06-20'));

    final byCustomer = store.creditsByCustomer();
    expect(byCustomer.length, 2);
    expect(byCustomer.first.customer, '王婶');
    expect(byCustomer.first.total, 25);
    expect(byCustomer.first.count, 2);
    expect(byCustomer.first.oldestDate, '2026-07-01');
    // 张老师虽只有一笔，但挂得最久
    expect(byCustomer.last.customer, '张老师');
    expect(byCustomer.last.oldestDate, '2026-06-20');
  });

  test('没填姓名的欠账在汇总里归入占位分组，不会丢', () {
    final store = StoreService.instance;
    store.addCredit(credit('c1', '', 12, '2026-07-01'));
    final byCustomer = store.creditsByCustomer();
    expect(byCustomer.single.customer, '（未填写姓名）');
    expect(byCustomer.single.total, 12);
  });

  test('编辑与删除', () {
    final store = StoreService.instance;
    store.addCredit(credit('c1', '王婶', 10, '2026-07-01'));
    store.updateCredit(store.credits.single.copyWith(amount: 20, note: '加了瓶酒'));
    expect(store.credits.single.amount, 20);
    expect(store.credits.single.note, '加了瓶酒');

    store.deleteCredit('c1');
    expect(store.credits, isEmpty);
  });

  test('欠账不参与营业额统计（同一笔钱不能被记两次）', () {
    final store = StoreService.instance;
    store.addCredit(credit('c1', '王婶', 100, '2026-07-01'));
    expect(store.dayTotal('2026-07-01'), 0);
    expect(store.monthlyStats('2026-07').totalRevenue, 0);
  });

  test('欠账会持久化：重新 load 后还在', () async {
    final store = StoreService.instance;
    store.addCredit(credit('c1', '王婶', 25.5, '2026-07-01', settled: false));
    store.settleCredit('c1');
    // 等落盘（_save 是发射后不管，这里让出事件循环）
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await store.load();
    expect(store.credits.single.customer, '王婶');
    expect(store.credits.single.settled, isTrue);
  });
}
