// BLE 传输层 adapter 单测（ADR 0024 分片 2）：建链全序、定向扫描超时、
// 通道缺失、断连回放/链路丢失、四个 await 边界上的取消收尾、单次断开、
// 发送语义与扫描归属。全部经 FakeObdRadio 驱动，fakeAsync 控时——零真
// 实等待、零 flutter_blue_plus 依赖。
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_errors.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_link.dart';
import 'package:lunio/features/shell/diagnostics/obd_radio.dart';

import '../helpers/fake_obd_radio.dart';

BleObdLinkErrorKind kindOf(Object? error) {
  expect(error, isA<BleObdTransportException>());
  return (error! as BleObdTransportException).kind;
}

/// 一次连接尝试的捕获（done/error；future 已挂 then/catchError）。
class _ConnectAttempt {
  _ConnectAttempt(this.future);

  final Future<void> future;
  Object? error;
  bool done = false;
}

_ConnectAttempt _startConnect(BleObdTransport transport, FakeAsync async) {
  final attempt = _ConnectAttempt(transport.connect());
  unawaited(attempt.future.then((_) {
    attempt.done = true;
  }).catchError((Object e) {
    attempt.error = e;
  }));
  async.flushMicrotasks();
  return attempt;
}

/// 传输层测试装具：标准 GATT + 已注册设备 + 共享事件日志。
class _TransportRig {
  _TransportRig({bool withGatt = true}) {
    radio = FakeObdRadio()..emitAdapterState(RadioAdapterState.on);
    device = radio.device(deviceId);
    if (withGatt) {
      final standard = FakeObdGatt.standard(radio.events);
      gatt = standard;
      device.services = standard.services;
    }
    transport = BleObdTransport(
      radio: radio,
      deviceId: deviceId,
      adapterStateWindow: const Duration(seconds: 10),
      directConnectScanWindow: const Duration(seconds: 8),
      connectWindow: const Duration(seconds: 15),
    );
  }

  final String deviceId = 'dev-1';
  late final FakeObdRadio radio;
  late final FakeRadioDevice device;
  FakeObdGatt? gatt;
  late final BleObdTransport transport;

  final List<List<int>> bytes = [];
  final List<Object> streamErrors = [];

  void listenStream() {
    transport.byteStream.listen(
      bytes.add,
      onError: (Object e) => streamErrors.add(e),
    );
  }

  /// 推进到「定向扫描已启动、等待目标设备出现」。
  void deliverDevice(FakeAsync async) {
    radio.emitScanResults([radio.scanResultFor(deviceId)]);
    async.flushMicrotasks();
  }
}

