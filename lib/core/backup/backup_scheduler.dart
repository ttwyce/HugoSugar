import '../note/note_store.dart';
import 'backup_config.dart';
import 'backup_service.dart';

/// 每日自动备份。
///
/// ## 为什么放在启动路径上
///
/// Flutter 侧没有可靠的后台定时任务（`workmanager` 是原生插件，
/// 且各厂商杀后台策略不同）。与其引入一个"有时不跑"的后台任务，
/// 不如在 App 启动/回到前台时检查「距上次备份是否超过一天」。
///
/// 代价是：如果用户一周没打开 App，这一周就不会有备份。
/// 但想法本身就是「在 App 里写」的产物，不开 App 就不会有新内容，
/// 所以这个代价实际上不存在。
///
/// ## 为什么失败必须静默
///
/// 自动备份是锦上添花。网络不通、服务器临时 503 都不该在启动时
/// 弹一个红条吓用户 —— 手动备份仍然可用，用户自己会发现问题。
/// 因此这里吞掉所有异常，只在 [BackupConfig.lastBackupAt] 上体现成功。
class BackupScheduler {
  const BackupScheduler._();

  /// 距离上次成功备份多久才再次自动备份。
  ///
  /// 用 23 小时而不是 24：否则「昨天 09:00 备份、今天 08:59 打开 App」
  /// 会因为差一分钟而跳过，随后几天可能一直错开同一分钟。
  static const Duration interval = Duration(hours: 23);

  /// 如果到期就备份一次。任何异常都不外抛。
  static Future<void> runIfDue(NoteStore store) async {
    try {
      final configStore = await BackupConfigStore.open();
      final config = await configStore.load();
      if (!config.canAutoBackup) return;

      final last = config.lastBackupAt;
      if (last != null && DateTime.now().difference(last) < interval) {
        return;
      }

      final service = BackupService(store: store, config: config);
      final outcome = await service.backupNow(passphrase: config.passphrase);
      if (!outcome.ok) return;

      await configStore.save(
        config.copyWith(
          lastBackupAt: DateTime.now(),
          lastBackupNoteCount: outcome.noteCount,
        ),
      );
    } catch (_) {
      // 见类注释：自动备份失败不能影响 App 启动
    }
  }
}
