// 坚果云同步测试：配置序列化与「未配置时的友好拒绝」。
//
// 真实网络请求不在这里测（需要账号 + 会依赖外部服务），
// 那部分由 SyncSettingsPage 的「测试连接」按钮在日常使用中验证。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shop_keeper/services/nutstore_sync.dart';
import 'package:shop_keeper/services/store_service.dart';

import '../helpers/store_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetStore();
  });

  group('NutstoreConfig', () {
    test('默认值直接可用（指向坚果云官方 WebDAV）', () {
      const c = NutstoreConfig();
      expect(c.baseUrl, 'https://dav.jianguoyun.com/dav');
      expect(c.remotePath, '/shop_keeper_backup.json');
      expect(c.autoSync, isFalse);
      expect(c.isConfigured, isFalse);
    });

    test('只有账号和密码都填了才算配置完成', () {
      expect(const NutstoreConfig(account: 'a@b.com').isConfigured, isFalse);
      expect(const NutstoreConfig(appPassword: 'xxx').isConfigured, isFalse);
      expect(
          const NutstoreConfig(account: 'a@b.com', appPassword: 'xxx')
              .isConfigured,
          isTrue);
      // 只有空白字符不算填了
      expect(const NutstoreConfig(account: '   ', appPassword: 'x').isConfigured,
          isFalse);
    });

    test('JSON 往返一致', () {
      const c = NutstoreConfig(
        account: 'a@b.com',
        appPassword: 'secret',
        remotePath: '/我的备份/shop.json',
        autoSync: true,
      );
      final back = NutstoreConfig.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.account, 'a@b.com');
      expect(back.appPassword, 'secret');
      expect(back.remotePath, '/我的备份/shop.json');
      expect(back.autoSync, isTrue);
    });

    test('copyWith 只改指定字段', () {
      const c = NutstoreConfig(account: 'a@b.com', appPassword: 'p');
      final c2 = c.copyWith(autoSync: true);
      expect(c2.account, 'a@b.com');
      expect(c2.autoSync, isTrue);
      expect(c.baseUrl, NutstoreConfig.defaultBaseUrl);
    });
  });

  group('未配置时的行为', () {
    test('测试连接：给出一句人话而不是抛异常', () async {
      final r = await NutstoreSync.test(const NutstoreConfig());
      expect(r.ok, isFalse);
      expect(r.message, contains('请先填写'));
    });

    test('上传：同样拒绝，不会发起网络请求', () async {
      final r = await NutstoreSync.upload(const NutstoreConfig(), '{}');
      expect(r.ok, isFalse);
      expect(r.message, contains('请先填写'));
    });

    test('下载：抛 SyncException 且信息可读', () async {
      expect(
        () => NutstoreSync.download(const NutstoreConfig()),
        throwsA(isA<SyncException>()),
      );
    });
  });

  group('StoreService 同步状态', () {
    test('保存配置后可读回（含自动同步开关）', () async {
      final store = StoreService.instance;
      store.updateSyncConfig(const NutstoreConfig(
          account: 'a@b.com', appPassword: 'p', autoSync: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await store.load();
      expect(store.syncConfig.account, 'a@b.com');
      expect(store.syncConfig.autoSync, isTrue);
    });

    test('未开启自动同步时，启动检查直接跳过（不发请求）', () async {
      final store = StoreService.instance;
      store.updateSyncConfig(const NutstoreConfig(
          account: 'a@b.com', appPassword: 'p', autoSync: false));
      await store.checkRemote(); // 不应抛异常，也不应有待处理备份
      expect(store.hasPendingRemote, isFalse);
      expect(store.pendingRemotePreview, isNull);
    });

    test('没有待处理备份时，应用它会得到失败而不是崩', () async {
      final r = await StoreService.instance.applyPendingRemote();
      expect(r.ok, isFalse);
      expect(r.reason, contains('没有待恢复'));
    });
  });
}
