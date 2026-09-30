---
version: "v1"
name: "Lunio Vehicle Care"
description: "A calm, utilitarian mobile design system for a local vehicle maintenance app across iOS and Android."
colors:
  background: "#f6f7f9"
  background-gradient-start: "#eef2ff"
  background-gradient-mid: "#f9faf7"
  background-gradient-end: "#f1f5f9"
  surface: "#ffffff"
  surface-2: "#f1f5f9"
  surface-3: "#e2e8f0"
  surface-overlay: "#e2e8f0"
  on-surface: "#111827"
  on-surface-soft: "#1f2937"
  on-surface-muted: "#64748b"
  on-surface-subtle: "#94a3b8"
  outline: "#e2e8f0"
  outline-strong: "#cbd5e1"
  primary: "#2563eb"
  primary-strong: "#1d4ed8"
  primary-container: "#dbeafe"
  on-primary: "#ffffff"
  on-primary-container: "#2563eb"
  primary-dark: "#0e7490"
  primary-dark-strong: "#155e75"
  primary-dark-container: "#0b2c38"
  secondary: "#475569"
  secondary-container: "#e2e8f0"
  on-secondary: "#ffffff"
  success: "#15803d"
  success-container: "#dcfce7"
  on-success-container: "#15803d"
  warning: "#b45309"
  warning-container: "#fef3c7"
  on-warning-container: "#b45309"
  danger: "#dc2626"
  danger-container: "#fee2e2"
  on-danger-container: "#dc2626"
  device-frame: "#101611"
  hero-gradient-start: "#2563eb"
  hero-gradient-mid: "#1d4ed8"
  hero-gradient-end: "#1e3a8a"
  toast-background: "#111827"
  toast-text: "#ffffff"
typography:
  # 刻度与 Flutter 实现（lunio_theme.dart textTheme + 各组件）一致。
  # 字重阶梯：400 正文 / 600 半粗（输入框 label、辅助强调）/ 700 粗
  # （标签、卡标题、按钮、图表金额）/ 800 特粗（页面标题、大数字）。
  # 不使用 w900；全 App 最小字号 10px。
  # fontFamily 统一为 "Inter, SF Pro Text, PingFang SC, Microsoft YaHei,
  # sans-serif" 回退链（见 lunio_theme.dart fontFamilyFallback），各档
  # 不重复声明。
  page-title:
    fontSize: 27px
    fontWeight: 800
    lineHeight: 1.12
    note: 页面标题（LunioTopBar，textTheme.headlineLarge）
  hero-metric:
    fontSize: 23px
    fontWeight: 800
    note: 车辆卡 hero 指标值（FittedBox 防溢出）
  card-title:
    fontSize: 20px
    fontWeight: 700
    lineHeight: 1.25
    note: 卡内大标题/大金额（textTheme.titleLarge）
  item-title:
    fontSize: 17px
    fontWeight: 700
    lineHeight: 1.2
    note: 列表项标题（textTheme.titleMedium）
  section-title:
    fontSize: 15px
    fontWeight: 700
    lineHeight: 1.2
    note: 卡片分组标题（LunioSection，textTheme.titleSmall）
  input-label:
    fontSize: 15px
    fontWeight: 600
    note: 输入框 label / 浮动 label
  body-md:
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.55
    note: 正文（textTheme.bodyMedium）
  body-sm:
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
    note: 辅助说明（textTheme.bodySmall）
  label-md:
    fontSize: 13px
    fontWeight: 700
    lineHeight: 1.35
    note: 强调标签/按钮/Toast 文字（textTheme.labelLarge、SnackBar）
  label-sm:
    fontSize: 12px
    fontWeight: 700
    lineHeight: 1.35
    note: 次级标签（textTheme.labelSmall）
  chart-amount:
    fontSize: 12px
    fontWeight: 700
    note: 图表柱顶金额（费用统计坐标系柱状图；金额槽高 ≥ 字号行高，FittedBox 不得回缩）
  chart-axis-label:
    fontSize: 11px
    fontWeight: 500
    note: 图表轴标签（高亮侧 700）
  chart-axis-tick:
    fontSize: 10.5px
    fontWeight: 400
    note: 图表纵轴刻度（subtle 色）
  micro-sub:
    fontSize: 10px
    fontWeight: 400
    note: 指标卡副字等最小档——全 App 字号下限
  nav-label:
    fontSize: 11px
    fontWeight: 700
    lineHeight: 1.2
    note: 底部导航标签
