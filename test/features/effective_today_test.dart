// 生效今天 provider 的零点自刷新机制测试（ADR 0025）。
//
// 三件事：跨零点自动翻页并重排次日；手动日期优先（跨零点仍是手动日期）；
// 容器 dispose 取消定时器（无残留，推进时间不抛）。时间用 fakeAsync 控制，
// 时钟经 appDateContextProvider 注入并随假时间推进；不碰数据库——手动
// 日期用 provider 覆写，偏好纪元用真实 Notifier。
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/app_date_context.dart';
import 'package:lunio/core/date/local_date.dart';

void main() {
  group('effectiveTodayProvider 零点自刷新（ADR 0025）', () {
    test('跨零点自动翻页，并重排次日零点', () {
      fakeAsync((async) {
        final base = DateTime(2026, 5, 19, 23, 59, 59);
        DateTime clock() => base.add(async.elapsed);
        final container = ProviderContainer(
          overrides: [
            appDateContextProvider.overrideWithValue(
              AppDateContext(readSystemNow: clock),
            ),
            manualDatePreferenceProvider.overrideWith((ref) async => null),
          ],
        );
        final values = <LocalDate>[];
        final sub = container.listen(
          effectiveTodayProvider,
          (_, next) {
            final value = next.value;
            if (value != null) {
              values.add(value);
            }
          },
          fireImmediately: true,
        );
        async.flushMicrotasks();
        expect(values.last, const LocalDate(2026, 5, 19));

        // 1 秒后跨入 5 月 20 日：定时器失效 provider，重算并排下一次。
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(values.last, const LocalDate(2026, 5, 20));

        // 再过 24 小时到 5 月 21 日：证明次日零点已重排，不是只翻一次。
        async.elapse(const Duration(days: 1));
        async.flushMicrotasks();
        expect(values.last, const LocalDate(2026, 5, 21));

        sub.close();
        container.dispose();
      });
    });

    test('手动日期优先：跨零点仍返回手动日期', () {
      fakeAsync((async) {
        final base = DateTime(2026, 5, 19, 23, 59, 59);
        DateTime clock() => base.add(async.elapsed);
        final container = ProviderContainer(
          overrides: [
            appDateContextProvider.overrideWithValue(
              AppDateContext(readSystemNow: clock),
            ),
            manualDatePreferenceProvider.overrideWith(
              (ref) async => const LocalDate(2026, 1, 1),
            ),
          ],
        );
        final sub = container.listen(
          effectiveTodayProvider,
          (_, _) {},
          fireImmediately: true,
        );
        async.flushMicrotasks();
        async.elapse(const Duration(days: 2));
        async.flushMicrotasks();
        expect(
          container.read(effectiveTodayProvider).value,
          const LocalDate(2026, 1, 1),
        );
        sub.close();
        container.dispose();
      });
    });

    test('最后一个观察者离开时取消定时器，重新观察时重排', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            appDateContextProvider.overrideWithValue(
              AppDateContext(
                readSystemNow: () => DateTime(2026, 5, 19, 12),
              ),
            ),
            manualDatePreferenceProvider.overrideWith((ref) async => null),
          ],
        );
        final first = container.listen(
          effectiveTodayProvider,
          (_, _) {},
          fireImmediately: true,
        );
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));

        // 最后一个观察者离开 → pause 生命周期取消定时器（外部容器测试
        // 的 pending timer 不变式要求）。
        first.close();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);

        // 重新观察 → resume 重排下一次零点。
        final second = container.listen(
          effectiveTodayProvider,
          (_, _) {},
          fireImmediately: true,
        );
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));

        second.close();
        container.dispose();
      });
    });

    test('容器 dispose 取消定时器：无残留，推进时间不抛', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            appDateContextProvider.overrideWithValue(
              AppDateContext(
                readSystemNow: () => DateTime(2026, 5, 19, 12),
              ),
            ),
            manualDatePreferenceProvider.overrideWith((ref) async => null),
          ],
        );
        final sub = container.listen(
          effectiveTodayProvider,
          (_, _) {},
          fireImmediately: true,
        );
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));

        sub.close();
        container.dispose();
        expect(async.pendingTimers, isEmpty);
        // 未取消的定时器会在推进后对已释放 provider 调 invalidateSelf，
        // 抛错即红。
        async.elapse(const Duration(days: 1));
      });
    });
  });
}
