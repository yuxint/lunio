// shell 内部共享层的 barrel 文件（统一出口）。
//
// barrel ≈ Java 里"只做 re-export 的聚合模块"：页面只需要
// `import '../shared/shell_shared.dart'` 一行，就能用到下面 5 个文件里
// 的全部公开符号。新增共享文件时在这里补一行 export。
export 'date_picker.dart';
export 'form_submit.dart';
export 'formatters.dart';
export 'modal_feedback.dart';
export 'shared_widgets.dart';
export 'shell_actions.dart';
