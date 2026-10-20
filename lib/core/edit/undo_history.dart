import 'dart:async';

/// 一次编辑快照：标题 + 正文。
///
/// 两者放在一起是因为「撤销」在用户心里是一次操作，
/// 拆成两个栈会出现「标题退回去了但正文没退」的错位。
class EditSnapshot {
  const EditSnapshot(this.title, this.body);

  final String title;
  final String body;

  bool sameAs(EditSnapshot o) => title == o.title && body == o.body;
}

/// 编辑撤销 / 重做栈。
///
/// 为什么不直接用 Flutter 自带的 undo：那一套绑在 TextField 的
/// 输入连接上，中文输入法的组合态（composing）会打断它，
/// 而且没法跨「标题 + 正文」一起回退，也没法从自定义按钮触发。
///
/// 关键设计是**防抖合并**：每敲一个字就压一条快照，栈会瞬间爆炸，
/// 撤一次只退一个字，还不如不撤。这里把 450ms 内的连续输入合并成一步，
/// 「打完一句话」≈ 一步，「粘一整段」≈ 一步。
class EditHistory {
  EditHistory({
    this.maxEntries = 200,
    this.debounce = const Duration(milliseconds: 450),
  });

  final int maxEntries;
  final Duration debounce;

  final List<EditSnapshot> _entries = [];
  int _index = -1;

  Timer? _timer;
  EditSnapshot? _pending;

  /// 由外部在「程序化改写文本」时打开，避免撤销本身又被记进历史。
  bool _muted = false;

  bool get canUndo => _index > 0;
  bool get canRedo => _index >= 0 && _index < _entries.length - 1;

  /// 载入文档后建立初始快照，这个状态不可撤销（再往前就没东西了）。
  void seed(String title, String body) {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _entries
      ..clear()
      ..add(EditSnapshot(title, body));
    _index = 0;
  }

  void mute(bool v) => _muted = v;

  /// 记录一次编辑意图（防抖，稍后真正落栈）。
  void record(String title, String body) {
    if (_muted) return;
    _pending = EditSnapshot(title, body);
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  /// 把待定的快照立即落栈。
  void flush() {
    _timer?.cancel();
    _timer = null;
    final p = _pending;
    _pending = null;
    if (p == null) return;
    if (_index >= 0 && _entries[_index].sameAs(p)) return;

    // 在历史中间编辑 → 丢弃后面的 redo 分支
    if (_index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(p);
    _index = _entries.length - 1;

    if (_entries.length > maxEntries) {
      final overflow = _entries.length - maxEntries;
      _entries.removeRange(0, overflow);
      _index -= overflow;
    }
  }

  /// 撤销：返回上一步快照；没有可退的返回 null。
  ///
  /// 先 flush 是因为「刚敲完还没满 450ms 就想撤」很常见，
  /// 不落地的话当前内容不在栈里，一撤会跳两步。
  EditSnapshot? undo() {
    flush();
    if (_index <= 0) return null;
    _index--;
    return _entries[_index];
  }

  /// 重做。**不能**先 flush —— 那会把 redo 分支截断掉。
  EditSnapshot? redo() {
    if (_index < 0 || _index >= _entries.length - 1) return null;
    _index++;
    return _entries[_index];
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _entries.clear();
    _pending = null;
    _index = -1;
  }
}
