// 表单 sheet 运行时（showLunioFormSheet + FormSheetHandle）：编辑表单类
// 底部弹层的完整生命周期运行时，ADR 0016。
//
// ≈ Java Web 里抽出来的"弹窗表单基类 + 弹窗生命周期管理器"：过去 11 个
// 表单 sheet 入口各自手写同一条 ~40 行生命周期（await 装载 → mounted
// 守卫 → showLunioModalSheet → PrototypeSheetFrame → 键盘 inset →
// 提交闭包里 pop + toast），键盘 context 的坑注释在 4 个文件里逐字
// 重复。现在时序只有这一份，各入口只声明"取数、守卫、画表单、提交、
// 成功文案"五件事；表单 State 的宿主接法（widget 实现接口 + State 混入
// 零状态转发 mixin）也归本模块（2026-09-26 收编，见 FormSheetHandleHost）。
//
// 固定时序（2026-09-25 拷问定稿；装载结果 2026-10-15 类型化）：
//   1. [load] 预装载（打开 sheet 前执行；失败 → friendlyError toast，
//      sheet 不出现）。load 返回 typed 装载结果 D，guard 与 builder 直接收
//      这个值——"装载了什么"是编译期契约，入口函数不再需要"可空闭包
//      捕获变量 + 装载赋值 + builder 非空断言"的三步舞；需要按装载结果
//      改头部（如车辆品牌车型副标题）时经 handle.setSubtitle 更新；
//      没有预装载步骤的表单走 showLunioFormSheetNoLoad 薄皮入口。
//   2. [guard] 领域前置守卫（返回非空文案 → info toast，sheet 不出现）；
//   3. showLunioModalSheet(barrierDismissible: false) 包
//      PrototypeSheetFrame——键盘 inset 由本模块经 sheet 自己的 context
//      读取（外层 context 在 sheet 构建时定格为 0，键盘弹起不更新，
//      曾致底部输入被遮挡），调用方不再裸写 MediaQuery；
//   4. 提交 = handle.submit：re-entrant 守卫 → saving → 动作 → 失败
//      friendlyError 写 errorText 留场 / 成功 pop（resultOnSubmit 透传
//      给入口 Future）+ successMessage toast（可空，停车倒计时/草稿
//      项目表单保持无 toast 的产品行为）；
//   5. 所有 pop 都经本模块：提交成功路径（submit）与非提交出口
//      （close：取消按钮、删除、查重"去编辑"、去系统设置）；pop 过一次
//      后再来的 submit/close 一律忽略（不重复关场）。
//
// 确认框（未调高里程、删除确认、同日查重）一律发生在 submit 生命周期
// 之前或由调用方编排，不引入"静默取消"语义。
//
// 与 modal_feedback 的关系：本模块是生命周期运行时，showLunioModalSheet
// 等原语仍是选择器/只读 sheet 的直接出口；编辑表单一律走这里。
import 'package:flutter/material.dart';

import 'formatters.dart';
import 'modal_feedback.dart';
import 'shared_widgets.dart';

