// GuardedOp（reminders 域重入防护小模块）的机制单测：锁 enter/exit
// 协议全部分支——空闲放行、重入记 pending、连环 pending 合并为一次
// 重跑、重跑动作里再 enter 放行（防护复位）、busy 中销毁不记 pending、
// exit 时已销毁不重跑。两个控制器（通知同步/小组件快照）的集成行为
// 各由自己的测试文件锁定，此处只锁协议本身——第三个消费者接入时以
// 本文件为语义参照。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/reminders/guarded_op.dart';

void main() {
  group('GuardedOp 重入防护协议', () {
    test('空闲时 enter 放行，exit 无 pending 不重跑', () {
      var reruns = 0;
      final op = GuardedOp(isDisposed: () => false, onRerun: () => reruns++);

      expect(op.enter(), isTrue);
      op.exit();

      expect(reruns, 0);
    });

    test('执行中来新请求被拒并记 pending，本轮结束恰好重跑一次', () {
      var reruns = 0;
      final op = GuardedOp(isDisposed: () => false, onRerun: () => reruns++);

      expect(op.enter(), isTrue);
      // 执行中（busy 未 exit）来的新请求：被拒 + 记 pending，不丢弃。
      expect(op.enter(), isFalse);
      op.exit();

      expect(reruns, 1);
    });

    test('连环多次新请求合并为一次重跑', () {
      var reruns = 0;
      final op = GuardedOp(isDisposed: () => false, onRerun: () => reruns++);

      expect(op.enter(), isTrue);
      expect(op.enter(), isFalse);
      expect(op.enter(), isFalse);
      op.exit();

      expect(reruns, 1);
    });

    test('重跑后防护复位：重跑动作里再 enter 放行', () {
      var reruns = 0;
      late final GuardedOp op;
      op = GuardedOp(isDisposed: () => false, onRerun: () {
        reruns++;
        // 重跑动作（onRerun）里再 enter：busy 已在 exit 里复位，必须
        // 放行——否则重跑轮自己被卡在门外，防护永久死锁。
        expect(op.enter(), isTrue);
        op.exit();
      });

      expect(op.enter(), isTrue);
      expect(op.enter(), isFalse);
      op.exit();

      expect(reruns, 1);
    });

    test('执行中销毁：新请求不记 pending，结束不重跑', () {
      var disposed = false;
      var reruns = 0;
      final op = GuardedOp(
        isDisposed: () => disposed,
        onRerun: () => reruns++,
      );

      expect(op.enter(), isTrue);
      disposed = true; // await 挂起期间宿主销毁
      expect(op.enter(), isFalse); // 被拒且不记 pending
      op.exit();

      expect(reruns, 0);
    });

    test('pending 已记之后才销毁：exit 不重跑', () {
      var disposed = false;
      var reruns = 0;
      final op = GuardedOp(
        isDisposed: () => disposed,
        onRerun: () => reruns++,
      );

      expect(op.enter(), isTrue);
      expect(op.enter(), isFalse); // 记下 pending
      disposed = true; // 本轮结束前宿主销毁
      op.exit();

      expect(reruns, 0);
    });
  });
}
