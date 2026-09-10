# 店铺管家（shop_keeper）

商品管理 × 营业额记录 合并 App —— 一站式守店工具（Android + Web）。

## 功能概览

- **营业额（首页）**：日期切换记账、从商品库选品自动带价、数量步进、总价自动/手动解绑、删除 5 秒撤销、常用商品（星标）一键记账；记销售自动扣库存（允许负数）。
- **月度统计**：月总营收 / 日均 / 最高日 / 总件数四宫格、柱状图（点柱子跳当日）、环比、商品排行、估算毛利。
- **导出**：Android 导 Excel 双 Sheet（当日明细 + 月度汇总）经系统分享；Web 导 CSV 浏览器下载；商品 CSV 导入导出；全量数据备份 / 恢复（JSON）。
- **商品管理**：8 字段商品模型 + 星标收藏、分类管理（增删改排序）、实时搜索、批量操作、缺进价提醒、扫码（仅 Android）。

## 技术栈

Flutter 3.47（Dart ^3.13），shared_preferences / localStorage 持久化（键名 `sk_` 前缀），fl_chart 图表，excel 包（仅非 Web 端 conditional import）。

## 构建

```bash
flutter pub get
flutter build apk --release   # Android APK → build/app/outputs/flutter-apk/
flutter build web --release   # Web 版 → build/web/（可安装 PWA）
```
