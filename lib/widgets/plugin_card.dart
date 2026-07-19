import 'dart:io';
import 'package:flutter/material.dart';
import '../models/plugin.dart';
import 'glass_card.dart';

class PluginCard extends StatefulWidget {
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
  State<PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<PluginCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    return GlassCard(
      animate: true,
      onTap: () {
        if (widget.onTap != null) {
          widget.onTap!();
        } else {
          setState(() => _expanded = !_expanded);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
              if (widget.trailing != null) ...[
                widget.trailing!,
                const SizedBox(width: 8),
              ],
              _buildSwitch(plugin),
            ],
          ),
          if (_expanded && plugin.actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFEAEAEA)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: plugin.actions.map((action) {
                return _ActionChip(
                  label: action.label,
                  onTap: () => widget.onTap?.call(),
                );
              }).toList(),
            ),
          ],
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

  Widget _buildSwitch(Plugin plugin) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: plugin.enabled
            ? Colors.black87
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Switch(
        value: plugin.enabled,
        onChanged: widget.onEnabledChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: Colors.transparent,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.transparent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ),
    );
  }
}
