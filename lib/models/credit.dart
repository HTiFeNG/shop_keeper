import 'package:flutter/foundation.dart';

/// 一笔赊账（欠账）。
///
/// 村里小卖部最常见的往来：熟客拿两包烟说「月底一起给」，先记着。
/// 本模块只做**台账**——登记、查看、标记结清，不参与营业额统计
/// （赊出去的货不算当天收入，收回来的钱也不算当天收入，
/// 否则营业额会被同一笔钱重复计两次）。
@immutable
class Credit {
  const Credit({
    required this.id,
    required this.customer,
    required this.amount,
    required this.date,
    this.note = '',
    this.settled = false,
    this.settledDate,
  });

  final String id;
  final String customer; // 客户称呼（如「王婶」「小学门口张老师」）
  final double amount; // 欠款金额
  final String date; // 赊账日期 'YYYY-MM-DD'
  final String note; // 备注（拿了什么）
  final bool settled; // 是否已结清
  final String? settledDate; // 结清日期 'YYYY-MM-DD'

  /// 唯一 id：微秒时间戳 + 自增，避免同毫秒内连续登记时碰撞
  static int _seq = 0;
  static String newId() =>
      'C${DateTime.now().microsecondsSinceEpoch}-${(_seq++).toRadixString(16)}';

  /// 未结清且已挂账超过 [days] 天 → 视为该催了
  bool isOverdue(int days, {DateTime? now}) {
    if (settled) return false;
    return ageInDays(now: now) >= days;
  }

  /// 挂账天数（结清的按结清日算，未结清的算到今天）
  int ageInDays({DateTime? now}) {
    final ref = now ?? DateTime.now();
    final start = _parse(date);
    final end = settledDate == null ? ref : _parse(settledDate!);
    if (start == null || end == null) return 0;
    return end.difference(start).inDays;
  }

  static DateTime? _parse(String key) {
    final p = key.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Credit copyWith({
    String? customer,
    double? amount,
    String? date,
    String? note,
    bool? settled,
    String? settledDate,
    bool clearSettledDate = false,
  }) =>
      Credit(
        id: id,
        customer: customer ?? this.customer,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        note: note ?? this.note,
        settled: settled ?? this.settled,
        settledDate: clearSettledDate ? null : (settledDate ?? this.settledDate),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer': customer,
        'amount': amount,
        'date': date,
        'note': note,
        'settled': settled,
        'settledDate': settledDate,
      };

  factory Credit.fromJson(Map<String, dynamic> json) => Credit(
        id: json['id'] as String? ?? newId(),
        customer: json['customer'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        date: json['date'] as String? ?? '',
        note: json['note'] as String? ?? '',
        settled: json['settled'] as bool? ?? false,
        settledDate: json['settledDate'] as String?,
      );
}

/// 按客户聚合的欠款（「谁一共欠多少」是最常问的问题）
class CreditByCustomer {
  CreditByCustomer({
    required this.customer,
    required this.total,
    required this.count,
    required this.oldestDate,
  });

  final String customer;
  final double total; // 未结清合计
  final int count; // 未结清笔数
  final String oldestDate; // 最早一笔的日期（催款优先级）
}
