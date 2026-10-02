import 'package:flutter/material.dart';

/// 轻提示（保存成功、已导出之类的普通信息）。
///
/// 抽出来的原因：`sales_page` / `product_manage_page` / `sync_settings_page`
/// 原本各写了一份几乎逐字相同的 `_toast`，而三份的停留时长还不一样
/// （同步页 2 秒、其余 3 秒）。集中之后行为只在一处定义。
///
/// 用 [BuildContext.mounted] 而不是 State 的 `mounted`，这样在没有 State 的
/// 场景（工具函数、回调）也能安全调用；跨 await 之后调用则不会 setState 到
/// 已卸载的树。
void showToast(BuildContext context, String msg, {int seconds = 3}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), duration: Duration(seconds: seconds)));
}

/// 失败提示：一句人话 + 更久停留 + 可选的「重试」按钮。
///
/// 刻意不把 `$e` 这种裸异常丢给用户 —— 目标用户是中老年店主，
/// 「SocketException: Connection refused」对他们等于没信息。
/// 需要给人看的错误请在这里传成一句中文，并把技术细节留在日志侧。
void showToastErr(
  BuildContext context,
  String msg, {
  Future<void> Function()? retry,
  int seconds = 6,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(seconds: seconds),
      action: retry == null
          ? null
          : SnackBarAction(label: '重试', onPressed: () => retry()),
    ));
}
