---
version: "alpha"
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
  primary-dark: "#8b5cf6"
  primary-dark-strong: "#7c3aed"
  primary-dark-container: "#2e214f"
  secondary: "#475569"
  secondary-container: "#e2e8f0"
  on-secondary: "#ffffff"
  success: "#22c55e"
  success-container: "#dcfce7"
  on-success-container: "#22c55e"
  warning: "#f59e0b"
  warning-container: "#fef3c7"
  on-warning-container: "#f59e0b"
  danger: "#ef4444"
  danger-container: "#fee2e2"
  on-danger-container: "#ef4444"
  device-frame: "#101611"
  hero-gradient-start: "#2563eb"
  hero-gradient-mid: "#1d4ed8"
  hero-gradient-end: "#1e3a8a"
  toast-background: "#111827"
  toast-text: "#ffffff"
typography:
  display-lg:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 34px
    fontWeight: 780
    lineHeight: 1.08
    letterSpacing: 0em
  page-title:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 28px
    fontWeight: 780
    lineHeight: 1.12
    letterSpacing: 0em
  sheet-title:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 21px
    fontWeight: 780
    lineHeight: 1.2
    letterSpacing: 0em
  card-title-lg:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 20px
    fontWeight: 760
    lineHeight: 1.25
    letterSpacing: 0em
  section-title:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 17px
    fontWeight: 760
    lineHeight: 1.2
    letterSpacing: 0em
  record-title:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 16px
    fontWeight: 780
    lineHeight: 1.2
    letterSpacing: 0em
  body-md:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.7
    letterSpacing: 0em
  body-sm:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: 0em
  label-md:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 13px
    fontWeight: 720
    lineHeight: 1.35
    letterSpacing: 0em
  label-sm:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 12px
    fontWeight: 720
    lineHeight: 1.35
    letterSpacing: 0em
  nav-label:
    fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: 11px
    fontWeight: 720
    lineHeight: 1.2
    letterSpacing: 0em
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

The product is not decorative or editorial. The interface is built around three recurring tasks: check maintenance urgency, record service work, and manage vehicles or backups. Every screen should make the current vehicle obvious, keep actions close to the relevant data, and avoid marketing-style hero sections or ornamental card stacks.

The emotional target is steady confidence. The system uses cool neutral surfaces, diffused shadows, compact information cards, and rounded-but-not-playful geometry. It should feel equally natural on iOS and Android, with no dependency on platform-specific glass, tab, or sheet styling.

## Colors

The palette is a restrained service-tool palette that separates brand color from maintenance status color. Brand color owns navigation, primary actions, and selected UI. Status color owns vehicle health and maintenance urgency.

