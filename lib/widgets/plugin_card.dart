import 'dart:io';
import 'package:flutter/material.dart';
import '../models/plugin.dart';
import 'glass_card.dart';

class PluginCard extends StatelessWidget {
  final Plugin plugin;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback? onTap;
  final Widget? trailing;

  const PluginCard({
    super.key,
    required this.plugin,
    required this.onEnabledChanged,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      animate: true,
      onTap: onTap,
      child: Row(
        children: [
          _buildIcon(plugin),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  plugin.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.withValues(alpha: 0.7),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (trailing != null) ...[
            trailing!,
            const SizedBox(width: 8),
          ],
          _buildSwitch(),
        ],
      ),
    );
  }

  Widget _buildIcon(Plugin plugin) {
    final iconPath = plugin.iconPath;
    if (iconPath != null && File(iconPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(iconPath),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Icon(
        plugin.builtIn ? Icons.touch_app_rounded : Icons.extension_rounded,
        color: Colors.black54,
        size: 24,
      ),
    );
  }

  Widget _buildSwitch() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onEnabledChanged(!plugin.enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          color: plugin.enabled
              ? Colors.black87
              : Colors.grey.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: plugin.enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
