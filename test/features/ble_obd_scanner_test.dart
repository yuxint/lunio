// BLE 扫描器 adapter 单测（ADR 0024 分片 1）：门禁分流、启动顺序、起始窗
// 口停扫、半开清理、停扫收尾与合并节奏。全部经 FakeObdRadio 驱动，时间
// 用 fakeAsync——零真实等待、零 flutter_blue_plus 依赖。
//
// 门禁窗口与合并器时钟都可注入；用例断言经假 radio 的共享事件日志（跨
// 对象顺序，如「先订阅结果流再 startScan」）。
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_errors.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_link.dart';
import 'package:lunio/features/shell/diagnostics/ble_scan_entries.dart';
import 'package:lunio/features/shell/diagnostics/obd_radio.dart';

import '../helpers/fake_obd_radio.dart';

/// 可推进时钟（合并器的时间源；fakeAsync 只控定时器不控 DateTime.now）。
class _MutableClock {
  _MutableClock(this._value);

  DateTime _value;

  DateTime now() => _value;

  void advance(Duration duration) => _value = _value.add(duration);
}

BleObdLinkErrorKind kindOf(Object? error) {
  expect(error, isA<BleObdTransportException>());
  return (error! as BleObdTransportException).kind;
}

void main() {
  group('适配器门禁', () {
    test('不支持蓝牙：adapterUnavailable，不启动扫描', () {
      fakeAsync((async) {
        final radio = FakeObdRadio(supported: false);
        final scanner = BleObdScanner(radio: radio);
        Object? error;
        unawaited(scanner.start().catchError((Object e) {
          error = e;
        }));
        async.flushMicrotasks();

        expect(kindOf(error), BleObdLinkErrorKind.adapterUnavailable);
        expect(radio.startScanCalls, 0);
      });
    });

    test('unknown 超过等待窗口：adapterUnavailable', () {
      fakeAsync((async) {
        final radio = FakeObdRadio();
        final scanner = BleObdScanner(
          radio: radio,
          adapterStateWindow: const Duration(seconds: 10),
        );
        Object? error;
        unawaited(scanner.start().catchError((Object e) {
          error = e;
        }));
        async.flushMicrotasks();
        expect(error, isNull);

        async.elapse(const Duration(seconds: 10));

        expect(kindOf(error), BleObdLinkErrorKind.adapterUnavailable);
        expect(radio.startScanCalls, 0);
      });
    });

    test('蓝牙关闭 / 未授权：adapterOff / permissionDenied', () {
      for (final (state, expected) in [
        (RadioAdapterState.off, BleObdLinkErrorKind.adapterOff),
        (RadioAdapterState.unauthorized, BleObdLinkErrorKind.permissionDenied),
      ]) {
        fakeAsync((async) {
          final radio = FakeObdRadio()..emitAdapterState(state);
          final scanner = BleObdScanner(radio: radio);
          Object? error;
          unawaited(scanner.start().catchError((Object e) {
            error = e;
          }));
          async.flushMicrotasks();

          expect(kindOf(error), expected);
          expect(radio.startScanCalls, 0);
        });
      }
    });

    test('状态流错误：权限文案 → permissionDenied', () {
      fakeAsync((async) {
        final radio = FakeObdRadio();
        final scanner = BleObdScanner(radio: radio);
        Object? error;
        unawaited(scanner.start().catchError((Object e) {
          error = e;
        }));
        async.flushMicrotasks();

        radio.emitAdapterError(
          PlatformException(
            code: 'scan_failed',
            message:
                'Permission android.permission.BLUETOOTH_SCAN required to scan devices',
          ),
        );
        async.flushMicrotasks();

        expect(kindOf(error), BleObdLinkErrorKind.permissionDenied);
      });
    });
  });

  group('启动与停止', () {
    test('先订阅结果流再 startScan；stop 撤订阅与节拍器、停扫一次', () {
      fakeAsync((async) {
        final radio = FakeObdRadio()..emitAdapterState(RadioAdapterState.on);
        final scanner = BleObdScanner(radio: radio);
        final emissions = <List<BleObdScanEntry>>[];
        scanner.results.listen(emissions.add);

        unawaited(scanner.start());
        async.flushMicrotasks();

        expect(radio.startScanCalls, 1);
        final listenIndex = radio.events.indexOf('listenScanResults');
        final startIndex = radio.events.indexOf('startScan');
        expect(listenIndex, isNonNegative);
        expect(listenIndex, lessThan(startIndex));

        unawaited(scanner.stop());
        async.flushMicrotasks();

        expect(radio.events, contains('cancelScanResults'));
        expect(radio.stopScanCalls, 1);
        expect(async.pendingTimers, isEmpty);

        // 停扫后推结果不再发射（订阅已撤）。
        radio.emitScanResults([radio.scanResultFor('dev-1')]);
        async.flushMicrotasks();
        expect(emissions, isEmpty);

        // 重复 stop 幂等：不再停扫。
        unawaited(scanner.stop());
        async.flushMicrotasks();
        expect(radio.stopScanCalls, 1);
      });
    });

    test('起始窗口内 stop：不启动扫描、无残留订阅', () {
      fakeAsync((async) {
        final radio = FakeObdRadio();
        final scanner = BleObdScanner(radio: radio);
        Object? error;
        unawaited(scanner.start().catchError((Object e) {
          error = e;
        }));
        async.flushMicrotasks();

        unawaited(scanner.stop());
        async.flushMicrotasks();
        radio.emitAdapterState(RadioAdapterState.on);
        async.flushMicrotasks();

        expect(error, isNull);
        expect(radio.startScanCalls, 0);
        expect(radio.events, isNot(contains('listenScanResults')));
      });
    });

    test('起始窗口内 stop 后重开：新 start 等旧 attempt 收尾并接管', () {
      fakeAsync((async) {
        final radio = FakeObdRadio();
        final scanner = BleObdScanner(radio: radio);
        var firstStarted = false;
        var secondStarted = false;
        unawaited(scanner.start().then((_) => firstStarted = true));
        async.flushMicrotasks();
        expect(radio.startScanCalls, 0);

        // 权限弹窗期间关 sheet 再重开：stop 作废在途 start，重开的
        // start 不得被 _starting 门卫静默吞掉（旧实现两种 future 都
        // 正常完成，但 startScan 永不发生——扫描 sheet 空转）。
        unawaited(scanner.stop());
        unawaited(scanner.start().then((_) => secondStarted = true));
        async.flushMicrotasks();
        expect(secondStarted, isFalse);

        radio.emitAdapterState(RadioAdapterState.on);
        async.flushMicrotasks();

        expect(firstStarted, isTrue);
        expect(secondStarted, isTrue);
        expect(radio.startScanCalls, 1);
        // 订阅只由接管的 attempt 建立一次（旧 attempt 在检查点就退出）。
        expect(
          radio.events.where((event) => event == 'listenScanResults'),
          hasLength(1),
        );

        unawaited(scanner.stop());
        async.flushMicrotasks();
        expect(radio.stopScanCalls, 1);
      });
    });

    test('startScan 抛权限异常：类型化 permissionDenied + 半开清理', () {
      fakeAsync((async) {
        final radio = FakeObdRadio()..emitAdapterState(RadioAdapterState.on);
        radio.startScanError = PlatformException(
          code: 'scan_failed',
          message:
              'Permission android.permission.BLUETOOTH_SCAN required to scan devices',
        );
        final scanner = BleObdScanner(radio: radio);
        Object? error;
        unawaited(scanner.start().catchError((Object e) {
          error = e;
        }));
        async.flushMicrotasks();

        expect(kindOf(error), BleObdLinkErrorKind.permissionDenied);
        expect(radio.events, contains('cancelScanResults'));
        expect(radio.stopScanCalls, 1);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('扫描清单合并节奏', () {
    test('首拍立即、纯数字更新合并到 1Hz、新设备立即', () {
      fakeAsync((async) {
        final radio = FakeObdRadio()..emitAdapterState(RadioAdapterState.on);
        final clock = _MutableClock(DateTime(2026, 5, 19, 12));
        final scanner = BleObdScanner(radio: radio, now: clock.now);
        final emissions = <List<BleObdScanEntry>>[];
        scanner.results.listen(emissions.add);

        unawaited(scanner.start());
        async.flushMicrotasks();

        // 首拍立即发射。
        radio.emitScanResults([radio.scanResultFor('dev-1', rssi: -40)]);
        async.flushMicrotasks();
        expect(emissions, hasLength(1));
        expect(emissions.single.single.id, 'dev-1');

        // 同设备纯数字变化：窗口内不发射。
        radio.emitScanResults([radio.scanResultFor('dev-1', rssi: -55)]);
        async.flushMicrotasks();
        expect(emissions, hasLength(1));

        // 到点由节拍器补发最新值。
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        expect(emissions, hasLength(2));
        expect(emissions.last.single.rssi, -55);

        // 新设备立即插入发射。
        radio.emitScanResults([
          radio.scanResultFor('dev-1', rssi: -55),
          radio.scanResultFor('dev-2', rssi: -70),
        ]);
        async.flushMicrotasks();
        expect(emissions, hasLength(3));
        expect(
          emissions.last.map((entry) => entry.id),
          containsAll(['dev-1', 'dev-2']),
        );

        unawaited(scanner.stop());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