/// 编辑表单 sheet 的统一入口（ADR 0016；装载结果类型化 2026-10-15）。
///
/// [R]：sheet 的返回值类型。提交成功后 [resultOnSubmit] 透传给返回的
/// Future（如项目表单的 `true` = 已保存，调用方据此刷新）；R 为 void
/// 时不传。
///
/// [D]：预装载结果类型。在调用点的显式类型实参里写出（如
/// `showLunioFormSheet<void, AppliedCarBoard>`），"这个表单装载什么"在
/// 入口行即编译期契约。
///
/// [load]：预装载（打开 sheet 前执行），返回装载结果交给 [guard] 与
/// [builder]。失败 → friendlyError toast、sheet 不出现。需要按装载结果
/// 改头部时（如车辆品牌车型副标题）在 load 内调
/// [FormSheetHandle.setSubtitle]。
///
/// [guard]：领域前置守卫（装载完成后、开 sheet 前执行），收装载结果。
/// 返回非空文案 → info toast 并中止（如"请先新增车辆"），sheet 不出现。
/// 可省略。
///
/// [builder]：表单内容。接收 sheet 自己的 context、[FormSheetHandle] 与
/// 装载结果；表单只画字段、校验与动作行，pop/toast/键盘 inset 都归本
/// 模块。builder 拿到的装载结果非空——若某个成员仍需 `!`（如数据束里
/// `car` 是 `Car?`），那是 guard 拦截后的业务不变量（守卫返回 null 即
/// 非空），不再是"装载变量可能没赋值"的信仰之跃。
///
/// [successMessage]：提交成功 toast 文案。null = 不提示（停车倒计时、
/// 草稿项目表单等产品约定无 toast 的入口）。
///
/// 没有预装载步骤的表单走 [showLunioFormSheetNoLoad]，不要在这里写空
/// 装载闭包。
///
/// barrierDismissible 固定 false：编辑表单有未保存输入，点遮罩/下滑/
/// 系统返回键都不可关，只能走取消/保存按钮（modal_feedback 里"编辑表单
/// 类"口径的结构化版本；2026-09-25 拍板把通知设置 sheet 的漂移一并
/// 归一）。
Future<R?> showLunioFormSheet<R, D>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Future<D> Function(FormSheetHandle<R> handle) load,
  String? Function(D loaded)? guard,
  required Widget Function(
    BuildContext sheetContext,
    FormSheetHandle<R> handle,
    D loaded,
  )
  builder,
  R? resultOnSubmit,
  String? successMessage,
}) async {
  final handle = FormSheetHandle<R>._(
    title,
    subtitle,
    resultOnSubmit,
    successMessage,
  );
  D loaded;
  try {
    loaded = await load(handle);
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, friendlyError(error), StatusOverlayTone.error);
    }
    return null;
  }
  if (!context.mounted) {
    return null;
  }
  final guardMessage = guard?.call(loaded);
  if (guardMessage != null) {
    if (context.mounted) {
      showStatusOverlay(context, guardMessage, StatusOverlayTone.info);
    }
    return null;
  }
  return showLunioModalSheet<R>(
    context: context,
    barrierDismissible: false,
    builder: (sheetContext) {
      return _FormSheetHost<R>(
        handle: handle,
        outerContext: context,
        // 装载结果在这里闭包收口：宿主与把手都不需要知道装载类型 D，
        // 类型参数只活在 showLunioFormSheet 的作用域里。
        builder: (hostSheetContext, hostHandle) =>
            builder(hostSheetContext, hostHandle, loaded),
      );
    },
  );
}

/// 无装载形态的编辑表单 sheet 入口（ADR 0016 修订 2026-10-15）：表单
/// 所需的值都是打开前同步可得的局部量、没有 await 装载步骤时走这里，
/// builder 只收 context 与把手、不收装载结果。它是 [showLunioFormSheet]
/// 的薄皮（D=void 空装载委托，[load] 恒为空操作），固定时序与全部反馈
/// 契约同一份。两种形态各管一种场景：有预装载的入口走
/// [showLunioFormSheet]、无预装载的入口走这里，不要混用（有装载的入口
/// 不要写空装载闭包，无装载的入口不要为此收 `void` 装载参数）。
Future<R?> showLunioFormSheetNoLoad<R>({
  required BuildContext context,
  required String title,
  String? subtitle,
  String? Function()? guard,
  required Widget Function(BuildContext sheetContext, FormSheetHandle<R> handle)
  builder,
  R? resultOnSubmit,
  String? successMessage,
}) {
  return showLunioFormSheet<R, void>(
    context: context,
    title: title,
    subtitle: subtitle,
    // 空装载委托：无 await 步骤的表单也走同一条时序（装载恒成功，
    // guard/builder 收到的装载值是 void 占位）。
    load: (handle) async {},
    // Dart 不允许少位置参数的函数直接赋给多参数函数类型，这里显式
    // 适配（guard 收到 void 装载值，原样转发文案）。
    guard: guard == null ? null : (_) => guard(),
    builder: (sheetContext, handle, _) => builder(sheetContext, handle),
    resultOnSubmit: resultOnSubmit,
    successMessage: successMessage,
  );
}

