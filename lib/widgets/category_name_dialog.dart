import 'package:flutter/material.dart';

import '../services/store_constants.dart';

/// 「新建分类 / 重命名分类」输入对话框。
///
/// 抽出来是因为有三处要用：商品页的「＋分类」、分类管理面板里的改名、以及
/// 分类选择面板里的「新建分类」。原先这段校验逻辑只存在于商品页一处，
/// 另两处要么复制一份、要么绕过校验，都会让「重名分类」漏进来。
///
/// 返回：确定 → 去掉首尾空格后的分类名；取消或没输入 → null。
Future<String?> showCategoryNameDialog(
  BuildContext context, {
  String title = '添加分类',
  String initial = '',
  String? oldName,
  List<String> existing = const [],
}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setStateDialog) {
          // 输入框内容变化时清掉上一次的报错，否则用户改对了还红着
          void clearError() {
            if (error != null) setStateDialog(() => error = null);
          }

          void submit() {
            final name = ctrl.text.trim();
            if (name.isEmpty) {
              setStateDialog(() => error = '请输入分类名称');
              return;
            }
            // 「全部」「未分类」是系统伪分类，不能被用户占用
            if (name == kCategoryAll || name == kCategoryNone) {
              setStateDialog(() => error = '「$name」是系统保留名称');
              return;
            }
            if (existing.contains(name) && name != oldName) {
              setStateDialog(() => error = '该分类已存在');
              return;
            }
            Navigator.pop(ctx, name);
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: '请输入分类名称',
                errorText: error,
              ),
              onChanged: (_) => clearError(),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(onPressed: submit, child: const Text('确定')),
            ],
          );
        },
      );
    },
  );
  // 对话框关闭后还有一小段退出动画在跑，此时立刻 dispose 会让 TextField
  // 用到已释放的 controller，所以等动画放完再释放。
  // （此前是根本不释放 —— 每次新建 / 改名分类都会漏一个 controller。）
  Future<void>.delayed(const Duration(milliseconds: 400), ctrl.dispose);
  return result;
}
