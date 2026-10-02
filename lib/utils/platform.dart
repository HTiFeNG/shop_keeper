/// 平台能力判断（集中一处，避免各页面各抄一份）。
library;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// 当前平台是否支持摄像头扫码。
///
/// 只有 Android / iOS 具备可用的扫码能力；Web 端 mobile_scanner 不可用、
/// 桌面端没有摄像头 API，一律返回 false（界面据此隐藏扫码入口）。
///
/// 之所以抽成公共判断：此前 `sales_page` / `product_manage_page` /
/// `product_edit_page` 各写了一份逐字相同的 `_canScan`，`scan_page` 里还有
/// 第四份。改一处很容易漏掉其余几处 —— 例如将来要放开 Web 版扫码，
/// 只改一个文件就会造成「有的页面能扫、有的不能」。
bool get canUseCameraScanner =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
