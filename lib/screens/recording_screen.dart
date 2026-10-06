import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_provider.dart';
import '../services/macro_program_parser.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';

/// 录制宏：录制参数页 + 录制状态页 + 结果编辑页。
///
/// - 参数页：选择录制模式（简单 / 复杂）、颜色捕获、系统键录制、点击间隔、手势回放；
/// - 状态页：录制中实时展示已记录步数，可暂停 / 继续 / 结束 / 取消；
/// - 编辑页：消费原生侧录制结果（consumePendingRecordingResult）后进入，可编辑步骤 / 代码并保存为宏。
class RecordingScreen extends StatefulWidget {
  /// 直接以结果编辑页打开（前台恢复检测到待处理录制结果时由 main.dart 传入）。
  final List<Map<String, dynamic>>? initialSteps;

  const RecordingScreen({super.key, this.initialSteps});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  // ── 录制参数 ──
  bool _complexMode = false;
  bool _captureColors = false;
  bool _recordSystemKeys = true;
  double _minClickIntervalMs = 100;
  bool _replayGestures = true;
  bool _gestureMode = false;
  bool _shizukuMode = false;

  // ── 录制状态（由 getRecordingState 轮询） ──
  String _sessionState = 'idle'; // idle | recording | paused | finished
  int _stepCount = 0;
  Timer? _pollTimer;
  bool _resultHandled = false;

  // ── Shizuku 状态 ──
  /// 0=就绪，1=未安装，2=服务未运行，3=未授权
  int _shizukuState = 1;

  // ── 结果编辑 ──
  bool _showEditor = false;
  bool _codeView = false;
  List<Map<String, dynamic>> _steps = [];
  late final TextEditingController _codeController;

