import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫码页（全屏）。
///
/// 行为：
/// - 手机端：启动后置摄像头实时识别，识别到条码后震动一下并返回结果（pop 返回条码字符串）。
/// - 相机权限被拒 / 启动失败：在预览区域显示真实失败原因。
/// - PC / 不支持的平台：显示「请在手机上使用」的提示页。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  MobileScannerController? _controller;
  bool _done = false; // 防止同一张码连续触发多次
  bool _supported = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    // 仅在移动端启用摄像头扫码；PC / Web 提示需手机使用
    _supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (_supported) {
      _controller = MobileScannerController(
        autoStart: true,
        facing: CameraFacing.back,
        detectionSpeed: DetectionSpeed.normal,
        torchEnabled: false,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done || !mounted) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _done = true;
        HapticFeedback.mediumImpact(); // 识别成功震动反馈
        _controller?.stop();
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  void _toggleTorch() {
    _controller?.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫一扫'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_supported)
            IconButton(
              tooltip: '手电筒',
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: _toggleTorch,
            ),
        ],
      ),
      body: _supported ? _buildScanner() : _buildUnsupported(),
    );
  }

  /// PC 端提示：扫码需要手机摄像头
  Widget _buildUnsupported() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phone_android, size: 64, color: Colors.grey.shade500),
          const SizedBox(height: 16),
          const Text('扫码功能需要使用手机摄像头',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          Text('请在手机上打开本应用使用扫码',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        // 摄像头预览 + 真实错误信息展示
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) {
            final msg = _describeError(error);
            if (kDebugMode) {
              // ignore: avoid_print
              print('扫码相机错误: ${error.errorCode} ${error.errorDetails?.message}');
            }
            return _buildError(msg);
          },
        ),
        // 扫描取景框
        Center(
          child: Container(
            width: 260,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        // 底部提示
        Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('将条码对准框内，自动识别',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 把相机错误转换为用户可读的真实原因
  String _describeError(MobileScannerException error) {
    final detail = error.errorDetails?.message ?? '';
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return '相机权限被拒绝，请在系统设置中允许本应用使用摄像头';
      case MobileScannerErrorCode.unsupported:
        return '当前设备不支持扫码：${detail.isNotEmpty ? detail : "未检测到可用摄像头"}';
      case MobileScannerErrorCode.controllerInitializing:
        return '相机正在初始化，请稍候…';
      default:
        return '扫码启动失败：${detail.isNotEmpty ? detail : error.errorCode.name}';
    }
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 56, color: Colors.white54),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () {
                setState(() {
                  _controller?.dispose();
                  _controller = MobileScannerController(autoStart: true);
                  _done = false;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
