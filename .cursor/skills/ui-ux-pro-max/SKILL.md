---
name: ui-ux-pro-max
description: Provides design intelligence for building professional UI/UX across web and mobile. Use when the user requests to design, build, create, implement, review, fix, or improve UI/UX, landing pages, dashboards, or interfaces. Includes 67 styles, 96 color palettes, 57 font pairings, 99 UX guidelines, design system generation, and stack-specific best practices.
---

# UI UX Pro Max

Design intelligence for professional UI/UX: styles, palettes, typography, UX guidelines, and design system generation across 13 stacks.

## When to Use

Apply this skill when the user asks to:
- Design or build UI/UX, landing pages, dashboards, or interfaces
- Create, implement, review, fix, or improve screens or components
- Choose styles, colors, typography, or layout patterns

## Workflow

### Step 1: Analyze Requirements

From the user request, extract:
- **Product type**: SaaS, e-commerce, portfolio, dashboard, landing page, app
- **Style keywords**: minimal, playful, professional, elegant, dark mode, etc.
- **Industry**: healthcare, fintech, gaming, beauty, education
- **Stack**: React, Flutter, Next.js, or default `html-tailwind`

### Step 2: Design System (required)

If the project has the UI UX Pro Max script installed (e.g. after `uipro init --ai cursor`), run:

```bash
python3 .cursor/skills/ui-ux-pro-max/scripts/search.py "<product_type> <industry> <keywords>" --design-system [-p "Project Name"]
```

This returns: pattern, style, colors, typography, effects, anti-patterns. Use that output to drive implementation.

**If the script is not installed:** Infer a design system from the same factors (product type, industry, style keywords). Apply the Common Rules and Pre-Delivery Checklist below.

**Optional — persist for later:** Add `--persist` to write `design-system/MASTER.md`. For a page override: `--page "dashboard"` to create `design-system/pages/dashboard.md`. When building a page, prefer `design-system/pages/<page>.md` if it exists, else `design-system/MASTER.md`.

### Step 3: Supplement (as needed)

```bash
python3 .cursor/skills/ui-ux-pro-max/scripts/search.py "<keyword>" --domain <domain> [-n <max_results>]
```

| Need | Domain | Example |
|------|--------|---------|
| More style options | `style` | `--domain style "glassmorphism dark"` |
| Chart types | `chart` | `--domain chart "real-time dashboard"` |
| UX / a11y | `ux` | `--domain ux "animation accessibility"` |
| Typography | `typography` | `--domain typography "elegant luxury"` |
| Landing structure | `landing` | `--domain landing "hero social-proof"` |

Domains and stacks: see [reference.md](reference.md).

### Step 4: Stack (default html-tailwind)

If the user did not specify a stack, use **html-tailwind**. Otherwise:

```bash
python3 .cursor/skills/ui-ux-pro-max/scripts/search.py "<keyword>" --stack <stack>
```

Stacks: `html-tailwind`, `react`, `nextjs`, `vue`, `svelte`, `swiftui`, `react-native`, `flutter`, `shadcn`, `jetpack-compose`.

### Step 5: Implement

Synthesize design system + any domain/stack results and implement. Before delivery, run through the Pre-Delivery Checklist below.

---

## Common Rules for Professional UI

### Icons & Visual

| Rule | Do | Don't |
|------|----|-------|
| No emoji icons | SVG (Heroicons, Lucide, Simple Icons) | Emojis as UI icons |
| Stable hover | Color/opacity transitions | Scale transforms that shift layout |
| Brand logos | Official SVG from Simple Icons | Guess or wrong paths |
| Icon size | Fixed viewBox (e.g. 24×24), consistent class | Mixed random sizes |

### Interaction

| Rule | Do | Don't |
|------|----|-------|
| Cursor | `cursor-pointer` on all clickable/hoverable elements | Default cursor on interactive |
| Hover feedback | Clear change (color, shadow, border) | No feedback |
| Transitions | e.g. `transition-colors duration-200` (150–300ms) | Instant or >500ms |

### Contrast (light/dark)

| Rule | Do | Don't |
|------|----|-------|
| Glass in light | `bg-white/80` or higher opacity | `bg-white/10` |
| Body text light | e.g. `#0F172A` (slate-900) | slate-400 for body |
| Muted text light | `#475569` (slate-600) min | gray-400 or lighter |
| Borders light | `border-gray-200` | `border-white/10` |

### Layout

| Rule | Do | Don't |
|------|----|-------|
| Floating nav | Spacing from edges (e.g. `top-4 left-4 right-4`) | `top-0 left-0 right-0` |
| Content | Account for fixed nav height | Content under fixed elements |
| Containers | Same max-width (e.g. `max-w-6xl`) | Mixed widths |

---

## Pre-Delivery Checklist

Before delivering UI code:

**Visual**
- [ ] No emojis as icons (use SVG)
- [ ] Icons from one set (Heroicons/Lucide)
- [ ] Brand logos correct (Simple Icons)
- [ ] Hover states don’t cause layout shift
- [ ] Theme colors used directly (e.g. `bg-primary`), not unnecessary `var()` wrappers

**Interaction**
- [ ] All clickable elements have `cursor-pointer`
- [ ] Hover gives clear feedback
- [ ] Transitions 150–300ms
- [ ] Focus states visible for keyboard

**Light/Dark**
- [ ] Light mode text contrast ≥ 4.5:1
- [ ] Glass/transparent elements visible in light mode
- [ ] Borders visible in both modes

**Layout**
- [ ] Floating elements spaced from edges
- [ ] No content hidden behind fixed nav
- [ ] Responsive at 375px, 768px, 1024px, 1440px
- [ ] No horizontal scroll on mobile

**Accessibility**
- [ ] Images have alt text
- [ ] Form inputs have labels
- [ ] Color not the only indicator
- [ ] `prefers-reduced-motion` respected

---

## Installation (optional)

For full design-system generation and search (Python script + data):

```bash
npm install -g uipro-cli
cd /path/to/your/project
uipro init --ai cursor
```

Requires Python 3. If missing: macOS `brew install python3`; Ubuntu/Debian `sudo apt install python3`; Windows `winget install Python.Python.3.12`.

Without installation, the agent still applies the rules and checklist above and infers design systems from context.
