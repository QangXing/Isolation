import 'package:flutter/material.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';

/// 应用设置页：目前包含"通知栏状态通知"开关。
///
/// 开关以原生侧持久化状态为唯一事实源，保证后台（定时触发 / 开机自启）
/// 场景下开关状态一致。
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _loading = true;
  bool _statusNotification = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await NativeChannel.isStatusNotificationEnabled();
    if (mounted) {
      setState(() {
        _statusNotification = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _onStatusNotificationChanged(bool value) async {
    // Android 13+ 发通知需要运行时权限，开启前先请求
    if (value) {
      final hasPermission = await NativeChannel.checkNotificationPermission();
      if (!hasPermission) {
        await NativeChannel.requestNotificationPermission();
      }
    }
    await NativeChannel.setStatusNotificationEnabled(value);
    if (mounted) {
      setState(() => _statusNotification = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '已开启通知栏状态通知' : '已关闭通知栏状态通知'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              GlassCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: Colors.black87,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '通知栏状态通知',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '在通知栏展示运行状态（悬浮球 / 辅助功能 / 定时宏）与宏执行中的 print 输出',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withValues(alpha: 0.45),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: _statusNotification,
                      onChanged: _onStatusNotificationChanged,
                      activeColor: Colors.black87,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: Colors.black.withValues(alpha: 0.12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
