// 表单 sheet 运行时（showLunioFormSheet + FormSheetHandle）：编辑表单类
// 底部弹层的完整生命周期运行时，ADR 0016。
//
// ≈ Java Web 里抽出来的"弹窗表单基类 + 弹窗生命周期管理器"：过去 11 个
// 表单 sheet 入口各自手写同一条 ~40 行生命周期（await 装载 → mounted
// 守卫 → showLunioModalSheet → PrototypeSheetFrame → 键盘 inset →
// 提交闭包里 pop + toast），键盘 context 的坑注释在 4 个文件里逐字
// 重复。现在时序只有这一份，各入口只声明"取数、守卫、画表单、提交、
// 成功文案"五件事。
//
// 固定时序（2026-09-25 拷问定稿）：
//   1. [load] 预装载（打开 sheet 前执行；失败 → friendlyError toast，
//      sheet 不出现）。装载结果靠入口函数的局部闭包捕获变量在
//      load/guard/builder 之间共享；需要按装载结果改头部（如车辆品牌
//      车型副标题）时经 handle.setFrame 更新；
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

/// 编辑表单 sheet 的统一入口（ADR 0016）。
///
/// [R]：sheet 的返回值类型。提交成功后 [resultOnSubmit] 透传给返回的
/// Future（如项目表单的 `true` = 已保存，调用方据此刷新）；R 为 void
/// 时不传。
///
/// [load]：预装载（打开 sheet 前执行）。失败 → friendlyError toast、
/// sheet 不出现。装载 Provider 的结果写入入口函数声明的局部变量即可在
/// guard/builder 闭包间共享；需要按装载结果改头部时（如车辆品牌车型
/// 副标题）调 [FormSheetHandle.setFrame]。
///
/// [guard]：领域前置守卫（装载完成后、开 sheet 前执行）。返回非空文案
/// → info toast 并中止（如"请先新增车辆"），sheet 不出现。
///
/// [builder]：表单内容。接收 sheet 自己的 context 与 [FormSheetHandle]；
/// 表单只画字段、校验与动作行，pop/toast/键盘 inset 都归本模块。
///
/// [successMessage]：提交成功 toast 文案。null = 不提示（停车倒计时、
/// 草稿项目表单等产品约定无 toast 的入口）。
///
/// barrierDismissible 固定 false：编辑表单有未保存输入，点遮罩/下滑/
/// 系统返回键都不可关，只能走取消/保存按钮（modal_feedback 里"编辑表单
/// 类"口径的结构化版本；2026-09-25 拍板把通知设置 sheet 的漂移一并
/// 归一）。
Future<R?> showLunioFormSheet<R>({
  required BuildContext context,
  required String title,
  String? subtitle,
  Future<void> Function(FormSheetHandle<R> handle)? load,
  String? Function()? guard,
  required Widget Function(BuildContext sheetContext, FormSheetHandle<R> handle)
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
  if (load != null) {
    try {
      await load(handle);
    } catch (error) {
      if (context.mounted) {
        showStatusOverlay(context, friendlyError(error), StatusOverlayTone.error);
      }
      return null;
    }
  }
  if (!context.mounted) {
    return null;
  }
  final guardMessage = guard?.call();
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
        builder: builder,
      );
    },
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