spacing:
  xxs: 2px
  xs: 4px
  sm: 6px
  md: 8px
  lg: 10px
  xl: 12px
  "2xl": 14px
  "3xl": 16px
  "4xl": 18px
  "5xl": 20px
  "6xl": 22px
  "7xl": 24px
  "8xl": 28px
  "9xl": 32px
  stage-gap: 36px
  page-horizontal: 18px
  page-bottom-nav-clearance: 112px
  phone-padding: 12px
  card-padding: 14px
  sheet-padding: 18px
  hero-padding: 22px
  nav-padding: 8px
  touch-target: 44px
rounded:
  xs: 3px
  sm: 10px
  md: 14px
  lg: 20px
  xl: 28px
  sheet: 30px
  screen: 36px
  phone: 46px
  full: 9999px
radii:
  xs: 3px
  sm: 10px
  md: 14px
  lg: 20px
  xl: 28px
  sheet: 30px
  screen: 36px
  phone: 46px
  full: 9999px
shadows:
  none: "0 0 0 rgba(0, 0, 0, 0)"
  soft: "0 10px 26px rgba(24, 32, 27, 0.08)"
  standard: "0 18px 48px rgba(24, 32, 27, 0.14)"
  floating: "0 16px 46px rgba(24, 32, 27, 0.16)"
  device: "0 34px 80px rgba(14, 19, 15, 0.24)"
  sheet: "0 -20px 54px rgba(24, 32, 27, 0.18)"
  primary-action: "0 18px 34px rgba(37, 99, 235, 0.28)"
elevation:
  level-0:
    shadow: "{shadows.none}"
    backgroundColor: "{colors.background}"
  level-1:
    shadow: "{shadows.soft}"
    backgroundColor: "{colors.surface}"
  level-2:
    shadow: "{shadows.standard}"
    backgroundColor: "{colors.surface}"
  level-3:
    shadow: "{shadows.floating}"
    backgroundColor: "{colors.surface}"
  level-modal:
    shadow: "{shadows.sheet}"
    backgroundColor: "{colors.surface}"
motion:
  duration-fast: 150ms
  duration-standard: 180ms
  duration-emphasis: 220ms
  easing-standard: "ease"
  easing-emphasis: "cubic-bezier(0.2, 0, 0, 1)"
  transform-sheet-enter: "translateY(0)"
  transform-sheet-exit: "translateY(105%)"
