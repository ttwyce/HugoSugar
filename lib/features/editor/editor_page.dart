import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// 编辑器：全屏、无 Tab、顶栏自动淡出。
///
/// 设计要点（见设计规范 §3.2）：
/// - 输入 2 秒后顶栏淡到 0.15，点任意处恢复
/// - 底部只显示字数与保存状态
/// - 正文行高 1.75，左右边距 20
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.title});

  final String title;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  final _bodyFocus = FocusNode();

  Timer? _idleTimer;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.title);
    _bodyCtrl = TextEditingController(
      text: '在这里开始写。\n\n'
          '顶栏会在你停笔两秒后淡出，点击任意位置可以恢复。',
    );
    _bodyCtrl.addListener(_onTyping);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _bodyCtrl.removeListener(_onTyping);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _onTyping() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _reveal() {
    if (_chromeVisible) return;
    setState(() => _chromeVisible = true);
  }

  int get _charCount => _bodyCtrl.text.replaceAll(RegExp(r'\s'), '').length;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _reveal,
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 52),
                    // 标题
                    TextField(
                      controller: _titleCtrl,
                      style: AppTypography.editorTitle.copyWith(
                        color: c.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        hintText: '标题',
                        hintStyle: AppTypography.editorTitle.copyWith(
                          color: c.textTertiary,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    // 元信息
                    Row(
                      children: [
                        Text(
                          'draft',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: c.textTertiary,
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Text(
                          '·',
                          style: TextStyle(color: c.textTertiary),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Text(
                          '刚刚',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    // 正文
                    Expanded(
                      child: TextField(
                        controller: _bodyCtrl,
                        focusNode: _bodyFocus,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: AppTypography.editorBody.copyWith(
                          color: c.textPrimary,
                        ),
                        decoration: InputDecoration(
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          hintText: '正文…',
                          hintStyle: AppTypography.editorBody.copyWith(
                            color: c.textTertiary,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 悬浮顶栏：自动淡出
            AnimatedOpacity(
              opacity: _chromeVisible ? 1 : 0.15,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Container(
                padding: EdgeInsets.only(top: topInset, left: 6, right: 6),
                height: topInset + 48,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      tooltip: '返回',
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.undo, size: 20),
                      tooltip: '撤销',
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.search, size: 20),
                      tooltip: '查找',
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz, size: 20),
                      tooltip: '更多',
                    ),
                  ],
                ),
              ),
            ),

            // 底部悬浮：字数 + 预览
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0.15,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                  color: c.background,
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Text(
                          '$_charCount 字',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: c.textTertiary,
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Icon(Icons.check_circle, size: 12, color: c.textTertiary),
                        const SizedBox(width: 2),
                        Text(
                          '已保存',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: c.textTertiary,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('预览'),
                        ),
                        const SizedBox(width: AppSpace.xxs),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('AI'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}