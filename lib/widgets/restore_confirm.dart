import 'package:flutter/material.dart';

import '../services/backup_codec.dart';
import '../theme/app_theme.dart';

/// 恢复备份时的「会清空本机现有数据」二次确认。
///
/// 两类场景会走到这里（都由 [StoreService.importBackup] 拒绝并给出
/// [RestoreResult.lossWarning]）：
/// - 备份里没有可用的欠账数据（v2 老备份没有该字段，或 v3 的字段缺失 / 类型不对）
/// - 备份里没有任何营业额记录，而本机有
///
/// 问过用户后，调用方带 `allowDataLoss: true` 重来一次。
///
/// 返回 true 表示用户明确同意「数据会被清空，仍要恢复」。
Future<bool> confirmRestoreLoss(BuildContext context, RestoreResult r) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('恢复会清空本机现有数据'),
      content: Text('${r.lossWarning ?? r.reason}\n\n'
          '商品、分类和营业额会按备份里的内容整体替换。\n'
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
