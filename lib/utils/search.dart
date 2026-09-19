/// 商品检索：汉字全拼 / 首字母 / 名称 / 品牌 / 条码 混合匹配 + 相关度排序。
///
/// 为什么要拼音：店主找货时手还在收银台上，输入法往往停在英文状态。
/// 输 `kl` 就能出「可口可乐」，比切中文输入法逐字打快得多。
///
/// 性能：拼音转换（尤其是全拼）对整张商品表逐字算一次是有成本的，
/// 「几百个商品 × 每敲一个字重算一遍」会让输入明显发卡。这里按**词**做缓存
/// （商品名重复率高，例如一堆「可乐」「矿泉水」），命中缓存后每键只剩字符串比较。
library;

import 'package:lpinyin/lpinyin.dart';

/// 一个字符串的检索索引（全部小写）。
class _TextIndex {
  _TextIndex(this.raw, this.full, this.initials);

  final String raw; // 原文小写
  final String full; // 全拼（无声调、无分隔符），非汉字原样保留
  final String initials; // 拼音首字母，非汉字原样保留

  bool contains(String q) =>
      raw.contains(q) || full.contains(q) || initials.contains(q);
}

abstract final class SearchIndex {
  /// 词 → 索引 缓存。超出上限整体清空（简单、无额外依赖，商品名规模下够用）。
  static final Map<String, _TextIndex> _cache = {};
  static const int _maxCache = 4000;

  /// 归一化查询串：小写 + 去掉空格（「可 乐」也能匹配「可乐」）
  static String normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static _TextIndex _index(String text) {
    final hit = _cache[text];
    if (hit != null) return hit;

    String full = '';
    String initials = '';
    if (text.isNotEmpty) {
      try {
        full = PinyinHelper.getPinyinE(
          text,
          separator: '',
          format: PinyinFormat.WITHOUT_TONE,
        ).toLowerCase();
        initials = PinyinHelper.getShortPinyin(text).toLowerCase();
      } catch (_) {
        // 极端字符（生僻字 / 代理对）转换失败时退回纯文本匹配，
        // 不能让搜索整体抛异常。
        full = '';
        initials = '';
      }
    }
    final idx = _TextIndex(text.toLowerCase(), full, initials);
    if (_cache.length >= _maxCache) _cache.clear();
    _cache[text] = idx;
    return idx;
  }

  /// 相关度打分。0 = 不匹配，越大越靠前。
  ///
  /// 排序的意义：搜「可乐」，名字就叫「可乐」的商品必须排在
  /// 「可口可乐香草味」前面，否则结果里第一屏全是长名字的旁支。
  static int score({
    required String query,
    required String name,
    String brand = '',
    String barcode = '',
  }) {
    final q = normalize(query);
    if (q.isEmpty) return 1;

    final n = name.toLowerCase();
    if (n == q) return 100;
    if (barcode.isNotEmpty && barcode.toLowerCase() == q) return 96;
    if (n.startsWith(q)) return 90;
    if (n.contains(q)) return 80;
    if (barcode.isNotEmpty && barcode.toLowerCase().contains(q)) return 70;

    final ni = _index(name);
    if (ni.initials.startsWith(q)) return 62;
    if (ni.initials.contains(q)) return 54;
    if (ni.full.startsWith(q)) return 46;
    if (ni.full.contains(q)) return 38;

    if (brand.isNotEmpty) {
      final b = brand.toLowerCase();
      if (b.startsWith(q)) return 30;
      if (b.contains(q)) return 26;
      final bi = _index(brand);
      if (bi.contains(q)) return 20;
    }
    return 0;
  }

  /// 是否匹配（调用方不需要排序时用这个，比 score > 0 语义更清楚）
  static bool matches({
    required String query,
    required String name,
    String brand = '',
    String barcode = '',
  }) =>
      score(query: query, name: name, brand: brand, barcode: barcode) > 0;

  /// 调试 / 测试用：当前缓存条目数
  static int get cacheSize => _cache.length;
}
