// NotificationSyncGuard / SyncRun 的单元测试：四层防竞态协议里"这轮还
// 作数吗"的票语义（同步代数 R8、写库中间态旗 2026-09-24、disposed R13，
// 协议全文见守卫模块文件头）。守卫是纯 Dart + 内存 provider，测试直接
// 开容器领票，不需要数据库与平台通道；重入 pending 重跑、签名比对等
// 控制器侧行为仍在 notification_sync_controller_test.dart 全链路锁定。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/reminders/notification_sync_guard.dart';

void main() {
  test('开工票有效；写库进行中被旗拦；收尾后旧票被代数拦、新票有效', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final guard = container.read(notificationSyncGuardProvider);

    final run = guard.acquire();
    expect(run.isValid, isTrue);

    guard.beginDataReset();
    expect(guard.isDataResetInFlight, isTrue);
    expect(run.isValid, isFalse, reason: '旗半：写库进行中，票必须失效');
    expect(
      guard.acquire().isValid,
      isFalse,
      reason: '旗半的真正职责：写库进行中新领的票——代数快照已是 bump 后'
          '的值，代数半拦不住，只有旗能拦（协调器侧停车保存链等无入口'
          '旗检查的领票场景）',
    );

    guard.settleDataReset();
    expect(guard.isDataResetInFlight, isFalse);
    expect(
      run.isValid,
      isFalse,
      reason: '代数半：settle 的 bump 作废写库期间持有的旧票——'
          '"先升代数再关旗"保证旗一关必然能被代数拦住',
    );
    expect(
      container.read(notificationSyncGenerationProvider),
      2,
      reason: '破坏性写库前后各 bump 一次（双 bump 契约）',
    );
    expect(guard.acquire().isValid, isTrue, reason: '收尾后新票有效');
  });

  test('dispose 注入后票失效；恢复注入后重新有效（谓词随最新状态求值）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final guard = container.read(notificationSyncGuardProvider);

    var disposed = false;
    final run = guard.acquire(isDisposed: () => disposed);
    expect(run.isValid, isTrue);
    disposed = true;
    expect(run.isValid, isFalse, reason: 'disposed 半：壳层已拆，在途任务放弃');
    disposed = false;
    expect(run.isValid, isTrue);
  });

  test('多次破坏性写库：代数累加，任一历史时刻的旧票都被拦', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final guard = container.read(notificationSyncGuardProvider);

    final run = guard.acquire();
    guard.beginDataReset();
    guard.settleDataReset();
    guard.beginDataReset();
    guard.settleDataReset();
    expect(container.read(notificationSyncGenerationProvider), 4);
    expect(run.isValid, isFalse);
    expect(guard.acquire().isValid, isTrue);
  });

  test('不注入 disposed 的票（协调器侧用法）只看旗与代数', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final guard = container.read(notificationSyncGuardProvider);

    final run = guard.acquire();
    guard.beginDataReset();
    guard.settleDataReset();
    expect(run.isValid, isFalse, reason: '两轮 bump 后旧票被代数拦');
    expect(guard.isDataResetInFlight, isFalse);
  });
}
