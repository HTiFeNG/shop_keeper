#!/usr/bin/env python3
"""在「Dart 无法创建子进程」的环境里跑静态分析（等价于 flutter analyze）。

## 为什么需要它

本机曾出现这样的故障：`flutter analyze` / `dart analyze` / `flutter test` 全部崩溃，
报 `ProcessException: 所有的管道范例都在使用中 (CreateFile failed 231)`。

根因是 **Dart VM 无法创建子进程的 stdio 命名管道**（`runtime/bin/process_win.cc`）。
已经排除的：沙箱、残留进程、系统管道泄漏（都不成立）。
注意 `ProcessStartMode.detached` 反而能成功 —— 因为它不建管道。
flutter_tools 内部（git / analysis_server / flutter_tester）全都要捕获输出，
所以必然崩，与项目代码无关。

**但 Python 起进程、开管道一切正常。** 所以这里由 Python 当 LSP 客户端，
Dart 语言服务器当服务端，走 stdio 通信拿诊断 —— 绕开 Dart 的 fork 问题。

`dart format` 也能跑（它不 fork），可以先用它兜住语法错误。

## 用法

    python tool/analyze_via_lsp.py            # 分析 lib/ 和 test/，打印摘要 + 前 40 条
    python tool/analyze_via_lsp.py --out r.txt

退出码：有 error 时为 1，否则 0（方便接 CI / 脚本判断）。

环境变量 `FLUTTER_ROOT` 可覆盖 Flutter 安装目录（默认 D:\\flutter\\flutter）。
"""
import argparse
import json
import os
import queue
import subprocess
import sys
import threading
import time

SEVERITY = {1: 'error', 2: 'warning', 3: 'info', 4: 'hint'}


def find_dart(flutter_root):
    sdk = os.path.join(flutter_root, 'bin', 'cache', 'dart-sdk')
    exe = os.path.join(sdk, 'bin', 'dart.exe' if os.name == 'nt' else 'dart')
    if not os.path.exists(exe):
        sys.exit('找不到 Dart SDK：%s\n可用 FLUTTER_ROOT 环境变量指定 Flutter 目录。' % exe)
    return exe, sdk


def collect(root):
    found = []
    for base in ('lib', 'test'):
        top = os.path.join(root, base)
        if not os.path.isdir(top):
            continue
        for dirpath, _dirs, filenames in os.walk(top):
            for name in filenames:
                if name.endswith('.dart'):
                    found.append(os.path.join(dirpath, name))
    return sorted(found)


def to_uri(path):
    return 'file:///' + path.replace('\\', '/').lstrip('/')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', help='把完整报告写到这个文件')
    parser.add_argument('--idle', type=float, default=20,
                        help='连续多少秒没有新消息就认为分析结束（默认 20）')
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    flutter_root = os.environ.get('FLUTTER_ROOT', r'D:\flutter\flutter')
    dart, sdk = find_dart(flutter_root)

    files = collect(root)
    if not files:
        sys.exit('没有找到任何 .dart 文件（项目根：%s）' % root)

    proc = subprocess.Popen(
        [dart, 'language-server', '--dart-sdk', sdk,
         '--disable-server-feature-completion',
         '--disable-server-feature-search'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        cwd=root,
    )

    # 必须排空 stderr，否则服务器日志写满缓冲区会把整个流程卡死
    threading.Thread(
        target=lambda: [None for _ in iter(proc.stderr.readline, b'')],
        daemon=True).start()

    write_lock = threading.Lock()

    def send(obj):
        data = json.dumps(obj).encode('utf-8')
        with write_lock:
            proc.stdin.write(b'Content-Length: %d\r\n\r\n' % len(data))
            proc.stdin.write(data)
            proc.stdin.flush()

    def read_msg():
        headers = {}
        while True:
            raw = proc.stdout.readline()
            if not raw:
                return None
            line = raw.decode('utf-8', 'replace').strip()
            if line == '':
                break
            key, _, value = line.partition(':')
            headers[key.strip().lower()] = value.strip()
        size = int(headers.get('content-length', '0'))
        if size <= 0:
            return None
        return json.loads(proc.stdout.read(size).decode('utf-8'))

    inbox = queue.Queue()

    def reader():
        while True:
            msg = read_msg()
            inbox.put(msg)
            if msg is None:
                return

    threading.Thread(target=reader, daemon=True).start()

    send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
          'params': {'processId': None, 'rootUri': to_uri(root),
                     'capabilities': {}}})

    while True:
        msg = inbox.get()
        if msg is None:
            sys.exit('Dart 语言服务器在初始化阶段就退出了')
        if msg.get('id') == 1:
            if 'error' in msg:
                sys.exit('初始化失败：%s' % json.dumps(msg['error']))
            break

    send({'jsonrpc': '2.0', 'method': 'initialized', 'params': {}})

    for path in files:
        with open(path, 'r', encoding='utf-8') as fh:
            text = fh.read()
        send({'jsonrpc': '2.0', 'method': 'textDocument/didOpen',
              'params': {'textDocument': {'uri': to_uri(path),
                                          'languageId': 'dart',
                                          'version': 1, 'text': text}}})

    diagnostics = {}
    idle = 0.0
    hard_deadline = time.time() + 600
    while time.time() < hard_deadline:
        try:
            msg = inbox.get(timeout=2)
        except queue.Empty:
            idle += 2
            if idle >= args.idle:
                break
            continue
        if msg is None:
            break
        idle = 0
        method = msg.get('method')
        if method == 'textDocument/publishDiagnostics':
            diagnostics[msg['params']['uri']] = msg['params'].get('diagnostics', [])
        elif method is not None and msg.get('id') is not None:
            # 服务器发来的请求，回空结果让它继续
            send({'jsonrpc': '2.0', 'id': msg['id'], 'result': None})

    try:
        proc.kill()
    except Exception:
        pass

    errors, warnings, infos = [], [], []
    for uri, diags in diagnostics.items():
        rel = os.path.relpath(uri.replace('file:///', '').replace('/', os.sep), root)
        for d in diags:
            start = d.get('range', {}).get('start', {})
            entry = '%s:%d:%d  %s' % (rel, start.get('line', 0) + 1,
                                      start.get('character', 0) + 1,
                                      (d.get('message') or '').replace('\n', ' '))
            sev = d.get('severity', 1)
            if sev == 1:
                errors.append(entry)
            elif sev == 2:
                warnings.append(entry)
            else:
                infos.append('[%s] %s' % (SEVERITY.get(sev, sev), entry))

    lines = ['分析文件数: %d' % len(files), '']
    lines += ['===== ERRORS (%d) =====' % len(errors)] + errors + ['']
    lines += ['===== WARNINGS (%d) =====' % len(warnings)] + warnings + ['']
    lines += ['===== INFO/HINT (%d) =====' % len(infos)] + infos
    report = '\n'.join(lines)

    if args.out:
        with open(args.out, 'w', encoding='utf-8') as fh:
            fh.write(report + '\n')
        print('完整报告已写入 %s' % args.out)

    print(report)
    print()
    print('合计: %d error, %d warning, %d info' % (len(errors), len(warnings), len(infos)))
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