/// 表单 sheet 的调用方把手：表单经它读提交状态、回显错误、发起提交与
/// 关闭。ChangeNotifier——宿主监听它重建，saving/errorText/头部文案的
/// 变化自动反映到 frame 与表单（表单不再自己 setState 管这些）。
class FormSheetHandle<R> extends ChangeNotifier {
  /// 位置参数（title/subtitle/resultOnSubmit/successMessage）：私有构造
  /// 只有一个调用点（showLunioFormSheet），位置传参满足
  /// prefer_initializing_formals。
  FormSheetHandle._(
    this._title,
    this._subtitle,
    this._resultOnSubmit,
    this._successMessage,
  );

  _FormSheetHostState<R>? _host;

  String _title;
  String? _subtitle;
  bool _saving = false;

  /// 已经 pop 过一次（submit 成功或 close）。之后再来的 submit/close
  /// 一律忽略，杜绝"pop 后宿主尚在退场动画、二次 pop 把底下的页面也
  /// 关掉"的竞态。
  bool _finished = false;
  String? _errorText;
  final R? _resultOnSubmit;
  final String? _successMessage;

  /// 当前 frame 标题（[setFrame] 可改，加车向导两步换标题用）。
  String get title => _title;

  /// 当前 frame 副标题。
  String? get subtitle => _subtitle;

  /// 提交进行中（提交按钮禁用态；re-entrant 期间的重复 submit 被忽略）。
  bool get saving => _saving;

  /// 行内错误文案（null = 无错误）。
  String? get errorText => _errorText;

  /// 手动设置/清除行内错误（同步校验失败用，如"请填写…"）。
  void setFormError(String? text) {
    if (_errorText == text) {
      return;
    }
    _errorText = text;
    notifyListeners();
  }

  /// 只补/清副标题（装载完成后回填"品牌 车型"这类依赖装载结果的头部；
  /// title 不动）。
  void setSubtitle(String? text) {
    if (_subtitle == text) {
      return;
    }
    _subtitle = text;
    notifyListeners();
  }

  /// 整体换头部（加车向导两步换标题）。title 必传（两步标题成对换）；
  /// subtitle 传 null 表示清掉副标题。
  void setFrame({required String title, String? subtitle}) {
    if (_title == title && _subtitle == subtitle) {
      return;
    }
    _title = title;
    _subtitle = subtitle;
    notifyListeners();
  }

  /// 提交生命周期（表单保存按钮入口）：已在提交中/已关场则忽略 → 清错
  /// 并置提交中 → 执行 action → 失败 friendlyError 写 [errorText] 留场 /
  /// 成功 pop sheet（[resultOnSubmit] 透传给入口 Future）+ successMessage
  /// toast（可空）。
  Future<void> submit(Future<void> Function() action) async {
    if (_saving || _finished) {
      return;
    }
    _saving = true;
    _errorText = null;
    notifyListeners();
    var finished = false;
    try {
      await action();
      finished = true;
      _host?._finishSubmit();
    } catch (error) {
      _errorText = friendlyError(error);
      notifyListeners();
    } finally {
      if (!finished) {
        // 提交失败留场：复位 saving（成功路径 pop 后宿主随后销毁，
        // 不再通知）。
        _saving = false;
        notifyListeners();
      }
    }
  }

