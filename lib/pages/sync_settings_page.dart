import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/nutstore_sync.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart' as du;

/// 坚果云同步设置。
///
/// 手机与电脑共用一个坚果云账号：谁改完点一下「上传到云端」，另一端点
/// 「从云端恢复」，数据就过去了 —— 相当于用坚果云当自己的小服务器。
///
/// 同步是**手动 + 可选的启动检查**，不会静默覆盖本地：
/// 发现云端更新时只在首页提示，恢复与否由用户决定。
class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  final store = StoreService.instance;

  late final TextEditingController _accountCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _pathCtrl;

  bool _showPwd = false;
  String? _busy; // 非 null 表示正在执行某个动作（显示进度文案）

  @override
  void initState() {
    super.initState();
    final c = store.syncConfig;
    _accountCtrl = TextEditingController(text: c.account);
    _pwdCtrl = TextEditingController(text: c.appPassword);
    _pathCtrl = TextEditingController(text: c.remotePath);
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _pwdCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  void _update(NutstoreConfig c) {
    store.updateSyncConfig(c);
    setState(() {});
  }

  NutstoreConfig get _currentConfig => store.syncConfig.copyWith(
        account: _accountCtrl.text,
        appPassword: _pwdCtrl.text,
        remotePath: _pathCtrl.text,
      );

  // ==================== 动作 ====================

  Future<void> _test() async {
    _update(_currentConfig);
    setState(() => _busy = '正在连接坚果云…');
    final r = await store.testSync();
    if (!mounted) return;
    setState(() => _busy = null);
    r.ok ? _toast(r.message) : _toastErr(r.message);
  }

  Future<void> _upload() async {
    _update(_currentConfig);
    if (store.products.isEmpty && store.sales.isEmpty && store.credits.isEmpty) {
      _toastErr('本机还没有任何数据，没什么可上传的');
      return;
    }
    setState(() => _busy = '正在上传…');
    final r = await store.syncUpload();
    if (!mounted) return;
    setState(() => _busy = null);
    if (r.ok) {
      _toast('已上传到云端。另一台设备打开「从云端恢复」就能拿到这份数据');
    } else {
      _toastErr(r.message, retry: _upload);
    }
  }

  Future<void> _download() async {
    _update(_currentConfig);
    setState(() => _busy = '正在读取云端备份…');
    try {
      final file = await store.fetchRemote();
      if (!mounted) return;
      setState(() => _busy = null);

      if (file == null) {
        _toastErr('云端还没有备份文件，请先在本机点「上传到云端」');
        return;
      }
      final preview = store.previewBackup(file.content);
      if (preview == null) {
        _toastErr('云端那份文件不是店铺管家的备份，已取消');
        return;
      }
      final when = preview.exportedAt == null
          ? '未记录'
          : preview.exportedAt!.replaceFirst('T', ' ').split('.').first;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('从云端恢复'),
          content: Text('云端备份包含：\n'
              '· ${preview.productCount} 个商品\n'
              '· ${preview.dayCount} 天的营业额（共 ${preview.itemCount} 条明细）\n'
              '· ${preview.creditCount} 笔欠账\n'
              '· 云端保存时间：$when\n\n'
              '恢复会用云端的【完全覆盖】本机数据。\n'
              '不用担心：恢复前会自动存一份当前数据，之后可以一键撤销。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认恢复'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      setState(() => _busy = '正在恢复…');
      final r = await store.applyRemote(file.content);
      if (!mounted) return;
      setState(() => _busy = null);
      if (r.ok) {
        _toast('已从云端恢复：${r.productCount} 个商品、${r.dayCount} 天记录'
            '（如需反悔可到「商品 → 备份与恢复 → 撤销上次恢复」）');
      } else {
        _toastErr('恢复失败：${r.reason}');
      }
    } on SyncException catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toastErr(e.message, retry: _download);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toastErr('同步出错：$e', retry: _download);
    }
  }

  // ==================== 提示 ====================

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), duration: const Duration(seconds: 5)));
  }

  void _toastErr(String msg, {Future<void> Function()? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 7),
        action: retry == null
            ? null
            : SnackBarAction(label: '重试', onPressed: () => retry()),
      ));
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final configured = _currentConfig.isConfigured;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('跨端同步', style: AppTheme.pageTitle),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (kIsWeb) _webNotice(),
          _statusCard(),
          const SizedBox(height: 12),
          _howToCard(),
          const SizedBox(height: 12),
          _formCard(),
          const SizedBox(height: 12),
          _actionsCard(configured),
        ],
      ),
    );
  }

  Widget _webNotice() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warningSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: AppTheme.warningYellow),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: AppTheme.primaryText),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '网页版受浏览器限制，无法直连坚果云。同步请在手机 App 上操作；'
                '网页端的数据仍可通过「备份文件」手动搬运。',
                style: TextStyle(
                    fontSize: AppTheme.fontCaption,
                    color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
      );

  Widget _statusCard() {
    final last = store.lastSyncAt;
    final err = store.lastSyncError;
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                err != null ? Icons.cloud_off : Icons.cloud_done_outlined,
                size: 20,
                color: err != null ? AppTheme.priceRed : AppTheme.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  err != null ? '上次同步失败' : '同步就绪',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            last == null
                ? '还没有同步过'
                : '上次同步：${du.dateKey(last)} '
                    '${last.hour.toString().padLeft(2, '0')}:'
                    '${last.minute.toString().padLeft(2, '0')}',
            style: AppTheme.caption,
          ),
          if (err != null) ...[
            const SizedBox(height: 4),
            Text(err,
                style: const TextStyle(
                    fontSize: AppTheme.fontCaption,
                    color: AppTheme.priceRed)),
          ],
        ],
      ),
    );
  }

  Widget _howToCard() => Container(
        decoration: AppTheme.cardDecoration,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.help_outline, size: 20, color: AppTheme.primary),
                SizedBox(width: 8),
                Text('怎么拿到应用密码', style: AppTheme.sectionTitle),
              ],
            ),
            const SizedBox(height: 8),
            ..._steps([
              '用电脑浏览器打开坚果云网页版，登录你的账号',
              '右上角头像 → 账户信息 → 安全选项',
              '找到「第三方应用管理」→ 添加应用，名字随便填（如 店铺管家）',
              '生成后会显示一串密码，复制它，粘到下面的「应用密码」里',
            ]),
            const SizedBox(height: 8),
            const Text(
              '注意：这里要的是那串【应用密码】，不是你的坚果云登录密码。'
              '应用密码只给这个 App 用，随时可以在坚果云里删掉，更安全。',
              style: TextStyle(
                  fontSize: AppTheme.fontCaption,
                  color: AppTheme.primaryText),
            ),
          ],
        ),
      );

  List<Widget> _steps(List<String> items) => [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.orangeSurface,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryText)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(items[i], style: AppTheme.caption)),
              ],
            ),
          ),
      ];

  Widget _formCard() {
    final c = store.syncConfig;
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('连接设置', style: AppTheme.sectionTitle),
          const SizedBox(height: 10),
          TextField(
            controller: _accountCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '坚果云账号',
              hintText: '你注册用的邮箱',
              prefixIcon: Icon(Icons.person_outline),
            ),
            onChanged: (_) => _update(_currentConfig),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pwdCtrl,
            obscureText: !_showPwd,
            decoration: InputDecoration(
              labelText: '应用密码',
              hintText: '坚果云生成的第三方应用密码',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: _showPwd ? '隐藏' : '显示',
                icon: Icon(
                    _showPwd ? Icons.visibility_off : Icons.visibility,
                    size: 20),
                onPressed: () => setState(() => _showPwd = !_showPwd),
              ),
            ),
            onChanged: (_) => _update(_currentConfig),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pathCtrl,
            decoration: const InputDecoration(
              labelText: '云端存放路径',
              hintText: NutstoreConfig.defaultRemotePath,
              prefixIcon: Icon(Icons.folder_outlined),
            ),
            onChanged: (_) => _update(_currentConfig),
          ),
          const SizedBox(height: 4),
          const Text('两台设备填一样的路径才能对上同一份数据',
              style: AppTheme.caption),
          const Divider(height: 24, color: AppTheme.divider),
          // SwitchListTile 内部是 ListTile，会把水波纹画到最近的 Material 上。
          // 卡片本身是带底色的 DecoratedBox，会挡住水波纹（Flutter 会直接
          // 抛断言），所以给它垫一层透明 Material。
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: c.autoSync,
              activeThumbColor: AppTheme.primary,
              title: const Text('启动时检查云端更新',
                  style: TextStyle(fontSize: 15)),
              subtitle: const Text('只提示、不自动覆盖本机数据',
                  style: AppTheme.caption),
              onChanged: (v) => _update(c.copyWith(autoSync: v)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsCard(bool configured) {
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy != null) ...[
            Row(
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(child: Text(_busy!, style: AppTheme.caption)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryText,
              side: const BorderSide(color: AppTheme.primary),
              minimumSize: const Size(0, 48),
            ),
            onPressed: (_busy != null || !configured) ? null : _test,
            icon: const Icon(Icons.wifi_tethering, size: 20),
            label: const Text('测试连接', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (_busy != null || !configured) ? null : _upload,
            icon: const Icon(Icons.cloud_upload_outlined, size: 20),
            label: const Text('上传到云端（本机 → 云端）',
                style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryText,
              side: const BorderSide(color: AppTheme.primary),
              minimumSize: const Size(0, 48),
            ),
            onPressed: (_busy != null || !configured) ? null : _download,
            icon: const Icon(Icons.cloud_download_outlined, size: 20),
            label: const Text('从云端恢复（云端 → 本机）',
                style: TextStyle(fontSize: 15)),
          ),
          if (!configured) ...[
            const SizedBox(height: 8),
            const Text('填好账号和应用密码后即可使用',
                style: AppTheme.caption, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
