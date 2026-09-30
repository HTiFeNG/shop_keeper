import 'package:flutter/material.dart';

import '../services/backup_codec.dart';
import '../theme/app_theme.dart';

/// 恢复备份时的「会清空欠账」二次确认。
///
/// v2 老备份没有欠账（credits）字段，直接恢复会把现有欠账整体清空。
/// [StoreService.importBackup] 默认拒绝这种情况并返回
/// [RestoreResult.needsCreditConfirm]，由这里问过用户后再带
/// `allowCreditLoss: true` 重来一次。
///
/// 返回 true 表示用户明确同意「欠账会被清空，仍要恢复」。
Future<bool> confirmCreditLoss(BuildContext context, RestoreResult r) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('这份备份不含欠账数据'),
      content: Text('${r.reason}\n\n'
          '商品、分类和营业额会按备份恢复；欠账记录会被清空。\n'
          '确定继续吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.priceRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('仍要恢复'),
        ),
      ],
    ),
  );
  return ok == true;
}
