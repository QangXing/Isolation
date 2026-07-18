import 'package:flutter/material.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '说明',
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRow('应用名称', 'isolation'),
                      const SizedBox(height: 12),
                      _buildRow('版本', '1.0.0'),
                      const SizedBox(height: 12),
                      _buildRow('用途', '插件管理与悬浮球小键盘'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTitle('使用说明'),
                      const SizedBox(height: 10),
                      _buildBullet('在“管理”页导入 .isoplugin 插件包'),
                      _buildBullet('在“主页”启用需要的插件'),
                      _buildBullet('启用“悬浮球小键盘”后，需授予悬浮窗与辅助功能权限'),
                      _buildBullet('单击悬浮球可唤起系统默认输入法'),
                      _buildBullet('长按悬浮球打开内置迷你 QWERTY 键盘'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTitle('权限说明'),
                      const SizedBox(height: 10),
                      _buildBullet('悬浮窗权限：显示悬浮球与键盘'),
                      _buildBullet('辅助功能权限：查找输入框并注入文字'),
                      _buildBullet('前台服务权限：保持悬浮球后台运行'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildPermissionButton(
                  context,
                  label: '检查悬浮窗权限',
                  onTap: () async {
                    final granted = await NativeChannel.checkOverlayPermission();
                    if (context.mounted) {
                      _showResult(context, '悬浮窗权限', granted);
                    }
                  },
                ),
                const SizedBox(height: 10),
                _buildPermissionButton(
                  context,
                  label: '检查辅助功能权限',
                  onTap: () async {
                    final granted = await NativeChannel.checkAccessibilityPermission();
                    if (context.mounted) {
                      _showResult(context, '辅助功能权限', granted);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
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
      padding: const EdgeInsets.only(bottom: 6),
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
                color: Colors.black.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
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