  bool get _recordingActive =>
      _sessionState == 'recording' || _sessionState == 'paused';

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _refreshShizukuState();
    final initial = widget.initialSteps;
    if (initial != null && initial.isNotEmpty) {
      _steps = List.from(initial);
      _showEditor = true;
      _syncCodeFromSteps();
    } else {
      // 管理页进入：若原生侧有未消费的录制结果（上次录制后进程被杀等），直接进入编辑页
      _checkPendingResult();
    }
    // 录制会话进行中则轮询状态（编辑页打开时不轮询）
    if (!_showEditor) {
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollSession());
    }
  }

  Future<void> _refreshShizukuState() async {
    final state = await NativeChannel.checkShizukuState();
    if (mounted) setState(() => _shizukuState = state);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  // ── 状态轮询 ──

  Future<void> _pollSession() async {
    if (!mounted || _showEditor) return;
    final state = await NativeChannel.getRecordingState();
    if (!mounted || state == null) return;
    final s = state['state'] as String? ?? 'idle';
    final count = (state['stepCount'] as num?)?.toInt() ?? 0;
    setState(() {
      _sessionState = s;
      _stepCount = count;
    });
    // 悬浮球结束录制后（或 结束 按钮触发 finish），原生会把结果持久化并回到前台
    if (s == 'finished' && !_resultHandled) {
      _resultHandled = true;
      await _consumeResult();
    }
  }

  Future<void> _checkPendingResult() async {
    final result = await NativeChannel.consumePendingRecordingResult();
    if (!mounted || result == null) return;
    _enterEditorWith(result);
  }

  Future<void> _consumeResult() async {
    final result = await NativeChannel.consumePendingRecordingResult();
    if (!mounted || result == null) return;
    _enterEditorWith(result);
  }

  void _enterEditorWith(Map<String, dynamic> result) {
    final rawSteps = (result['steps'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    if (rawSteps.isEmpty) {
      if (mounted) {
        setState(() => _sessionState = 'idle');
      }
      return;
    }
    final converted = MacroProgramParser.convertLegacySteps(rawSteps);
    setState(() {
      _steps = converted;
      _showEditor = true;
      _codeView = false;
      _sessionState = 'idle';
    });
    _syncCodeFromSteps();
  }

  // ── 录制控制 ──

  Future<void> _startRecording() async {
    final hasA11y = await NativeChannel.checkAccessibilityPermission();
    if (!hasA11y) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先开启辅助功能权限'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      await NativeChannel.requestAccessibilityPermission();
      return;
    }
    if (_shizukuMode) {
      await _refreshShizukuState();
      if (_shizukuState != 0) {
        _showShizukuGuide(_shizukuState);
        return;
      }
    }
    final started = await NativeChannel.startRecordingSession(
      mode: _complexMode ? 'complex' : 'simple',
      captureColors: _captureColors,
      recordSystemKeys: _recordSystemKeys,
      minClickIntervalMs: _minClickIntervalMs.round(),
      replayGestures: _replayGestures,
      gestureMode: _gestureMode,
      shizukuMode: _shizukuMode,
    );
    if (!mounted) return;
    if (started) {
      setState(() {
        _sessionState = 'recording';
        _stepCount = 0;
        _resultHandled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('录制已开始，请在其他 App 中执行操作，完成后点击悬浮球或返回本页结束'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法开始录制，请检查悬浮窗、辅助功能与 Shizuku 授权'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showShizukuGuide(int state) {
    String message;
    String actionLabel;
    VoidCallback action;
    switch (state) {
      case 1:
        message = 'Shizuku 未安装，需要它来读取系统输入事件';
        actionLabel = '去安装';
        action = () { NativeChannel.openShizuku(); };
      case 2:
        message = 'Shizuku 服务未运行，请先启动';
        actionLabel = '打开 Shizuku';
        action = () { NativeChannel.openShizuku(); };
      case 3:
        message = 'Shizuku 未授权，请在弹窗中允许';
        actionLabel = '授权';
        action = () { NativeChannel.requestShizukuPermission(); };
      default:
        message = 'Shizuku 状态异常';
        actionLabel = '打开 Shizuku';
        action = () { NativeChannel.openShizuku(); };
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
        action: SnackBarAction(
          label: actionLabel,
          textColor: Colors.white,
          onPressed: action,
        ),
      ),
    );
  }

  void _showShizukuGuideFromTile() => _showShizukuGuide(_shizukuState);

  String _shizukuStateLabel(int state) {
    switch (state) {
      case 0:
        return 'Shizuku 已就绪';
      case 1:
        return 'Shizuku 未安装';
      case 2:
        return 'Shizuku 服务未运行';
      case 3:
        return 'Shizuku 未授权';
      default:
        return 'Shizuku 状态未知';
    }
  }

  Future<void> _pause() async {
    await NativeChannel.pauseRecording();
    if (mounted) setState(() => _sessionState = 'paused');
  }

  Future<void> _resume() async {
    await NativeChannel.resumeRecording();
    if (mounted) setState(() => _sessionState = 'recording');
  }

  Future<void> _finish() async {
    await NativeChannel.finishRecording();
    if (!mounted) return;
    setState(() => _resultHandled = true);
    await _consumeResult();
    if (mounted) {
      setState(() {
        if (!_showEditor) _sessionState = 'idle';
      });
    }
  }

  Future<void> _cancel() async {
    await NativeChannel.cancelRecording();
    if (mounted) {
      setState(() {
        _sessionState = 'idle';
        _stepCount = 0;
      });
    }
  }

  // ── 步骤 / 代码互转 ──

  void _syncCodeFromSteps() {
    _codeController.text = MacroProgramParser.serialize(_steps);
  }

  void _syncStepsFromCode() {
    try {
      _steps = MacroProgramParser.parse(_codeController.text);
    } catch (_) {
      // 解析失败时保留原 _steps，让用户继续编辑
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
        title: Text(
          _showEditor
              ? (_codeView ? '编辑宏 · 代码' : '编辑宏 · 步骤')
              : (_recordingActive ? '录制中' : '录制宏'),
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Colors.black.withValues(alpha: 0.7)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_showEditor)
            IconButton(
              icon: Icon(
                _codeView ? Icons.list_rounded : Icons.code_rounded,
                color: Colors.black.withValues(alpha: 0.7),
              ),
              tooltip: _codeView ? '步骤视图' : '代码视图',
              onPressed: () {
                setState(() {
                  if (_codeView) {
                    _syncStepsFromCode();
                  } else {
                    _syncCodeFromSteps();
                  }
                  _codeView = !_codeView;
                });
              },
            ),
        ],
      ),
      body: Consumer<PluginProvider>(
        builder: (context, provider, child) {
          if (_showEditor) {
            return _buildEditor(context, provider);
          }
          return _recordingActive ? _buildRecordingStatus() : _buildParams(context);
        },
      ),
    );
  }

  // ── 参数页 ──

  Widget _buildParams(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          '录制模式',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.bolt_rounded,
                title: '简单录制',
                subtitle: '只记录点击 / 滑动 / 系统键等基础指令，回放快',
                selected: !_complexMode,
                onTap: () => setState(() {
                  _complexMode = false;
                  _captureColors = false;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModeCard(
                icon: Icons.auto_awesome_rounded,
                title: '复杂录制',
                subtitle: '关键点击升级为文本查找 / 颜色校验，更稳健',
                selected: _complexMode,
                onTap: () => setState(() => _complexMode = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '参数',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(
            children: [
              _SwitchRow(
                title: '记录系统按键',
                subtitle: '录制返回键 / Home 键（需在辅助功能中开启按键过滤）',
                value: _recordSystemKeys,
                onChanged: (v) => setState(() => _recordSystemKeys = v),
              ),
              const Divider(height: 1),
              _SwitchRow(
                title: '手势回放',
                subtitle: '录制时把操作原样回放给目标 App，便于查看录制效果（仅手势模式生效）',
                value: _replayGestures,
                onChanged: (v) => setState(() => _replayGestures = v),
              ),
              const Divider(height: 1),
              _SwitchRow(
                title: '手势模式',
                subtitle: '开启后挂载全屏捕获层，可录滑动/拖拽，但背景无法直接点击',
                value: _gestureMode,
                onChanged: (v) => setState(() {
                  _gestureMode = v;
                  if (v) _shizukuMode = false;
                }),
              ),
              const Divider(height: 1),
              _SwitchRow(
                title: 'Shizuku 高级模式',
                subtitle: '通过 Shizuku 读取系统输入事件，背景可正常点击且能录滑动（需安装并授权 Shizuku）',
                value: _shizukuMode,
                onChanged: (v) => setState(() {
                  _shizukuMode = v;
                  if (v) {
                    _gestureMode = false;
                    _refreshShizukuState();
                  }
                }),
              ),
              if (_shizukuMode)
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _shizukuState == 0 ? Colors.green : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _shizukuStateLabel(_shizukuState),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      if (_shizukuState != 0)
                        GestureDetector(
                          onTap: _showShizukuGuideFromTile,
                          child: Text(
                            '去处理',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.redAccent.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              _SwitchRow(
                title: '颜色捕获',
                subtitle: '记录点击位置的颜色，回放时校验（仅复杂模式）',
                value: _captureColors,
                enabled: _complexMode,
                onChanged: (v) => setState(() => _captureColors = v),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '最小点击间隔',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '过滤过密的连点，避免误录',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_minClickIntervalMs.round()}ms',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Slider(
                value: _minClickIntervalMs,
                min: 0,
                max: 500,
                divisions: 50,
                activeColor: Colors.black87,
                inactiveColor: Colors.black.withValues(alpha: 0.1),
                label: '${_minClickIntervalMs.round()}ms',
                onChanged: (v) => setState(() => _minClickIntervalMs = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: Colors.black.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '开始录制后请切换到目标 App 执行操作；屏幕上的录制悬浮球可暂停 / 结束，本页也可随时控制。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: '开始录制',
          filled: true,
          red: true,
          onTap: _startRecording,
        ),
      ],
    );
  }

  // ── 录制状态页 ──

  Widget _buildRecordingStatus() {
    final paused = _sessionState == 'paused';
    return Column(
      children: [
        Expanded(
          child: Center(
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: paused
                          ? Colors.orange.withValues(alpha: 0.12)
                          : Colors.redAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      paused ? Icons.pause_rounded : Icons.fiber_manual_record_rounded,
                      color: paused ? Colors.orange : Colors.redAccent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    paused ? '录制已暂停' : '正在录制...',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    paused
                        ? '点击"继续"或悬浮球恢复录制'
                        : '请在其他 App 中执行操作，悬浮球可暂停 / 结束。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '已记录 $_stepCount 步',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildStatusControls(),
      ],
    );
  }

  Widget _buildStatusControls() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ControlButton(
              icon: _sessionState == 'paused' ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: _sessionState == 'paused' ? '继续' : '暂停',
              color: Colors.black87,
              onTap: _sessionState == 'paused' ? _resume : _pause,
            ),
            _ControlButton(
              icon: Icons.stop_rounded,
              label: '结束',
              color: Colors.redAccent,
              onTap: _finish,
            ),
            _ControlButton(
              icon: Icons.close_rounded,
              label: '取消',
              color: Colors.grey,
              onTap: _cancel,
            ),
          ],
        ),
      ),
    );
  }

  // ── 结果编辑页 ──

  Widget _buildEditor(BuildContext context, PluginProvider provider) {
    return Column(
      children: [
        Expanded(
          child: _codeView ? _buildCodeEditor() : _buildCardEditor(),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: '返回录制',
                    onTap: () {
                      if (_codeView) _syncStepsFromCode();
                      setState(() => _showEditor = false);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: '保存宏',
                    filled: true,
                    onTap: () => _showSaveDialog(context, provider),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardEditor() {
    return _steps.isEmpty
        ? Center(
            child: Text(
              '暂无步骤',
              style: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: _steps.length,
            itemBuilder: (context, index) {
              final step = _steps[index];
              final type = step['type'] as String? ?? '';
              final label = _stepLabel(step, type);
              final delay = step['delay'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              type,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (delay != null)
                        Text(
                          '${delay}ms',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.withValues(alpha: 0.6),
                          ),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _steps.removeAt(index);
                          });
                        },
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent.withValues(alpha: 0.8),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  String _stepLabel(Map<String, dynamic> step, String type) {
    switch (type) {
      case 'print':
        return step['message']?.toString() ?? '';
      case 'click':
        return '点击 (${step['x']}, ${step['y']})';
      case 'clickNode':
        final target = step['target'] as Map<String, dynamic>?;
        return target?['text']?.toString() ??
            target?['resourceId']?.toString() ??
            target?['className']?.toString() ??
            '节点点击';
      case 'longPressAt':
        return '长按 (${step['x']}, ${step['y']})';
      case 'swipe':
        return '滑动 (${step['start']} → ${step['end']})';
      case 'scroll':
        final deltaX = step['deltaX'] ?? 0;
        final deltaY = step['deltaY'] ?? 0;
        return '滚动 @(${step['x']}, ${step['y']}) Δ($deltaX, $deltaY)';
      case 'back':
        return '返回';
      case 'home':
        return '主屏';
      case 'wait':
        return '等待 ${step['duration']}ms';
      case 'findText':
        return '查找文本: ${step['text']}';
      case 'waitForText':
        return '等待文本: ${step['text']}';
      case 'ifColorAt':
        return '颜色校验 @(${step['x']}, ${step['y']})';
      case 'findColor':
        return '查找颜色';
      default:
        return '指令参数';
    }
  }

  Widget _buildCodeEditor() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _codeController,
        maxLines: null,
        expands: true,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: Color(0xFFE0E0E0),
          height: 1.5,
        ),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.all(16),
          border: InputBorder.none,
          hintText: '在此编辑宏代码…',
          hintStyle: TextStyle(color: Color(0xFF757575)),
        ),
      ),
    );
  }

  Future<void> _showSaveDialog(BuildContext context, PluginProvider provider) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('保存宏'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '宏名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '描述',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final name = nameController.text.trim().isEmpty ? '未命名宏' : nameController.text.trim();
      final description = descController.text.trim();
      if (_codeView) _syncStepsFromCode();
      final success = await provider.saveMacroPlugin(
        name: name,
        description: description,
        steps: _steps,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '宏已保存' : '保存失败'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: success ? Colors.black87 : Colors.redAccent,
          ),
        );
        if (success) {
          Navigator.of(context).pop();
        }
      }
    }
  }
}

/// 录制模式选择卡片。
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      color: selected ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.55),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: selected ? Colors.black87 : Colors.black45),
              const Spacer(),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 18,
                color: selected ? Colors.redAccent : Colors.black26,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 参数开关行。
class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: enabled ? Colors.black87 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeColor: Colors.black87,
            inactiveThumbColor: Colors.grey,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final bool red;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    this.filled = false,
    this.red = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (filled && red) {
      bg = Colors.redAccent;
    } else if (filled) {
      bg = Colors.black87;
    } else {
      bg = Colors.black.withValues(alpha: 0.05);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: filled ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
