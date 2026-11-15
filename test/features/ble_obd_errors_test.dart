// BLE 链路错误分类单测：statusCopy 单出口、门禁类分流、平台异常映射。
// 2026-11-15 从 ble_obd_transport.dart 拆出 ble_obd_errors.dart 时补的直
// 接测试（此前该路径只经 widget/controller 间接触达；Android 权限拒绝
// 的消息嗅探在评审轮修过一次，这里第一次有回归守卫）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_errors.dart';

void main() {
  group('statusCopy：每个 kind 都有用户文案', () {
    test('七种 kind 全部非空且两两不同', () {
      final copies = {
        for (final kind in BleObdLinkErrorKind.values)
          BleObdTransportException(kind).statusCopy,
      };
      expect(copies, hasLength(BleObdLinkErrorKind.values.length));
      expect(copies.any((copy) => copy.isEmpty), isFalse);
    });

    test('关键文案锁定（权限拒绝/蓝牙未开/链路丢失）', () {
      expect(
        const BleObdTransportException(BleObdLinkErrorKind.permissionDenied)
            .statusCopy,
        '蓝牙权限未授权：请在系统设置 > Lunio 中允许蓝牙',
      );
      expect(
        const BleObdTransportException(BleObdLinkErrorKind.adapterOff)
            .statusCopy,
        '蓝牙未开启：请打开蓝牙后重试',
      );
      expect(
        const BleObdTransportException(BleObdLinkErrorKind.linkLost)
            .statusCopy,
        '连接已断开',
      );
    });
  });

  group('isGateError：门禁类三查', () {
    test('蓝牙关/不支持/权限拒绝是门禁类', () {
      expect(BleObdLinkErrorKind.adapterOff.isGateError, isTrue);
      expect(BleObdLinkErrorKind.adapterUnavailable.isGateError, isTrue);
      expect(BleObdLinkErrorKind.permissionDenied.isGateError, isTrue);
    });

    test('设备/链路类不是门禁类', () {
      expect(BleObdLinkErrorKind.deviceNotFound.isGateError, isFalse);
      expect(BleObdLinkErrorKind.connectFailed.isGateError, isFalse);
      expect(BleObdLinkErrorKind.serviceMissing.isGateError, isFalse);
      expect(BleObdLinkErrorKind.linkLost.isGateError, isFalse);
    });
  });

  group('bleObdPermissionDeniedError：平台异常 → 权限拒绝', () {
    test('Android 权限拒绝文案识别为 permissionDenied', () {
      final error = PlatformException(
        code: 'scan_failed',
        message:
            'Permission android.permission.BLUETOOTH_SCAN required to scan devices',
      );
      final mapped = bleObdPermissionDeniedError(error);
      expect(mapped?.kind, BleObdLinkErrorKind.permissionDenied);
      expect(mapped?.cause, same(error));
    });

    test('定位权限文案（API 30 及以下）同样识别', () {
      final mapped = bleObdPermissionDeniedError(
        PlatformException(
          code: 'scan_failed',
          message:
              'Permission android.permission.ACCESS_FINE_LOCATION required',
        ),
      );
      expect(mapped?.kind, BleObdLinkErrorKind.permissionDenied);
    });

    test('非权限异常返回 null（调用方按兜底类别包装）', () {
      expect(
        bleObdPermissionDeniedError(
          PlatformException(code: 'io', message: 'write timeout'),
        ),
        isNull,
      );
      expect(bleObdPermissionDeniedError(StateError('adapter off')), isNull);
    });

    test('已是 permissionDenied 的异常原样返回，其他 kind 返回 null', () {
      const denied =
          BleObdTransportException(BleObdLinkErrorKind.permissionDenied);
      expect(bleObdPermissionDeniedError(denied), same(denied));
      expect(
        bleObdPermissionDeniedError(
          const BleObdTransportException(BleObdLinkErrorKind.connectFailed),
        ),
        isNull,
      );
    });
  });

  group('mapBleObdLinkFailure：权限优先，其余归 fallback', () {
    test('可辨识异常原样透传', () {
      const original =
          BleObdTransportException(BleObdLinkErrorKind.serviceMissing);
      expect(
        mapBleObdLinkFailure(
          original,
          fallback: BleObdLinkErrorKind.connectFailed,
        ),
        same(original),
      );
    });

    test('权限拒绝覆盖 fallback', () {
      final mapped = mapBleObdLinkFailure(
        PlatformException(
          code: 'scan_failed',
          message: 'Permission android.permission.BLUETOOTH_SCAN required',
        ),
        fallback: BleObdLinkErrorKind.deviceNotFound,
      );
      expect(mapped.kind, BleObdLinkErrorKind.permissionDenied);
    });

    test('普通异常按 fallback 包装并保留 cause', () {
      final cause = StateError('boom');
      final mapped = mapBleObdLinkFailure(
        cause,
        fallback: BleObdLinkErrorKind.connectFailed,
      );
      expect(mapped.kind, BleObdLinkErrorKind.connectFailed);
      expect(mapped.cause, same(cause));
    });
  });
}
