/// 全局常量：与持久化 / 分类语义相关，被多个模块共用。
///
/// 单独成文件是为了打破循环依赖：StoreService 与 BackupCodec 都需要这两个
/// 常量，而 BackupCodec 又被 StoreService 引用。页面照旧从 store_service.dart
/// 导入即可（那里做了 re-export）。
library;

/// 固定分类名：不可删除、不可重命名
const String kCategoryAll = '全部';
const String kCategoryNone = '未分类';