- **Primary Blue (#2563eb):** The light-mode brand and interaction color. Use it for the active tab, primary buttons, floating action button, current vehicle highlights, and high-emphasis selected states.
- **Primary Purple (#8b5cf6):** The dark-mode brand and interaction color. Use it in the same places as primary blue when the app is in dark mode.
- **Status Green (#22c55e):** Used only for normal vehicle health, positive maintenance status, and normal progress ranges.
- **Neutral Canvas (#f6f7f9):** The app background. It should read as a cool off-white, not pure white, beige, or cream.
- **White Surface (#ffffff):** The main card and sheet surface. Use it for readable information containers and controls.
- **Secondary Slate (#475569):** A secondary accent used sparingly for system variety and visual balance, not for primary actions.
- **Warning Amber (#f59e0b):** Used only for due-soon maintenance states and cautionary progress ranges.
- **Danger Red (#ef4444):** Used only for overdue states, destructive actions, and critical warning badges.

Color usage should remain functional. Do not create multicolor decorative backgrounds. Green must not be used as a generic brand accent; reserve it for normal status so users can distinguish action from health.

## Typography

Typography uses a system-first sans-serif stack with Inter as the preferred web font. Chinese UI text must fall back cleanly to PingFang SC or Microsoft YaHei. Letter spacing remains neutral; do not use tight negative tracking.

Headlines are strong and compact, usually 28px on mobile pages with weight around 780. They should fit tool surfaces and not feel like landing-page hero type. Section titles and card titles use semibold to bold weights, while metadata uses 12px to 13px muted labels.

Numeric information such as mileage, percentage, cost, and dates should be visually firm. Use heavier weights for values, but keep them aligned with labels and supporting text. Avoid oversized dashboard numerals except inside compact hero metrics where immediate scanning matters.

## Layout

The layout is mobile-first and organized around a single phone-width content rail. On wide screens, the prototype may show a device frame beside a design notes panel, but the product UI itself should remain a focused mobile surface.

Primary mobile pages use 18px horizontal padding and leave clear bottom space for the floating bottom navigation. Content is grouped in vertical sections with 16px to 20px rhythm. Cards use compact internal padding, typically 14px to 16px, so lists remain scannable without becoming dense or cramped.

Navigation is fixed to three tabs: reminders, records, and profile/garage tools. The floating add action belongs near the bottom right and should remain available on the reminder and record flows, because adding a maintenance record is the dominant repeated task.

## Elevation & Depth

Depth is created through tonal layers and soft ambient shadows rather than heavy material elevation. Backgrounds are cool neutral gray, cards are white, and primary containers use the current brand color.

Standard cards use very soft shadows with low opacity. Elevated hero cards and sheets may use wider blur values, but no component should look glossy or heavily skeuomorphic. Bottom navigation is the most glass-like element: it may use a white translucent surface and blur, but it should still read as part of a practical tool, not as decorative glassmorphism.

Sheets rise from the bottom and dim the content beneath them. The dimming overlay should be functional and subtle, enough to focus attention without making the screen feel modal-heavy.

## Shapes

The shape language is rounded and tactile. Cards use 20px radii, hero panels use 28px, and bottom sheets use 30px top radii. Icon buttons and input fields use 14px radii. The design should feel soft enough for touch but still professional.

Use full pills only for circular progress rings, switch tracks, and small meter-like indicators. Do not turn every text label into a pill. Repeated rectangular chips should use a 10px radius and restrained padding.

## Components

### Hero Vehicle Card

The current vehicle card is the anchor of the reminder screen. It uses the current brand gradient, white text, and two compact metrics: current mileage and most urgent item. It must clearly identify the active vehicle and expose a switch action.

### Reminder Rows

Reminder rows combine a circular progress indicator, item title, status badge, and plain-language remaining distance or time. The row should support normal, warning, and overdue states without changing its structure. Sort high-urgency rows first.

### Records

Records are list-first, not chart-first. The record screen supports two display modes: by service cycle and by item. Use segmented controls for the mode switch, horizontal filter chips for year and item filters, and compact cards for rows. Costs sit on the right in the current brand color.

### Bottom Navigation

Bottom navigation is a floating rounded container with three equal destinations. The active destination uses a filled primary segment with white icon and label. Inactive destinations remain muted, not outlined.

### Bottom Sheets

Forms, filters, vehicle switching, project management, and restore confirmation use bottom sheets. Sheets should include a small drag handle, strong title, concise supporting text, and two action buttons where appropriate. Closed sheets must not remain reachable to assistive technologies.

### Forms

Inputs use light neutral surfaces, 14px radii, and readable 13px labels. Date fields always express business dates in `yyyy-MM-dd` semantics, even if the visual control renders with local separators. Numeric fields should be plain and practical.

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
- Don't make the UI monochrome; blue or purple is brand, while green, amber, and red are semantic status colors.
- Don't use project names or displayed maintenance item names as stable identifiers in product flows.
- Don't overcrowd the bottom navigation or add more than the three primary tabs without revisiting the information architecture.
- Don't use heavy dark shadows, glossy glass surfaces, or platform-specific visual tricks that would make iOS and Android diverge.
