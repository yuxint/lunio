// 私有 DID 组：OBDb Honda Civic 2022 supported_commands_by_ecu（北美数据，
// 实车可能不同；一键采集的日志会给出本车实际响应）。
// 源：https://raw.githubusercontent.com/OBDb/Honda-Civic/main/tests/test_cases/2022/command_support.yaml
// 只读 mode 22 命令；ATSH 头由调试脚本按组分段设置，末尾恢复 DB 33 F1。
class ObdVendorCommandGroup {
  const ObdVendorCommandGroup({required this.header, required this.commands});

  final String header;
  final List<String> commands;
}

const List<ObdVendorCommandGroup> obdVendorCommandGroups = [
  ObdVendorCommandGroup(header: 'DA10F1', commands: [
    '222600', '222601', '222610', '222611', '222612', '222615',
    '222617', '222620', '222621', '222622', '222623', '222625',
    '222627', '222630', '222660', '222661', '222662', '222663',
    '222664', '222665', '222668', '22266A', '22266E', '22266F',
    '222673', '222676', '222678', '222679', '22267A', '22267B',
    '22267C', '22267E', '22267F', '222680', '222681', '222683',
    '222684', '222685', '222686', '222688', '222689', '22268B',
    '22268C', '22268D', '22268E', '222693', '222699', '22269A',
    '22269B', '22269C', '223000', '223001', '22300C', '22E411',
    '22E412', '22E413', '22E414', '22E415', '22E416', '22E41F',
    '22E5FF', '22E600', '22E602', '22E800', '22E801', '22E80E',
  ]),
  ObdVendorCommandGroup(header: 'DA11F1', commands: [
    '222612',
  ]),
  ObdVendorCommandGroup(header: 'DA1EF1', commands: [
    '222300', '222301', '222311', '222320', '222321', '222322',
    '222323', '222330', '222331', '222332', '222333', '222340',
    '22E50A', '22E50B', '22E50D',
  ]),
  ObdVendorCommandGroup(header: 'DA28F1', commands: [
    '224000', '224001', '224002', '224003', '224004', '224005',
    '224006', '224007', '224008', '224030', '224031', '224032',
    '224033', '224034', '224035', '224036', '224037', '224038',
    '224039', '224070', '224071', '224072', '224073', '22E600',
    '22E602',
  ]),
  ObdVendorCommandGroup(header: 'DA53F1', commands: [
    '228000', '228001', '228005',
  ]),
  ObdVendorCommandGroup(header: 'DA60F1', commands: [
    '227010', '227012', '227020', '227021', '227022', '227028',
    '227029', '22702A', '22702B', '227068', '2270A8', '2270A9',
    '2270C0', '2270C1', '2270C2', '2270C3',
  ]),
];