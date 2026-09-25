# ADR 0016：编辑表单 sheet 的生命周期收进表单运行时 showLunioFormSheet

日期：2026-09-25
状态：已接受

## 背景

每个编辑表单类底部 sheet（记录/加油记录/手填油价/手动日期/通知设置/
保养项目两版/加车向导/编辑车辆/快捷里程/停车倒计时，共 11 处入口）各自
手写同一条 ~40 行生命周期：await 装载 provider → mounted 守卫 →
`showLunioModalSheet(barrierDismissible: false)` → `PrototypeSheetFrame` +
键盘 inset → 提交闭包里"动作层写库 → pop(sheetContext) → toast(外层
context)"。这条隐式接口的坑已多次显形：

- 键盘高度必须用 sheet 自己的 context 读（外层 context 在 sheet 构建时
  定格为 0，曾致底部输入被遮挡，2026-09-12 修复），这条约束的警告注释在
  4 个文件里逐字重复，`MediaQuery.of(sheetContext).viewInsets.bottom`
  裸写 11 处；
- `Navigator.of(sheetContext).pop()` 裸写 13 处（含取消按钮、删除、
  查重"去编辑"、去系统设置等非提交出口），pop/toast 双 context 写法是
  每个入口都要重新学会的局部知识；
- 表单 State 的 saving/errorText 生命周期由 `LunioFormSubmit` mixin
  提供，但 mixin 与入口闭包各管一半，通知设置 sheet 干脆手搓 saving 且
  `barrierDismissible` 漂移成 true（全仓表单 sheet 里唯一可点遮罩关闭的
  编辑表单，属漂移非设计）。

## 决定

1. **新增 `shared/form_sheet.dart`（ADR 0016）**：`showLunioFormSheet<R>`
   拥有固定时序——①`load` 预装载（失败 friendlyError toast，sheet 不
   出现；装载结果经入口函数局部闭包捕获变量在 load/guard/builder 间
   共享；需按装载结果改头部时经 `handle.setSubtitle`）；②`guard` 领域
   前置守卫（返回非空文案 → info toast 中止，如"请先新增车辆"）；
   ③`showLunioModalSheet(barrierDismissible: false)` 包
   `PrototypeSheetFrame`，键盘 inset 由运行时经 sheet 自己的 context
   读取；④提交 = `handle.submit`：re-entrant 守卫 → saving → 动作 →
   失败 friendlyError 写 `errorText` 留场 / 成功 pop（`resultOnSubmit`
   透传给入口 Future）+ `successMessage` toast（可空——停车倒计时、
   草稿项目表单保持产品约定的无 toast）；⑤所有 pop 都经运行时：
   `handle.close({toast, tone})` 承接取消按钮、删除、查重"去编辑"、
   去系统设置等非提交出口；pop 过一次后再来的 submit/close 一律忽略。
2. **`FormSheetHandle` 是 ChangeNotifier**：宿主监听它重建 frame 与表单，
   表单 State 经它读 `saving`/`errorText`、发 `submit`/`close`/
   `setFrame`（加车向导两步换标题）/`setSubtitle`（装载后补品牌车型
   副标题）。`LunioFormSubmit` mixin 吸干删除，`form_submit.dart` 移除。
3. **错误行渲染留在表单侧**：运行时只写 `errorText`，`LunioInlineMessage`
   的位置各表单自理（现网 8 处渲染已逐字节相同，仅数据源换成把手）。
4. **两个 submit 语义**：`submit` = 成功关场；`run` = 成功不关场
   （加车向导第一步"下一步"推进阶段用）。确认框（未调高里程、删除
   确认、同日查重）一律发生在 submit 生命周期之前，不引入"静默取消"
   语义。删除路径失败走 `handle.run` 的行内错误位（原先未捕获异常，
   属顺手加固）。
5. **通知设置 sheet 归一为不可关**（barrierDismissible=false）——判定
   原行为是漂移而非设计，如需推翻应重开本 ADR。
6. **加车/编辑车辆 sheet 的装载从"sheet 先开、frame 内 watch"归一为
   预装载**（目录/日期是缓存 provider，等待很短）；frame 内装载分支
   （`CarFormLoad` 密封类 + `carFormLoadGuard`）随之删除，目录为空的
   "暂无可选车型"从行内提示改为守卫 toast。**范围边界**：选择器/只读/
   宿主 sheet（省份/油品/日期/滚轮/详情/项目列表/切换车辆/恢复默认）
   不在运行时范围，继续直接用 `showLunioModalSheet`。

## 后果

- 新增编辑表单只有一个正确写法：`showLunioFormSheet` 声明装载/守卫/
  标题/表单/成功文案五件事；键盘 context 坑、双 context pop/toast、
  barrier 口径从"每个入口重新学会"变成"运行时一处实现"。
- 11 处入口净删 ~300 行脚手架；4 处重复坑注释、13 处裸 pop、11 处裸
  MediaQuery 随之消失。
- 加车/编辑车辆 sheet 打开时机从"立即"变为"预装载完成后"（provider
  有缓存，实际等待很短）；目录装载失败从行内提示改为 toast + 不开壳。
- 测试面：新增模块级专测 `test/widget/form_sheet_test.dart`（装载失败/
  守卫拦截/提交成败/关场去重/结果透传/头部切换，10 例）；既有行为级
  widget 测试零改动全绿。
- 动作层（ADR 0007）不变：写库+失效仍在动作函数；变化的只是 UI 侧
  反馈薄壳从"每个入口手写"归入运行时。
