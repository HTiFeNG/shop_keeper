/// 坚果云 WebDAV 跨端同步。
///
/// 为什么用坚果云而不是自建服务器：用户手上没有服务器，但有坚果云账号。
/// 坚果云开放标准 WebDAV（`https://dav.jianguoyun.com/dav`），
/// 用「账号 + 第三方应用密码」做 Basic 认证，存取一个固定路径的 JSON 文件，
/// 就等价于有一台属于自己的小服务器。
///
/// 只用到三个动作，刻意不引入 webdav_client 这类完整客户端：
/// - `PROPFIND` 测连通 / 看远端是否存在
/// - `GET`      取回备份
/// - `PUT`      上传备份（必要时先 `MKCOL` 建目录）
///
/// 注意：Web 端会被浏览器 CORS 拦截（坚果云不返回 CORS 头），
/// 同步能力**只在 Android / 桌面端可用**，Web 上会给出明确提示。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// 坚果云连接配置
class NutstoreConfig {
  const NutstoreConfig({
    this.baseUrl = defaultBaseUrl,
    this.account = '',
    this.appPassword = '',
    this.remotePath = defaultRemotePath,
    this.autoSync = false,
  });

  static const String defaultBaseUrl = 'https://dav.jianguoyun.com/dav';
  static const String defaultRemotePath = '/shop_keeper_backup.json';

  final String baseUrl; // WebDAV 根地址
  final String account; // 坚果云登录邮箱
  final String appPassword; // 「安全选项 → 第三方应用管理」里生成的应用密码
  final String remotePath; // 远端文件路径（相对 baseUrl）
  final bool autoSync; // 启动时自动比对并拉取较新的一份

  bool get isConfigured =>
      account.trim().isNotEmpty && appPassword.trim().isNotEmpty;

  NutstoreConfig copyWith({
    String? baseUrl,
    String? account,
    String? appPassword,
    String? remotePath,
    bool? autoSync,
  }) =>
      NutstoreConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        account: account ?? this.account,
        appPassword: appPassword ?? this.appPassword,
        remotePath: remotePath ?? this.remotePath,
        autoSync: autoSync ?? this.autoSync,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'account': account,
        'appPassword': appPassword,
        'remotePath': remotePath,
        'autoSync': autoSync,
      };

  factory NutstoreConfig.fromJson(Map<String, dynamic> j) => NutstoreConfig(
        baseUrl: j['baseUrl'] as String? ?? defaultBaseUrl,
        account: j['account'] as String? ?? '',
        appPassword: j['appPassword'] as String? ?? '',
        remotePath: j['remotePath'] as String? ?? defaultRemotePath,
        autoSync: j['autoSync'] as bool? ?? false,
      );
}

/// 一次同步动作的结果
class SyncResult {
  SyncResult.ok(this.message) : ok = true;
  SyncResult.fail(this.message) : ok = false;

  final bool ok;
  final String message; // 面向用户的一句话
}

/// 远端文件
class RemoteFile {
  RemoteFile({required this.content, this.lastModified});

  final String content;
  final DateTime? lastModified;
}

/// 同步协议常量
abstract final class RemoteState {
  static const String apiLabel = '坚果云 WebDAV';
}

abstract final class NutstoreSync {
  static const Duration _timeout = Duration(seconds: 25);

