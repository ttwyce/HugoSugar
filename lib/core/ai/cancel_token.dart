/// 取消令牌。
///
/// ## 为什么需要它
///
/// 早先的「停止」只是把 UI 的 busy 标记清掉，HTTP 请求仍在后台跑完：
/// - 用户以为省下了 token，其实一分没省
/// - 长回答会继续占用一个连接几十秒
///
/// ## 为什么不用 StreamSubscription.cancel
///
/// `await for` 循环里没法直接 cancel 自己；而 `http` 的
/// `StreamedResponse` 也不提供从外部关闭的句柄。
/// 协作式取消（循环里检查标志位）是成本最低、行为最可预测的做法：
/// 当前这个 chunk 处理完就退出，不会有半截状态写进历史。
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// 已取消时抛出，让调用链统一往上冒泡
  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }
}

/// 用户主动取消。
///
/// 单独一个类型而不是复用 AiException：取消不是错误，
/// UI 不该弹出红色错误气泡，也不该写进对话历史。
class CancelledException implements Exception {
  const CancelledException();

  @override
  String toString() => '已取消';
}