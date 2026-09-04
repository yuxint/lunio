// 表单提交运行器（LunioFormSubmit mixin）：表单 State 混入后获得统一的
// "提交中 / 行内错误"生命周期。
//
// ≈ Java Web 里抽出来的表单基类：过去 9 个表单 State 各自手写
// "清错 → saving=true → try 提交 → catch 行内错误回显 → finally
// saving=false"骨架（细节各处有微差：漏 mounted 检查、saving 忘复位），
// 现在骨架只有这一份，各表单只保留字段与校验规则。
//
// 用法：
//  - State 声明 `with LunioFormSubmit`，build 里照旧读 `saving` /
//    `errorText`（LunioFormActions(saving: saving) 与
//    LunioInlineMessage(message: errorText) 不用改）；
//  - 同步校验失败用 [setFormError] 回显"请填写…"类提示；
//  - 异步提交用 [runSubmit]：成功 = 正常返回（成功反馈/pop 留在调用方
//    闭包里），失败 = friendlyError 翻译后写入 errorText。
// ⚠ 闭包里 pop 掉 sheet 后 State 已销毁，mixin 内部全部经 mounted 守卫，
// 不会在 dispose 后 setState。
import 'package:flutter/widgets.dart';

import 'formatters.dart';

mixin LunioFormSubmit<T extends StatefulWidget> on State<T> {
  bool _saving = false;

  /// 提交进行中（提交按钮禁用态）。
  bool get saving => _saving;

  String? _errorText;

  /// 行内错误文案（null = 无错误）。
  String? get errorText => _errorText;

  /// 手动设置/清除行内错误（同步校验失败用）。
  void setFormError(String? text) {
    if (!mounted) {
      return;
    }
    setState(() => _errorText = text);
  }

  /// 统一提交骨架：已在提交中则忽略重复点击 → 清错并置提交中 → 执行
  /// action → 失败时错误翻译成行内文案。成功后的反馈（pop/toast）写在
  /// action 闭包内，本方法不代劳。
  Future<void> runSubmit(Future<void> Function() action) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
