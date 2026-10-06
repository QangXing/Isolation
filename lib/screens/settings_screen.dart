import 'package:flutter/material.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';
import 'instruction_manual_screen.dart';

/// 设置页（底栏第三个 Tab）。
///
/// 由原"说明"页改造而来，包含：
/// - 通知栏状态通知开关（原"设置"卡片功能）；
/// - "说明"卡片：原说明页内容（应用信息、指令说明入口、使用说明、权限说明、权限检查）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _statusNotification = false;
  bool _loading = true;
  bool _helpExpanded = false;

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
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '设置',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w300,
                color: Colors.black.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                // 通知栏状态通知
                if (_loading)
                  const GlassCard(
                    child: SizedBox(
                      height: 72,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
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
                const SizedBox(height: 16),
                // 说明卡片（可展开）
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _helpExpanded = !_helpExpanded),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.help_outline_rounded,
                                  size: 20,
                                  color: Colors.black.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Text(
                                  '说明',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              AnimatedRotation(
                                turns: _helpExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_helpExpanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(height: 1, color: Colors.black12),
                              const SizedBox(height: 14),
                              _buildInfoRow('应用名称', 'isolation'),
                              const SizedBox(height: 12),
                              _buildInfoRow('版本', '1.0.0'),
                              const SizedBox(height: 12),
                              _buildInfoRow('用途', '插件管理与跨应用自动化宏'),
                              const SizedBox(height: 14),
                              // 指令说明入口
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const InstructionManualScreen(),
                                    ),
                                  );
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.menu_book_rounded,
                                        size: 18,
                                        color: Colors.black.withValues(alpha: 0.6),
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          '指令说明',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '查看宏 / 球指令语法',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: Colors.black.withValues(alpha: 0.3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _buildTitle('使用说明'),
                              const SizedBox(height: 10),
                              _buildBullet('在"管理"页录制宏或导入 .isoplugin 插件包'),
                              _buildBullet('在"主页"启用需要的宏插件'),
                              _buildBullet('启用宏后需授予悬浮窗与辅助功能权限'),
                              _buildBullet('单击悬浮球可在当前界面自动执行启用的宏'),
                              _buildBullet('长按悬浮球打开应用主界面'),
                              const SizedBox(height: 14),
                              _buildTitle('权限说明'),
                              const SizedBox(height: 10),
                              _buildBullet('悬浮窗权限：显示悬浮球'),
                              _buildBullet('辅助功能权限：录制点击事件并回放宏'),
                              _buildBullet('前台服务权限：保持悬浮球后台运行'),
                              const SizedBox(height: 14),
                              _buildTitle('权限检查'),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _PermissionButton(
                                      label: '悬浮窗',
                                      icon: Icons.crop_square_rounded,
                                      onTap: () async {
                                        final granted = await NativeChannel.checkOverlayPermission();
                                        if (context.mounted) {
                                          _showResult(context, '悬浮窗权限', granted);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _PermissionButton(
                                      label: '辅助功能',
                                      icon: Icons.accessibility_new_rounded,
                                      onTap: () async {
                                        final granted = await NativeChannel.checkAccessibilityPermission();
                                        if (context.mounted) {
                                          _showResult(context, '辅助功能权限', granted);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showResult(BuildContext context, String name, bool granted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name：${granted ? '已授予' : '未授予'}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: granted ? Colors.black87 : Colors.orangeAccent,
      ),
    );
  }
}

class _PermissionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PermissionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