components:
  app-background:
    backgroundColor: "{colors.background}"
    textColor: "{colors.on-surface}"
  phone-frame:
    backgroundColor: "{colors.device-frame}"
    rounded: "{rounded.phone}"
    padding: "{spacing.phone-padding}"
  phone-screen:
    backgroundColor: "{colors.background}"
    rounded: "{rounded.screen}"
  hero-card:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.xl}"
    padding: "{spacing.hero-padding}"
  content-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.lg}"
    padding: "{spacing.card-padding}"
  bottom-navigation:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface-muted}"
    rounded: "{rounded.xl}"
    padding: "{spacing.nav-padding}"
  bottom-navigation-active:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.lg}"
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.label-md}"
    rounded: "{rounded.md}"
    height: 50px
    padding: 0 16px
  button-secondary:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.on-surface}"
    typography: "{typography.label-md}"
    rounded: "{rounded.md}"
    height: 50px
    padding: 0 16px
  button-icon:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.md}"
    width: 42px
    height: 42px
  floating-action-button:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.lg}"
    width: 58px
    height: 58px
  chip-filter:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    typography: "{typography.label-md}"
    rounded: "{rounded.sm}"
    height: 34px
    padding: 0 12px
  chip-filter-active:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.on-primary-container}"
    typography: "{typography.label-md}"
    rounded: "{rounded.sm}"
    height: 34px
    padding: 0 12px
  status-danger:
    backgroundColor: "{colors.danger-container}"
    textColor: "{colors.on-danger-container}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.sm}"
    height: 24px
    padding: 0 8px
  status-warning:
    backgroundColor: "{colors.warning-container}"
    textColor: "{colors.on-warning-container}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.sm}"
    height: 24px
    padding: 0 8px
  status-normal:
    backgroundColor: "{colors.success-container}"
    textColor: "{colors.on-success-container}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.sm}"
    height: 24px
    padding: 0 8px
  input-field:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.md}"
    height: 48px
    padding: 12px 13px
  bottom-sheet:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.sheet}"
    padding: "{spacing.sheet-padding}"
  toast:
    backgroundColor: "{colors.toast-background}"
    textColor: "{colors.toast-text}"
    typography: "{typography.label-md}"
    rounded: "{rounded.md}"
    padding: 12px 16px
---

## Overview

Lunio Vehicle Care is a calm, utilitarian mobile app design system for personal vehicle maintenance. It should feel like a reliable garage logbook translated into a modern phone interface: quiet, practical, readable, and composed under repeated daily use.

This document describes the formal v1 product UI. The current Flutter app has real reminder, record, vehicle, fuel, cost statistics, backup, notification, parking countdown, home widget, manual date, and theme flows; do not treat these screens as placeholder prototypes when making future design changes.

The product is not decorative or editorial. The interface is built around three recurring tasks: check maintenance urgency, record service work, and manage vehicles or backups. Every screen should make the current vehicle obvious, keep actions close to the relevant data, and avoid marketing-style hero sections or ornamental card stacks.

The emotional target is steady confidence. The system uses cool neutral surfaces, diffused shadows, compact information cards, and rounded-but-not-playful geometry. It should feel equally natural on iOS and Android, with no dependency on platform-specific glass, tab, or sheet styling.

## Colors

The palette is a restrained service-tool palette that separates brand color from maintenance status color. Brand color owns navigation, primary actions, and selected UI. Status color owns vehicle health and maintenance urgency.