  static Map<String, String> _authHeaders(NutstoreConfig c) => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${c.account.trim()}:${c.appPassword.trim()}'))}',
      };

  static Uri _uri(NutstoreConfig c, String path) {
    final base = c.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  static String _normalizePath(String raw) {
    var p = raw.trim();
    if (p.isEmpty) p = NutstoreConfig.defaultRemotePath;
    if (!p.startsWith('/')) p = '/$p';
    if (!p.toLowerCase().endsWith('.json')) p = '$p.json';
    return p;
  }

  /// 「人话版」错误：把 HTTP 状态码翻成店主看得懂的句子
  static String _friendly(int code, String detail) {
    switch (code) {
      case 401:
        return '账号或应用密码不对。请到坚果云「账户信息 → 安全选项 → '
            '第三方应用管理」添加应用并复制生成的应用密码（不是登录密码）';
      case 403:
        return '坚果云拒绝了这次请求（403）。请确认账号未被限制，'
            '且用的是应用密码而非登录密码';
      case 404:
        return '远端文件不存在';
      case 405:
      case 409:
        return '远端目录不可用（$code），请换一个存放路径试试';
      case 507:
        return '坚果云空间不足，无法写入';
      default:
        return '请求失败（HTTP $code）${detail.isEmpty ? '' : '：$detail'}';
    }
  }

  static String _reason(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection')) {
      return '连不上坚果云，请检查网络后重试';
    }
    if (s.contains('TimeoutException')) return '连接超时，请检查网络后重试';
    return '同步出错：$s';
  }

  /// Web 端不可用（浏览器同源策略会拦截跨域 WebDAV 请求）
  static SyncResult? _webGuard() => kIsWeb
      ? SyncResult.fail('网页版受浏览器限制无法直连坚果云，'
          '请在手机 App 上使用同步功能（数据仍可通过备份文件手动搬运）')
      : null;

  /// 测试连通性。
  ///
  /// 用 `PROPFIND` 探测目标文件：
  /// - 207 → 文件已存在，一切正常
  /// - 404 → 认证通过但文件还没有（第一次上传会创建），也算通过
  /// - 401/403 → 账号或密码问题
  static Future<SyncResult> test(NutstoreConfig c) async {
    final guard = _webGuard();
    if (guard != null) return guard;
    if (!c.isConfigured) return SyncResult.fail('请先填写账号与应用密码');

    final url = _uri(c, _normalizePath(c.remotePath));
    try {
      final req = http.Request('PROPFIND', url)
        ..headers.addAll(_authHeaders(c))
        ..headers['Depth'] = '0'
        ..headers['Content-Type'] = 'application/xml; charset=utf-8';
      final res = await http.Client().send(req).timeout(_timeout);

      if (res.statusCode == 207) {
        return SyncResult.ok('连接成功，云端已有备份文件，可以直接下载');
      }
      if (res.statusCode == 404) {
        return SyncResult.ok('连接成功（云端还没有备份文件，首次上传会自动创建）');
      }
      // 认证过了但目录不存在时，有些服务端返回 409/405
      if (res.statusCode == 405 || res.statusCode == 409) {
        return SyncResult.ok('连接成功（远端目录会在首次上传时自动创建）');
      }
      return SyncResult.fail(_friendly(res.statusCode, ''));
    } catch (e) {
      return SyncResult.fail(_reason(e));
    }
  }

  /// 上传备份（本地 → 云端）。必要时逐级创建目录。
  static Future<SyncResult> upload(NutstoreConfig c, String jsonText) async {
    final guard = _webGuard();
    if (guard != null) return guard;
    if (!c.isConfigured) return SyncResult.fail('请先填写账号与应用密码');

    final path = _normalizePath(c.remotePath);
    try {
      await _ensureDirs(c, path);
      final res = await http
          .put(
            _uri(c, path),
            headers: {
              ..._authHeaders(c),
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: utf8.encode(jsonText),
          )
          .timeout(_timeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return SyncResult.ok('已上传到坚果云');
      }
      return SyncResult.fail(_friendly(res.statusCode, res.body));
    } catch (e) {
      return SyncResult.fail(_reason(e));
    }
  }

  /// 下载备份（云端 → 本地）。远端不存在返回 null（不是错误）。
  static Future<RemoteFile?> download(NutstoreConfig c) async {
    final guard = _webGuard();
    if (guard != null) throw SyncException(guard.message);
    if (!c.isConfigured) throw SyncException('请先填写账号与应用密码');

    final path = _normalizePath(c.remotePath);
    try {
      final res = await http
          .get(_uri(c, path), headers: _authHeaders(c))
          .timeout(_timeout);

      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        throw SyncException(_friendly(res.statusCode, res.body));
      }
      // 坚果云带 BOM 的情况（Windows 端工具写入过）要剥掉，否则 jsonDecode 会失败
      var body = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (body.startsWith('\uFEFF')) body = body.substring(1);
      return RemoteFile(
        content: body,
        lastModified: res.headers['last-modified'] == null
            ? null
            : DateTime.tryParse(res.headers['last-modified']!)?.toLocal(),
      );
    } on SyncException {
      rethrow;
    } catch (e) {
      throw SyncException(_reason(e));
    }
  }

  /// 获取远端文件的最后修改时间（用于「谁更新」的冲突判断）。
  /// 取不到（文件不存在 / 网络失败）返回 null。
  static Future<DateTime?> remoteModified(NutstoreConfig c) async {
    if (kIsWeb || !c.isConfigured) return null;
    final path = _normalizePath(c.remotePath);
    try {
      final req = http.Request('PROPFIND', _uri(c, path))
        ..headers.addAll(_authHeaders(c))
        ..headers['Depth'] = '0';
      final res = await http.Client().send(req).timeout(_timeout);
      if (res.statusCode != 207) return null;
      final xml = await res.stream.bytesToString();
      final m = RegExp(r'<[^>]*getlastmodified[^>]*>([^<]+)<',
              caseSensitive: false)
          .firstMatch(xml);
      if (m == null) return null;
      return DateTime.tryParse(m.group(1)!.trim())?.toLocal();
    } catch (_) {
      return null;
    }
  }

  /// 逐级创建远端目录（已存在会被忽略）
  static Future<void> _ensureDirs(NutstoreConfig c, String filePath) async {
    final parts = filePath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length <= 1) return; // 直接在根目录放文件，无需建目录

    var acc = '';
    for (var i = 0; i < parts.length - 1; i++) {
      acc += '/${parts[i]}';
      try {
        final req = http.Request('MKCOL', _uri(c, acc))
          ..headers.addAll(_authHeaders(c));
        final res = await http.Client().send(req).timeout(_timeout);
        // 201 创建成功；405 已存在；301/409 语义上也可继续
        if (res.statusCode == 401 || res.statusCode == 403) {
          throw SyncException(_friendly(res.statusCode, ''));
        }
      } on SyncException {
        rethrow;
      } catch (_) {
        // 建目录失败不阻塞上传：很多 WebDAV 服务在根目录直接 PUT 也能成功
      }
    }
  }
}

/// 同步异常（带一句人话）
class SyncException implements Exception {
  SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