void main() {
  group('建链全序', () {
    test('定向扫描 → 建链 → 发现 → 先订阅后开通知；通知字节转发', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        rig.listenStream();
        final attempt = _startConnect(rig.transport, async);
        expect(rig.radio.directedScanIds, [rig.deviceId]);
        expect(attempt.done, isFalse);

        rig.deliverDevice(async);

        expect(attempt.error, isNull);
        expect(attempt.done, isTrue);
        expect(rig.device.connectCalls, 1);
        expect(rig.device.discoverCalls, 1);
        expect(rig.gatt!.notify.notifyEnabled, isTrue);

        final events = rig.radio.events;
        expect(events, contains('startDirectedScan:${rig.deviceId}'));
        expect(events, contains('connect:${rig.deviceId}'));
        expect(events, contains('discover:${rig.deviceId}'));
        final subscribeIndex =
            events.indexOf('subscribe:${BleObdUuids.notify}');
        final setNotifyIndex = events
            .indexOf('setNotify:${BleObdUuids.notify}:true');
        expect(subscribeIndex, isNonNegative);
        expect(subscribeIndex, lessThan(setNotifyIndex));

        // 通知字节 → 传输层字节流。
        rig.gatt!.notify.emitValue([0x41, 0x2F, 0x60]);
        async.flushMicrotasks();
        expect(rig.bytes, [
          [0x41, 0x2F, 0x60]
        ]);

        unawaited(rig.transport.disconnect());
        async.flushMicrotasks();
        expect(rig.device.disconnectCalls, 1);
      });
    });

    test('定向扫描窗口内未发现设备：deviceNotFound + 停扫', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        final attempt = _startConnect(rig.transport, async);
        expect(rig.radio.directedScanIds, [rig.deviceId]);

        async.elapse(const Duration(seconds: 8));

        expect(kindOf(attempt.error), BleObdLinkErrorKind.deviceNotFound);
        expect(rig.radio.stopScanCalls, 1);
      });
    });

    test('服务缺失 / 写入通道缺失：serviceMissing', () {
      // 没有任何服务。
      fakeAsync((async) {
        final rig = _TransportRig(withGatt: false);
        final attempt = _startConnect(rig.transport, async);
        rig.deliverDevice(async);
        expect(kindOf(attempt.error), BleObdLinkErrorKind.serviceMissing);
      });

      // 有服务但缺写入 characteristic。
      fakeAsync((async) {
        final rig = _TransportRig(withGatt: false);
        rig.device.services = [
          RadioService(
            uuid: BleObdUuids.service,
            characteristics: [
              FakeRadioCharacteristic(
                uuid: BleObdUuids.notify,
                events: rig.radio.events,
              ),
            ],
          ),
        ];
        final attempt = _startConnect(rig.transport, async);
        rig.deliverDevice(async);
        expect(kindOf(attempt.error), BleObdLinkErrorKind.serviceMissing);
      });
    });

    test('门禁类失败（蓝牙关闭）在建链入口分流：adapterOff，不扫描', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        rig.radio.emitAdapterState(RadioAdapterState.off);
        final attempt = _startConnect(rig.transport, async);
        expect(kindOf(attempt.error), BleObdLinkErrorKind.adapterOff);
        expect(rig.radio.directedScanIds, isEmpty);
      });
    });
  });

  group('连接状态与链路丢失', () {
    test('建链前回放 disconnected 不误报；建链后断连抛 linkLost', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        rig.listenStream();
        final attempt = _startConnect(rig.transport, async);
        rig.deliverDevice(async);
        expect(attempt.done, isTrue);
        expect(rig.streamErrors, isEmpty);

        rig.device.setConnectionState(RadioConnectionState.disconnected);
        async.flushMicrotasks();

        expect(rig.streamErrors, hasLength(1));
        expect(kindOf(rig.streamErrors.single), BleObdLinkErrorKind.linkLost);
      });
    });

    test('我方 disconnect 不误报 linkLost；断开指令恰一次', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        rig.listenStream();
        final attempt = _startConnect(rig.transport, async);
        rig.deliverDevice(async);
        expect(attempt.done, isTrue);

        unawaited(rig.transport.disconnect());
        async.flushMicrotasks();

        expect(rig.streamErrors, isEmpty);
        expect(rig.device.disconnectCalls, 1);

        // 幂等：重复 disconnect 不再发断开指令。
        unawaited(rig.transport.disconnect());
        async.flushMicrotasks();
        expect(rig.device.disconnectCalls, 1);
      });
    });
  });

  group('建链中途取消（四个 await 边界）', () {
    test('定位阶段取消：connectFailed，无设备断开', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        final attempt = _startConnect(rig.transport, async);

        unawaited(rig.transport.disconnect());
        async.flushMicrotasks();
        rig.deliverDevice(async);

        expect(kindOf(attempt.error), BleObdLinkErrorKind.connectFailed);
        expect(rig.device.disconnectCalls, 0);
        expect(rig.radio.stopScanCalls, 1);
      });
    });

    test('建链阶段取消：connectFailed + 迟到建链清理（断开恰一次）', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        rig.device.connectGate = Completer<void>();
        final attempt = _startConnect(rig.transport, async);
        rig.deliverDevice(async);
        expect(rig.device.connectCalls, 1);

        unawaited(rig.transport.disconnect());
        async.flushMicrotasks();
        rig.device.connectGate!.complete();
        async.flushMicrotasks();

        expect(kindOf(attempt.error), BleObdLinkErrorKind.connectFailed);
        expect(rig.device.disconnectCalls, 1);
      });
    });

    test('服务发现阶段取消：connectFailed + 断开恰一次', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        rig.device.discoverGate = Completer<void>();
        final attempt = _startConnect(rig.transport, async);
        rig.deliverDevice(async);
        expect(rig.device.discoverCalls, 1);

        unawaited(rig.transport.disconnect());
        async.flushMicrotasks();
        rig.device.discoverGate!.complete();
        async.flushMicrotasks();

        expect(kindOf(attempt.error), BleObdLinkErrorKind.connectFailed);
        expect(rig.device.disconnectCalls, 1);
      });
    });

    test('开通知阶段取消：connectFailed + 断开恰一次', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        rig.gatt!.notify.setNotifyGate = Completer<void>();
        final attempt = _startConnect(rig.transport, async);
        rig.deliverDevice(async);
        expect(rig.gatt!.notify.setNotifyCalls, 1);

        unawaited(rig.transport.disconnect());
        async.flushMicrotasks();
        rig.gatt!.notify.setNotifyGate!.complete();
        async.flushMicrotasks();

        expect(kindOf(attempt.error), BleObdLinkErrorKind.connectFailed);
        expect(rig.device.disconnectCalls, 1);
      });
    });
  });

  group('发送', () {
    test('未连接抛 StateError；连接后写入捕获', () {
      fakeAsync((async) {
        final rig = _TransportRig();
        Object? sendError;
        unawaited(rig.transport.send([0x41]).catchError((Object e) {
          sendError = e;
        }));
        async.flushMicrotasks();
        expect(sendError, isA<StateError>());

        final attempt = _startConnect(rig.transport, async);
        rig.deliverDevice(async);
        expect(attempt.done, isTrue);

        unawaited(rig.transport.send([0x41, 0x54]));
        async.flushMicrotasks();
        expect(rig.gatt!.write.writes, [
          [0x41, 0x54]
        ]);

        unawaited(rig.transport.disconnect());
        async.flushMicrotasks();
      });
    });
  });

  group('扫描归属', () {
    test('旧定向扫描收尾不停掉后来者启动的扫描', () {
      fakeAsync((async) {
        final radio = FakeObdRadio()..emitAdapterState(RadioAdapterState.on);
        final transport = BleObdTransport(
          radio: radio,
          deviceId: 'dev-1',
          directConnectScanWindow: const Duration(seconds: 8),
        );
        Object? transportError;
        unawaited(transport.connect().catchError((Object e) {
          transportError = e;
        }));
        async.flushMicrotasks();
        expect(radio.directedScanIds, ['dev-1']);

        // 扫描器随后启动新扫描（领到更新令牌）。
        final scanner = BleObdScanner(radio: radio);
        unawaited(scanner.start());
        async.flushMicrotasks();
        expect(radio.startScanCalls, 1);

        // 旧定向扫描超时收尾：不得停掉新扫描。
        async.elapse(const Duration(seconds: 8));
        expect(kindOf(transportError), BleObdLinkErrorKind.deviceNotFound);
        expect(radio.stopScanCalls, 0);

        // 扫描器自己的 stop 仍会停扫。
        unawaited(scanner.stop());
        async.flushMicrotasks();
        expect(radio.stopScanCalls, 1);
      });
    });
  });
}