- **Primary Blue (#2563eb):** The light-mode brand and interaction color. Use it for the active tab, primary buttons, floating action button, current vehicle highlights, and high-emphasis selected states.
- **Primary Deep Cyan (#0e7490):** The dark-mode brand and interaction color. It keeps the tool-like mechanical feel of the vehicle-care workflow while staying separate from green status semantics. Use it in the same places as primary blue when the app is in dark mode.
- **Status Green (#15803d):** Used only for normal vehicle health, positive maintenance status, normal progress ranges, and the fuel price falling arrow on the fuel page (red-rise/green-fall convention, see below). The light-mode value is the ADR 0019 contrast tier (dark mode keeps its brighter tier).
- **Neutral Canvas (#f6f7f9):** The app background. It should read as a cool off-white, not pure white, beige, or cream.
- **White Surface (#ffffff):** The main card and sheet surface. Use it for readable information containers and controls.
- **Secondary Slate (#475569):** A secondary accent used sparingly for system variety and visual balance, not for primary actions.
- **Warning Amber (#b45309):** Used only for due-soon maintenance states and cautionary progress ranges. The light-mode value is the ADR 0019 contrast tier (dark mode keeps its brighter tier).
- **Danger Red (#dc2626):** Used only for overdue states, destructive actions, critical warning badges, and the fuel price rising arrow on the fuel page. The light-mode value is the ADR 0019 contrast tier (dark mode keeps its brighter tier).

Fuel price trend arrow exception (red-rise/green-fall): the "预估下次油价" block uses Danger Red for a predicted rise and Status Green for a predicted fall, following the Chinese stock-market color convention users expect for prices. This is a price-direction semantic, not vehicle health — do not reuse red/green this way outside the fuel price block.

On-gradient status tints (hero "到期概览"): inside the hero vehicle card the due/overdue counts carry their status hue as pale tints — #fecaca for overdue, #fde68a for due — instead of the ADR 0019 tiers. The tier colors are tuned for text on white; on the primary gradient they drop below readable contrast. The tints are theme-stable light constants (declared next to the hero usage) because the gradient itself already flips with light/dark mode. Anything outside the hero gradient keeps using the normal semantic tiers.

Color usage should remain functional. Do not create multicolor decorative backgrounds. Green must not be used as a generic brand accent; reserve it for normal status so users can distinguish action from health.

## Typography

Typography uses a system-first sans-serif stack with Inter as the preferred font. Chinese UI text must fall back cleanly to PingFang SC or Microsoft YaHei. Letter spacing remains neutral; do not use tight negative tracking.

Headlines are strong and compact, usually 27px on mobile pages with weight 800. They should fit tool surfaces and not feel like landing-page hero type. Section titles and card titles use semibold to bold weights (the 400/600/700/800 ladder), while metadata uses 12px to 13px muted labels.

Numeric information such as mileage, percentage, cost, and dates should be visually firm. Use heavier weights for values, but keep them aligned with labels and supporting text. Avoid oversized dashboard numerals except inside compact hero metrics where immediate scanning matters.

## Layout

The layout is mobile-first and organized around a single phone-width content rail; the product UI is a focused mobile surface with no tablet or desktop layout.

Primary mobile pages use 18px horizontal padding and leave clear bottom space for the floating bottom navigation. Content is grouped in vertical sections with 16px to 20px rhythm. Cards use compact internal padding, typically 14px to 16px, so lists remain scannable without becoming dense or cramped.

Navigation is a floating bottom bar with three primary tabs — reminders, records, and profile/garage tools — plus a conditional fuel tab that appears only when the fuel prediction switch is enabled. The floating add action belongs near the bottom right and should remain available on the reminder and record flows, because adding a maintenance record is the dominant repeated task.

## Elevation & Depth

Depth is created through tonal layers and soft ambient shadows rather than heavy material elevation. Backgrounds are cool neutral gray, cards are white, and primary containers use the current brand color.

Standard cards use very soft shadows with low opacity. Elevated hero cards and sheets may use wider blur values, but no component should look glossy or heavily skeuomorphic. Bottom navigation is the most glass-like element: it may use a white translucent surface and blur, but it should still read as part of a practical tool, not as decorative glassmorphism.

Blocking sheets and dialogs use a light background blur with a subtle dimming overlay so the underlying page reads as the previous layer. The modal surface itself stays solid and readable; do not turn forms, lists, or confirmation dialogs into glass panels.

All centered dialogs share one card shell (`LunioDialogCard`): solid surface with the 20px card radius, a hairline border, a soft ambient shadow, a title row with an optional 20px semantic-tone icon, and a max height of 82% of screen height with internal scrolling so long content never overflows. Action rows (`LunioDialogActions`) pair a secondary text button with a 50px-tall filled primary (or a single full-width primary), tinted by the dialog's semantic color when one applies.

## Shapes

The shape language is rounded and tactile. Cards use 20px radii, hero panels use 28px, and bottom sheets use 30px top radii. Icon buttons and input fields use 14px radii. The design should feel soft enough for touch but still professional.

Use full pills only for circular progress rings, switch tracks, and small meter-like indicators. Do not turn every text label into a pill. Repeated rectangular chips should use a 10px radius and restrained padding.

## Components

### Hero Vehicle Card

The current vehicle card is the anchor of the reminder screen. It uses the current brand gradient, white text, and two compact metrics: current mileage and most urgent item. It must clearly identify the active vehicle and expose a switch action.

### Reminder Rows

The reminder list is layered (ADR 0018): items whose status is due or overdue are always expanded first under a "需要处理 · N" section, each rendered as a horizontal gauge row — rounded semantic-color fill bar with the percentage at its right, plus item title, status badge, and plain-language remaining distance or time. Normal items are folded into a single "一切正常 · N 项" row (tap to expand) whenever attention items exist; when nothing needs attention all items are laid flat under "全部项目". Rows keep supporting normal, warning, and overdue states without changing their structure, sorted high-urgency first; tapping a row opens the last-service detail sheet.

### Parking Countdown

Parking countdown is a temporary but high-priority reminder-screen utility. It sits between the current vehicle card and the maintenance reminder list. It uses the same normal, warning, and danger semantics as maintenance reminders: green for enough time remaining, amber when remaining time is at or below 20%, and red after timeout. The countdown entry uses an iOS-style wheel for entry time and an integer minute input for free duration, with shortcut chips only as accelerators.

### Records

Records are list-first, not chart-first. The record screen supports two display modes: by service cycle and by item. Use segmented controls for the mode switch, horizontal filter chips for year and item filters, and compact cards for rows. Costs sit on the right in the current brand color. Record cards lazily build as the user scrolls (sliver lists with stable per-record keys). Item name pills inside a card flow with a 6px gap via `Wrap`; they wrap naturally without forced row packing. While the backing data is loading, the whole page shows the shared centered loading placeholder, and load failures show the shared error card — all three main pages use the same loading/error treatment. A compact summary row sits at the top of the records header when records exist — "今年保养" and "今年加油" amounts, each shown only when its domain has records — and links to the cost statistics page.

### Cost Statistics

The cost statistics page is a pushed subpage (not a tab) reached from the records header row or the profile page. It is read-only aggregation rendered with self-drawn primitives — no chart library — and its scope is always the applied vehicle (the vehicle name shows as the title subtitle; there is no "all vehicles" scope). Charts use only existing tokens and never hard-coded hex colors:

- Summary cards: a totals card at the top of the page — 总费用 plus 今年保养, with a third 今年加油 block when the car has fuel records — followed by a slim four-block metrics card: visit count (with a "this year n" sub-line), average per visit, monthly average (total cost ÷ calendar months from the first record month to the current one, a fixed whole-history figure that follows nothing), and last service ("n days ago" / "today"). Numbers stay small; the chart cards carry the visual weight.
- Item share: one 100% stacked bar whose segments are sorted by paid amount descending and step from dark to light primary, followed by compact detail rows — each row is a color dot, item name, percentage, saved amount, and paid amount, with the three numeric columns in fixed-width slots, right-aligned. The card header is one line: label + total cost (the conservation anchor) + a small green "累计优惠 ¥x" on the right. A neutral "其他" segment (surface3, not tappable, shown only when non-zero) absorbs unattributable cost — summary-mode records and per-record excess of total cost over the item sum — so the bar and the rows always add up to the total cost (总费用 ≡ Σ项目实付 + 其他). Tapping an item row opens the per-item history sheet (summary blocks + reverse-chronological per-visit rows).
- Maintenance cost trend: shown from two records onward (a single-record car hides the whole card; a single-year car with 2+ records still shows its one column). One column per year (= that year's total cost), uniform primary color with no per-year highlight, capped with an amount label; the vertical axis carries three ticks (0 / half-peak / peak, step adaptive to round numbers) with dashed horizontal grid lines. The chart fills the card width when it fits and scrolls horizontally when it does not (bottom scrollbar shown while scrolling, initially parked at the rightmost year, snapping to whole columns). There is no window switcher and no average line. The chart canvas must be given an explicit width (`double.infinity`): inside the section's start-aligned column a childless CustomPaint collapses to zero width and renders nothing.
- Fuel cost card: the last card on the page, shown only when the car has fuel records. Header is one line — total fuel cost + monthly average (same whole-history dilution rule as maintenance) — over a full-history continuous monthly column chart in the same axes style (axis fixed on the left, dashed grid lines, amount labels on top, "26.9"-style axis labels). No year dimension.
- Entrance animation: one shared one-shot 700ms controller — share-bar segments grow by width, chart columns grow by height. Any bar driven by the entrance progress must live inside an `AnimatedBuilder` listening to that controller; a subtree without it never rebuilds during the animation and bars stay invisible at progress 0. No looping or idle animations.

Safe-area handling lives in `LunioPage` itself, so every pushed subpage is correct by construction; exact amounts always accompany charts.

### Bottom Navigation

Bottom navigation is a floating rounded container with three equal destinations. The active destination uses a filled primary segment with white icon and label. Inactive destinations remain muted, not outlined.

### Bottom Sheets

Forms, filters, vehicle switching, project management, and restore confirmation use bottom sheets. Every sheet is built on a single shared skeleton (`PrototypeSheetFrame`): drag handle, strong title, concise supporting text, scrollable content, 30px top radius, and one surface token. Information sheets and form sheets must not introduce alternate surface containers or radii. Open sheets blur and dim the page behind them; closed sheets must not remain reachable to assistive technologies.

Sheet dismissal rules (shared, implemented in the shared sheet runtime, not per-sheet): dragging the sheet body down moves the whole sheet with the finger — releasing past one quarter of the sheet height (or with enough downward speed) closes it, otherwise it springs back; when the content is scrollable the drag only grabs the sheet once the content is scrolled to the top. Tapping empty space inside the sheet only dismisses the keyboard, and the drag rules apply uniformly to every bottom sheet. Tapping the dimmed area outside closes information sheets immediately with no unsaved-changes confirmation; edit-form sheets (built on `showLunioFormSheet`, ADR 0016) are not barrier-dismissible — they close only through their own actions, where a successful submit pops with a success toast and any other exit closes silently.

### Forms

Inputs use light neutral surfaces, 14px radii, and readable 13px labels. Form sheets close with a shared action row (`LunioFormActions`): a secondary "取消"-style button beside one primary confirm button that greys out and swaps to a saving label while submitting. Do not hand-roll per-sheet button rows with different heights or labels for the same state. Date fields always express business dates in `yyyy-MM-dd` semantics, even if the visual control renders with local separators. Date picking uses a compact sheet with day, month, and year layers so users can select nearby days directly, jump to a month in the current year, or move across years without long scrolling. Numeric fields should be plain and practical.

### Toasts

Toasts are dark neutral surfaces with white or high-contrast text and rounded corners. They communicate lightweight success states such as saved record, vehicle switched, backup exported, or restore complete. Do not use alert dialogs for routine successful operations.

## Do's and Don'ts

- Do make the current vehicle visible before showing reminders or records.
- Do use the current brand color for the most important action or selected state on each screen.
- Do keep cards compact, with enough whitespace for scanning but no oversized marketing composition.
- Do use warning amber only for due states and danger red only for overdue or destructive states.
- Do preserve cross-platform neutrality; avoid controls that only make sense on one mobile OS.
- Do keep typography neutral with zero letter spacing and system-friendly fallbacks.
- Do maintain bottom sheets, chips, cards, and buttons as a unified component family.
- Don't use decorative gradient orbs, bokeh, large landing-page heroes, or visual filler.
- Don't make the UI monochrome; blue or deep cyan is brand, while green, amber, and red are semantic status colors.
- Don't use project names or displayed maintenance item names as stable identifiers in product flows.
- Don't overcrowd the bottom navigation or add more than the three primary tabs without revisiting the information architecture.
- Don't use heavy dark shadows, glossy glass surfaces, or platform-specific visual tricks that would make iOS and Android diverge.
- Don't describe iOS Live Activity, Dynamic Island, or widget surfaces as current product UI unless those targets are actually present in the repository.