  /// 提交生命周期的不关场版（加车向导第一步"下一步"：成功 = 推进阶段
  /// 而非关 sheet）。失败同样 friendlyError 写 [errorText] 留场。
  Future<void> run(Future<void> Function() action) async {
    if (_saving || _finished) {
      return;
    }
    _saving = true;
    _errorText = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _errorText = friendlyError(error);
      notifyListeners();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// 非提交出口：pop sheet（返回值 null），可选带一条 toast。
  /// 取消按钮、删除、查重"去编辑"、去系统设置等所有不经提交生命周期的
  /// 关闭都走这里——"sheet 怎么关"全仓只有本模块一个答案。
  void close({String? toast, StatusOverlayTone tone = StatusOverlayTone.success}) {
    _host?._close(toast: toast, tone: tone);
  }

  void _attach(_FormSheetHostState<R> host) {
    _host = host;
  }

  void _detach() {
    _host = null;
  }
}

/// 表单宿主接缝（2026-09-26 修订）：表单 widget 实现本接口即声明"我
/// 持有把手"。已有的 `final FormSheetHandle handle` 字段天然满足 getter
/// 要求（`FormSheetHandle<void>`、`<bool>` 都是
/// `FormSheetHandle<dynamic>` 的子类型），不需要新增成员——接口只把
/// "这个表单的把手在哪"变成编译期可查的约定，builder 闭包注入把手的
/// 接线方式不变。
abstract interface class FormSheetHandleWidget implements StatefulWidget {
  /// 本表单绑定的把手（由 showLunioFormSheet 的 builder 闭包注入）。
  FormSheetHandle get handle;
}

/// 表单 State 的宿主 mixin：混入后直接以短名读把手的高频三件——
/// [saving]（提交中）、[errorText]（行内错误）、[setFormError]（同步
/// 校验错误回显），免写 `widget.handle.` 前缀。状态全部归
/// [FormSheetHandle]（ChangeNotifier），本 mixin 零状态、纯转发。
///
/// 与 2026-09-25 随 ADR 0016 落地删除的旧 LunioFormSubmit mixin 的
/// 本质区别：旧 mixin **拥有状态**（_saving/_errorText 存 State 里、
/// 自带 runSubmit 提交骨架）；本 mixin 只有三个一行转发，提交生命周期
/// 100% 归运行时。低频动作（submit/run/close/setFrame/setSubtitle）不
/// 进本 mixin，调用点保留显式 `widget.handle.` 直呼。
mixin FormSheetHandleHost<W extends FormSheetHandleWidget> on State<W> {
  /// 本表单绑定的把手（来自宿主 widget）。
  FormSheetHandle get handle => widget.handle;

  /// 提交进行中（转发 [FormSheetHandle.saving]）。
  bool get saving => handle.saving;

  /// 行内错误文案（转发 [FormSheetHandle.errorText]）。
  String? get errorText => handle.errorText;

  /// 手动设置/清除行内错误（转发 [FormSheetHandle.setFormError]）。
  void setFormError(String? text) => handle.setFormError(text);
}

/// sheet 宿主：挂在 modal 路由里，监听 handle 重建 frame 与表单内容，
/// 并为 handle 提供 pop/toast 的执行点（sheet 自己的 context 与外层
/// context 各在其位——键盘 inset 用 sheet 的，toast 用外层的）。
class _FormSheetHost<R> extends StatefulWidget {
  const _FormSheetHost({
    required this.handle,
    required this.outerContext,
    required this.builder,
  });

  final FormSheetHandle<R> handle;

  /// 入口函数的外层 context（toast 用；sheet 关闭后做 mounted 守卫）。
  final BuildContext outerContext;
  final Widget Function(BuildContext sheetContext, FormSheetHandle<R> handle)
  builder;

  @override
  State<_FormSheetHost<R>> createState() => _FormSheetHostState<R>();
}

class _FormSheetHostState<R> extends State<_FormSheetHost<R>> {
  late final FormSheetHandle<R> _handle = widget.handle.._attach(this);

  /// 提交成功收尾：pop sheet（resultOnSubmit 透传给入口 Future）+
  /// successMessage toast（可空）。pop 与 toast 的顺序沿用既有约定
  /// （先关场再提示）。
  void _finishSubmit() {
    if (!mounted || _handle._finished) {
      return;
    }
    _handle._finished = true;
    Navigator.of(context).pop(_handle._resultOnSubmit);
    final message = _handle._successMessage;
    if (message != null && widget.outerContext.mounted) {
      showStatusOverlay(widget.outerContext, message, StatusOverlayTone.success);
    }
  }

  /// 非提交出口：pop + 可选 toast。
  void _close({required String? toast, required StatusOverlayTone tone}) {
    if (!mounted || _handle._finished) {
      return;
    }
    _handle._finished = true;
    Navigator.of(context).pop();
    if (toast != null && widget.outerContext.mounted) {
      showStatusOverlay(widget.outerContext, toast, tone);
    }
  }

  @override
  void dispose() {
    _handle._detach();
    _handle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _handle,
      builder: (context, _) {
        return PrototypeSheetFrame(
          title: _handle.title,
          subtitle: _handle.subtitle,
          // 键盘高度必须用 sheet 自己的 context 读（外层 context 在 sheet
          // 构建时定格为 0）——这条契约收进本模块后，调用方不再裸写
          // MediaQuery.viewInsets（ADR 0016）。
          bottomInset: MediaQuery.of(context).viewInsets.bottom,
          child: widget.builder(context, _handle),
        );
      },
    );
  }
}
