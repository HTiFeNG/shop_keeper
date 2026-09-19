// 商品检索测试：汉字、全拼、拼音首字母、品牌、条码，以及相关度排序。
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/utils/search.dart';

void main() {
  group('匹配', () {
    test('汉字直接包含', () {
      expect(SearchIndex.matches(query: '可乐', name: '可口可乐'), isTrue);
      expect(SearchIndex.matches(query: '矿泉', name: '农夫山泉矿泉水'), isTrue);
    });

    test('拼音首字母', () {
      // 店主手停在收银台上，输入法常常还在英文状态
      expect(SearchIndex.matches(query: 'kl', name: '可乐'), isTrue);
      expect(SearchIndex.matches(query: 'kkkl', name: '可口可乐'), isTrue);
      expect(SearchIndex.matches(query: 'nfsq', name: '农夫山泉'), isTrue);
      expect(SearchIndex.matches(query: 'whh', name: '娃哈哈'), isTrue);
    });

    test('全拼', () {
      expect(SearchIndex.matches(query: 'kele', name: '可乐'), isTrue);
      expect(SearchIndex.matches(query: 'nongfu', name: '农夫山泉'), isTrue);
      expect(SearchIndex.matches(query: 'kuangquanshui', name: '矿泉水'), isTrue);
    });

    test('中英数字混排：字母数字部分照常匹配', () {
      expect(SearchIndex.matches(query: '500', name: '可乐500ml'), isTrue);
      expect(SearchIndex.matches(query: 'kl500', name: '可乐500ml'), isTrue);
      expect(SearchIndex.matches(query: 'ml', name: '可乐500ml'), isTrue);
    });

    test('品牌与条码', () {
      expect(
          SearchIndex.matches(query: '农夫', name: '矿泉水', brand: '农夫山泉'),
          isTrue);
      expect(
          SearchIndex.matches(query: 'nfsq', name: '矿泉水', brand: '农夫山泉'),
          isTrue);
      expect(
          SearchIndex.matches(query: '6901', name: '矿泉水', barcode: '6901234'),
          isTrue);
    });

    test('不匹配就是 0，不会误报', () {
      expect(SearchIndex.matches(query: 'xyz', name: '矿泉水'), isFalse);
      expect(SearchIndex.matches(query: '啤酒', name: '矿泉水'), isFalse);
      expect(SearchIndex.score(query: '啤酒', name: '矿泉水'), 0);
    });

    test('查询串里带空格也能匹配（归一化）', () {
      expect(SearchIndex.matches(query: ' 可 乐 ', name: '可乐'), isTrue);
      expect(SearchIndex.normalize('  可 乐  '), '可乐');
    });

    test('空查询视为全部命中', () {
      expect(SearchIndex.score(query: '', name: '任意'), greaterThan(0));
      expect(SearchIndex.score(query: '   ', name: '任意'), greaterThan(0));
    });
  });

  group('相关度排序', () {
    test('名字完全相同的排最前', () {
      final a = SearchIndex.score(query: '可乐', name: '可乐');
      final b = SearchIndex.score(query: '可乐', name: '可口可乐');
      final c = SearchIndex.score(query: '可乐', name: '零度可乐大瓶');
      expect(a, greaterThan(b));
      // b 和 c 都只是「名字里含可乐」，同级；a 必须明显高于它们
      expect(b, greaterThanOrEqualTo(c));
      expect(a - b, greaterThan(0));
    });

    test('名称前缀匹配优于中间包含', () {
      expect(
        SearchIndex.score(query: '可乐', name: '可乐味糖'),
        greaterThan(SearchIndex.score(query: '可乐', name: '大瓶可乐')),
      );
    });

    test('拼音首字母完全命中优于部分命中', () {
      // 「可乐」首字母 kl 完全命中 > 「可口可乐」首字母 kkkl 只是包含
      expect(
        SearchIndex.score(query: 'kl', name: '可乐'),
        greaterThan(SearchIndex.score(query: 'kl', name: '可口可乐')),
      );
    });

    test('条码完全命中优先级很高', () {
      expect(
        SearchIndex.score(query: '6901234', name: '随便什么', barcode: '6901234'),
        greaterThan(60),
      );
    });
  });

  group('缓存', () {
    test('同一个词反复查询只建一次索引，且不会无限增长', () {
      final before = SearchIndex.cacheSize;
      for (var i = 0; i < 500; i++) {
        SearchIndex.matches(query: 'kl', name: '商品$i');
      }
      // 500 个不同词 → 缓存里有 500 条；再查同样 500 个词不应增加
      final mid = SearchIndex.cacheSize;
      for (var i = 0; i < 500; i++) {
        SearchIndex.matches(query: 'kl', name: '商品$i');
      }
      expect(SearchIndex.cacheSize, mid);
      expect(mid, greaterThan(before));
    });

    test('生僻字 / 异常字符不会让检索抛异常', () {
      expect(() => SearchIndex.matches(query: 'a', name: '𠮷野家'), returnsNormally);
      expect(() => SearchIndex.score(query: 'x', name: ''), returnsNormally);
    });
  });
}
