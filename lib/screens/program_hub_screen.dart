import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/plugin_card.dart';
import 'default_floater_settings_screen.dart';
import 'floater_editor_screen.dart';
import 'program_macro_screen.dart';

class ProgramHubScreen extends StatefulWidget {
  final bool initialFloaterTab;

  const ProgramHubScreen({super.key, this.initialFloaterTab = false});

  @override
  State<ProgramHubScreen> createState() => _ProgramHubScreenState();
}

class _ProgramHubScreenState extends State<ProgramHubScreen> {
  late bool _isFloaterTab;

  @override
  void initState() {
    super.initState();
    _isFloaterTab = widget.initialFloaterTab;
  }

  void _createNew() {
    if (_isFloaterTab) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FloaterEditorScreen()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProgramMacroScreen()),
      );
    }
  }

  void _editPlugin(Plugin plugin) {
    if (plugin.isFloater) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FloaterEditorScreen(pluginId: plugin.id)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProgramMacroScreen(pluginId: plugin.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Colors.black.withValues(alpha: 0.7)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '编程',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: _createNew,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_circle_outline_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _isFloaterTab ? '新建编程球' : '新建编程宏',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<PluginProvider>(
        builder: (context, provider, child) {
          final macros = provider.plugins.where((p) => !p.isFloater).toList();
          final floaters = provider.plugins.where((p) => p.isFloater).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: _buildToggle(),
              ),
              Expanded(
                child: _isFloaterTab
                    ? _buildFloaterList(context, provider, floaters)
                    : _buildMacroList(context, provider, macros),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToggle() {
    return Row(
      children: [
        Expanded(
          child: _ToggleChip(
            label: '编程宏',
            selected: !_isFloaterTab,
            onTap: () => setState(() => _isFloaterTab = false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ToggleChip(
            label: '球',
            selected: _isFloaterTab,
            onTap: () => setState(() => _isFloaterTab = true),
          ),
        ),
      ],
    );
  }

  Widget _buildMacroList(BuildContext context, PluginProvider provider, List<Plugin> macros) {
    if (macros.isEmpty) {
      return Center(
        child: Text(
          '暂无编程宏，点击右上角创建',
          style: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      itemCount: macros.length,
      itemBuilder: (context, index) {
        final plugin = macros[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PluginCard(
            plugin: plugin,
            onTap: () => _editPlugin(plugin),
            onEnabledChanged: (value) => provider.setEnabled(plugin.id, value),
          ),
        );
      },
    );
  }

  Widget _buildFloaterList(BuildContext context, PluginProvider provider, List<Plugin> floaters) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      itemCount: floaters.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _DefaultFloaterCard(
              enabled: provider.floatingBallVisible,
              onEnabledChanged: (value) => provider.setFloatingBallVisible(value),
            ),
          );
        }
        final plugin = floaters[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PluginCard(
            plugin: plugin,
            onTap: () => _editPlugin(plugin),
            onEnabledChanged: (value) => provider.setEnabled(plugin.id, value),
          ),
        );
      },
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.black87 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black.withValues(alpha: 0.8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultFloaterCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  const _DefaultFloaterCard({required this.enabled, required this.onEnabledChanged});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DefaultFloaterSettingsScreen()),
        );
      },
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.touch_app_rounded,
              color: Colors.black.withValues(alpha: 0.5),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '默认悬浮球',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '与系统内置悬浮球效果完全一致的默认模板，可自定义外观',
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onEnabledChanged(!enabled),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 50,
              height: 28,
              decoration: BoxDecoration(
                color: enabled ? Colors.black87 : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
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
          ),
        ],
      ),
    );
  }
}
