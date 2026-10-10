# VCE Maths toolkit (Methods + Specialist, tech active)

A TI-Nspire CX II CAS Lua program for the technology-active Exam 2 of VCE **Mathematical Methods** (MM) and **Specialist Mathematics** (SM). You type in what the question gives and it fills in everything that can be worked out: exact values first, each answer with brief working laid out the way VCE marking schemes expect, and graphs where they help.

The toolkit ships three ways:

- `vce.tns`: the English version, a standalone document. Open it and the toolkit starts. It is English only: it contains no Chinese text and has no language setting (it is also the smaller file).
- `vce_zh.tns`: the version with Chinese (中英双语). The interface, field labels and hints, notes, menus, help and the name of every result (for example *variance 方差*, *Type II error 第二类错误*) appear in Chinese and English. The working steps stay in English, the language of the VCE exam. **Settings › Language** switches this document between Chinese + English and English only; the choice is saved with the document.
- `rpn.tns`: rpnspire with the toolkit built in, in English like `vce.tns`. Press <kbd>.</kbd> <kbd>a</kbd> and choose **VCE Maths toolkit**. With **Send to RPN stack** in the context menu you can push a result onto the rpnspire stack.

> Status: the solvers are tested on a desktop against a numeric CAS mock (`testcas.lua`), and the bundled document is smoke-tested in a TI-like Lua 5.1 sandbox. The real TI CAS (exact output, syntax) still has to be checked on a handheld or in the TI-Nspire CX CAS software. Run **Help › Self-test** once on your calculator: it solves 64 known problems and reports any that fail.

## Getting started: 3 steps

1. **Pick a topic** on the home screen. Press its number (1–9, or 0 for the tenth) or move to it and press enter.
2. **Type what the question gives** into the boxes. Leave the unknowns empty.
3. **Read the answers.** They appear at once in the green **Answers** area. The working is underneath.

Not sure what to type? An empty problem has a **Try an example** button that fills in a sample question so you can see how the boxes are used.

## Built for easy reading

The layout assumes that any student may have dyslexia or ADHD:

- **Few choices per screen.** The home screen has ten topics with one short line each. All of Probability is a single topic; you choose the kind of question from a numbered list.
- **One thing at a time.** In Probability, step 1 is to choose the kind of question; only its boxes are then shown. In *Find unknown constants*, the number of condition boxes matches the number of unknowns.
- **Always clear where you are.** The selected row has a blue bar on its left. Input boxes are outlined so you can see where to type, and the hint line at the bottom names the next key to press.
- **Answers stand out.** Answers sit on a green background, directly under the inputs; the working follows below them. After **Try an example**, the screen jumps to the answers.
- **Calm colours.** A soft cream page with dark grey text, and notes in tinted boxes with an icon: **i** for information, **!** for a warning, **×** for an error. **Settings › Colours** switches to plain white.
- **Short words.** Field hints show a typical input such as `kx+2y=3`, and sentence answers such as transformations wrap onto several lines instead of running off the screen.

## Course marks: MM and SM

Each topic carries a badge, also shown in the title bar of an open problem:

- **MM** (teal): Mathematical Methods Units 3 & 4.
- **SM** (purple): Specialist Mathematics Units 3 & 4.
- **MM SM**: used in both.

Both subjects have a technology-active Exam 2, where this toolkit is allowed.

| # | Topic | Course | Notes |
|---|-------|--------|-------|
| 1 | Function graph & features | MM SM | |
| 2 | Find unknown constants | MM SM | |
| 3 | Transformations of graphs | MM | |
| 4 | Simultaneous equations with a parameter | MM | |
| 5 | Area, volume, arc length, surface area | MM SM | area under and between curves is MM; volumes, arc length and surface area are SM |
| 6 | Differential equation models | SM | |
| 7 | Constant acceleration (SUVAT) | SM | |
| 8 | Kinematics | SM | |
| 9 | Probability & statistics | MM SM | see the next table |
| 0 | Angle between vectors | SM | press 0 for the tenth topic |

Kinds of question under Probability & statistics:

| # | Kind | Course |
|---|------|--------|
| 1 | Normal distribution | MM |
| 2 | Normal: find μ and σ | MM |
| 3 | Binomial | MM |
| 4 | Discrete random variable | MM |
| 5 | Probability density function | MM |
| 6 | Sample proportion & CI | MM |
| 7 | Sample mean & CI | SM |
| 8 | Linear combinations | SM |
| 9 | Hypothesis test | SM |

## Solvers

| Solver | What you can enter | What you get |
|--------|--------------------|--------------|
| Function graph | f(x), x window, optional y window; show/hide choices for asymptotes, turning points, inflection points, intercepts, discontinuities and labels | <ul><li>vertical, horizontal and oblique (or curved) asymptotes</li><li>stationary points classified as max, min or stationary inflection</li><li>points of inflection and intercepts</li><li>holes, jumps and endpoints</li><li>points where f is not differentiable (corners, cusps, vertical tangents)</li><li>f′ and f″</li><li>an annotated graph</li></ul> |
| Find unknown constants | f(x) with letters (`a*x^3+b*x^2+c`, `a/(x-b)+c`, `k*e^(-x)`); one condition per box: `f(1)=3`, `f'(2)=0`, `f''(0)=0`, `(2,5)` (passes through), `tp(1,2)` or `max (1,2)` (turning point), `poi (0,1)` (inflection), `tangent y=2x+1 at x=1`, `asymptote x=2` / `asymptote y=3`, or any equation such as `integral(f(x),x,0,1)=2` | <ul><li>the equation from each condition</li><li>the simultaneous solution (every solution when there are several)</li><li>f(x) with the values substituted</li><li>a check of every condition</li><li>a graph with the given points, the tangent and the asymptotes</li></ul> It asks for more conditions when there are fewer than unknowns. |
| Transformations | f(x) and the image, either written with f (`-2f(3x-6)+4`) or as a rule (`3(x-1)^2+2`, `2sqrt(3-x)+1`); optional point `(1,1)` | <ul><li>A, n, b and c in y = A f(n(x + b)) + c (with f(3x−6) rewritten as f(3(x−2)))</li><li>the transformations in VCE order (dilations, reflections, then translations) in exam wording</li><li>the mapping (x, y) → (x/n − b, Ay + c) and its inverse</li><li>the image of the point</li><li>the rule of the image</li><li>both graphs with the point and its image</li></ul> |
| Simultaneous equations | two equations in x, y (or three in x, y, z) with one parameter, e.g. `kx+2y=k`, `2x+(k-3)y=k-2` | <ul><li>the matrix form and its determinant (factorised)</li><li>the values where det = 0</li><li>the unique solution in terms of k</li><li>for each det = 0 value, the reduced equations and whether there is no solution (parallel lines, inconsistent planes) or infinitely many, with the general solution in terms of λ (and μ)</li></ul> Without a parameter it simply solves the system. |
| Area, volume, arc length, surface area | y = f(x), x = g(y) or parametric x(t), y(t); optional second curve; limits as x values or as **y values** (choose *Limits are: y values*, or type `y=1` and `y=4`); limits and curves may contain a letter such as `a` or `k`; axis of rotation; with a letter, **given** `V=16pi`, `A=4` or `a=2` | <ul><li>area (split where the curve crosses the axis or the curves cross) and the signed integral</li><li>volume by discs/washers, or by the inverse function and shells for the other axis</li><li>arc length and surface area</li><li>a shaded graph</li><li>with y-value limits for y = f(x): the region beside the y-axis, with x written in terms of y (for example V = π∫ x² dy)</li><li>with a letter: area and volume in terms of it (assumed positive), or its value from a given volume or area, followed by every other result</li></ul> |
| DE models | model: growth/decay, Newton's cooling, logistic, mixing (tank), general dy/dx, related rates; initial value, a second data point or half-life/doubling time; "find" (`t=10`, `N=200`) | <ul><li>the DE and its solution, k, values and times</li><li>doubling time or half-life, and the limiting value</li><li>logistic point of fastest growth and maximum rate</li><li>mixing amount and concentration (variable volume too)</li><li>deSolve result, Euler table and a slope field</li><li>related-rates chain rule</li><li>a graph</li></ul> |
| SUVAT | any three of s, u, v, a, t | the other two (both roots when there are two, negative t rejected) |
| Kinematics | a(t), a(v), a(x), v(t), v(x), v²(x) or x(t), which may contain an unknown constant k; known state t₀, x₀, v₀ (optional); conditions in "also" (`x(2)=5`, `a=-3.5 when v=7`, `a(7)=-3.5`, several separated by `;`); **Find** (everything, x, v, a or t, or one function: x(t), v(t), a(t), v(x), v²(x), a(x), t(x), x(v), t(v), a(v)) **when** (`t=3`, `v=0`, `x=5`, `a=0`); time interval | <ul><li>the derived relations (v(t), x(t), v(x), t(v), x(v), ...) with their domains</li><li>unknown constants and terminal velocity</li><li>values at the requested instant, or only the quantity chosen in **Find**</li><li>a function chosen in **Find** (such as v(x) from a(t)), worked out by differentiating, solving for the other variable (the branch through the known state) or substituting, e.g. v(x) = v(t(x))</li><li>a "Not enough conditions" note naming the missing value (for example x₀) when something cannot be found</li><li>displacement and distance (split at turning points)</li><li>average velocity and speed</li><li>without an initial state, the general solution with +c</li></ul> |
| Angle between vectors | **Use** two vectors a, b or three points A, B, C (angle ABC, vertex B); vectors as `2i-j+3k`, `(2,-1,3)`, `[2,-1,3]` or `<2,-1,3>` (2D or 3D); **Angle**: 0 to 180° (between vectors) or acute (between lines, 180° − θ when obtuse); **Unit**: degrees or radians; with one letter such as `m` in a vector, **given θ** (`60`, `pi/3`) | <ul><li>BA = A − B and BC = C − B for three points</li><li>a·b, \|a\|, \|b\| and cos θ with working</li><li>θ in the chosen unit (both units in the working); perpendicular or parallel is said</li><li>the acute angle 180° − θ when asked for and θ is obtuse</li><li>with a letter and a given angle: (a·b)² = \|a\|²\|b\|² cos²θ (a·b = 0 for 90°), solved, and each value checked; values that give 180° − θ are rejected unless the acute angle was chosen</li><li>without a given angle: the answers in terms of the letter</li></ul> |
| Normal distribution | μ, σ or σ², event (`45<X<55`, `X>k`, `X>60\|X>50`), Pr, area | probability, inverse normal (k), unknown μ or σ, z-scores, x for a given area |
| Normal: find μ and σ | two events with probabilities | μ, σ by solving the standardised equations simultaneously |
| Binomial | any two of n, p, E(X), Var(X), SD(X); event; Pr (`>=0.95`) | exact probabilities (binomCdf/binomPdf working), conditional probabilities, smallest n, p from a probability |
| Discrete random variable | x values, probabilities with unknowns (`0.1,k,2k,0.3`), E(X) | unknown constants, E(X), E(X²), Var(X), SD, median, mode, P(event) |
| Probability density function | up to three pieces f(x) on [a, b] (∞ allowed), E(X), event, Pr, area | constant k (from total area 1), E(X), Var(X), SD, median, mode, P(a<X<b), x for an area, k in P(X<k)=p |
| Sample proportion & CI | p, n, event for p̂ (`P>0.3`, `0.2<P<0.4`; `X>=20` for the count), count x or p̂, level, margin of error E, a given interval | <ul><li>E(p̂) = p, SD(p̂) = √(p(1−p)/n) and Var(p̂)</li><li>P(p̂ ...) exactly, as P(X ...) with X = np̂ ~ Bi(n, p)</li><li>the same probability by the normal approximation</li><li>p̂ = x/n and the approximate confidence interval p̂ ± z√(p̂(1−p̂)/n)</li><li>the sample size for a margin of error (with p̂ = ½ when unknown)</li><li>p̂, E, n or the level from a given interval</li></ul> |
| Sample mean & CI | μ, σ (s), n, x̄, level, z, E, width, interval | SD(X̄), z, margin of error, confidence interval, sample size (rounded up), level from an interval, P(X̄ > a) |
| Linear combinations | E, SD/Var of X and Y, W = `2X-3Y+4` or `X1+X2+X3`, event such as `X1+X2>2Y` | E(W), Var(W) (independent variables), normal probabilities |
| Hypothesis test | μ₀, H₁ (<, >, ≠), σ, n, x̄, α, decision rule c, true μ | z, p-value, decision, critical x̄, P(Type I), P(Type II), power |

In Probability, enter on the **Type** box (or a click on it) opens the list of kinds again; left/right steps through them. Each kind keeps its own inputs, so switching away and back loses nothing.

### Kinematics formulas and domains

Each derived formula shows its domain under it. The domain follows from the motion:
- `a(v)`: v moves from v₀ towards the terminal velocity (or 0, or ±∞).
- `a(x)` and `v²(x)`: x moves from x₀ to the turning point where v² = 0.
- Formulas in t hold for t ≥ t₀, cut short where the formula stops being defined.

Enter switches a formula between exact and decimal, like every other answer. Select a formula and press **W** (or choose *Working for this formula* in the ctrl+menu context menu) to see only the steps that lead to it, including the given information and any constant found.

If the question gives no x₀ or v₀ but, for example, the acceleration at a certain velocity, type that condition into **also**: `a=-3.5 when v=7`. The unknown constant is found first. Without an initial state, t(v) and x(v) are given as general solutions with +c.

### Graphs

The function graph, area/volume and DE model solvers draw a graph under the results:
- asymptotes are dashed red lines; one that lies on an axis (x = 0 or y = 0) is drawn on both sides of the axis, so the axis does not hide it;
- marked points have labels;
- regions are hatched;
- slope fields are drawn for dy/dx.

Select the graph and press **enter** (or click it) to open it full screen:

| Key | Action |
|-----|--------|
| left / right | trace along the curve (x, y and t shown at the top) |
| up / down | jump between the marked points (turning points, intercepts, ...) |
| tab | next curve |
| + / − | zoom in / out around the cursor |
| 8 4 6 2 | pan up / left / right / down |
| 5 or 0 | reset the window |
| l / a | labels on/off, asymptotes on/off |
| esc / enter | back to the worksheet |

The function graph samples f numerically and uses the CAS for exact candidates:
- zeros of denominators;
- arguments of ln, log and √;
- poles of tan, sec, cot and csc;
- solutions of f′ = 0 and f″ = 0;
- limits at ±∞ and at holes.

Exact values are shown where the CAS finds them. Points it finds only numerically are rounded to six decimal places. Change the window if a feature lies outside it.

### Input conventions

- Numbers, fractions and CAS expressions all work: `1/3`, `√(2)`, `e^(-0.5x)`, `inf` (∞), `pi`.
- **Functions from other pages** of the same problem work too: `f11(t)` as an acceleration, `f11(2)` as a value. Press ctrl+menu on a field and choose **Insert document function** to list them.
- Leave unknowns empty. In an event, an unknown bound is any letter: `X<k`, `50-c<X<50+c`.
- In *Find unknown constants*, *Transformations* and *Simultaneous equations*, `kx` means k·x and `k(x-1)` means k·(x−1); the box shows the product so you can check it.
- Single letters in kinematics, PDF and discrete inputs are local symbols, so a stored document variable called `x` or `k` cannot interfere.
- Calculations use radians and real numbers whatever the document settings, using `math.setEvalSettings` when the OS supports it.

## Keys

| Key | Action |
|-----|--------|
| digits on the home screen | open topic 1–9 (0: the tenth) |
| digits in a list of kinds | choose that kind (Probability step 1) |
| up / down | move between rows |
| typing | edits the selected field (a preview shows it in 2D, like the CAS) |
| enter | solve and move to the next field; on any result (formulas too) it switches **exact ⇄ decimal**; on a choice with many options (Probability's Type) it opens the list |
| W | on a derived formula (e.g. x(v)): the working for that formula only (esc returns) |
| click (touchpad) | select a row; clicking a result switches exact ⇄ decimal |
| left / right | move the cursor in a field, change a choice, switch a result or scroll a long answer |
| tab / shift+tab | next / previous field |
| esc | undo the unsaved edit, else go back (home) |
| del / clear | delete a character / clear the field |
| ctrl+C | copy the selected row: an answer as shown (exact or decimal, in calculator syntax), a working line, the text in a box (even while typing) or a choice; the bottom bar shows what was copied. Paste it into a Calculator page |
| ctrl+X | in a box: copy its text and clear it |
| menu | toolbar: new problem, duplicate, tag, clear, previous/next, solvers, history, settings, help |
| ctrl+menu | context menu: insert a document function or symbol, store to a variable, send to the RPN stack, the working for a formula |
| on result/working rows: n / p | next / previous problem |
| t / h / d / e | tag the problem / history / all decimal / all exact |

## History and tags

Each problem you open is kept in the history (up to 60), together with its inputs and an optional tag such as `2023 E2 Q5b`. You can tag a problem with **menu › Problem › Tag** or <kbd>t</kbd>. **History** lists every problem, and typing filters it by tag or content. The history and settings are saved with the document.

## Settings

**Settings** on the home screen (also **menu › Settings › All settings**) shows every setting on one screen; left/right changes a setting and it applies at once:

- decimal places (2–6) for decimal answers; values keep full precision, so this affects display only;
- whether answers start exact or decimal;
- text size (small, normal or large);
- colours (soft cream or plain white);
- language (English, or Chinese + English): only in `vce_zh.tns`.

Settings are saved with the document. Use **All exact / All decimal** in the menu to switch every result at once.

## 中英双语版 (vce_zh.tns)

- 界面、输入格的标签和提示、菜单、帮助、提示信息都显示中英两种语言。
- 每个结果旁边用灰色小字标出术语的中英文名称，例如 `σ² = 16    variance 方差`、`P(Type II) = 0.1962    Type II error 第二类错误`。
- 解题步骤（Working）保持英文，与 VCE 考试的答题语言一致。
- 可以在 **menu › 设置 Settings › 语言 Language** 里切换成纯英文显示，设置会随文档保存。
- 英文版 `vce.tns`（以及 `rpn.tns`）完全是英文：不含任何中文，也没有语言选项。
- 中文显示依赖计算器系统字体中的中文字形。TI-Nspire CX II 系统支持简体中文，一般可以正常显示；如果出现方框，请切换回英文，或改用 `vce.tns`。

## Development

- Solvers: `apps/vce/solvers/*.lua`, listed in `apps/vce/registry.lua`.
  - Each solver declares fields and a `solve(inputs, report)` function. It adds results, working lines and notes, and can set `report.graph` to a plot spec.
  - `registry.list` holds every solver. `registry.home` is the home screen, where `registry.probability` is a group made with `apps/vce/solvers/group.lua`; a group stores member inputs as `<member>.<field>`.
  - The registry also gives each solver its course (`MM`, `SM` or both) and its one-line home blurb.
  - A field with `implicit = true` reads `kx` as k·x.
  - A result with `text = true` is a sentence answer.
- Graphs: `apps/vce/numeric.lua` compiles CAS expressions into Lua functions for fast sampling; `ui/plot.lua` draws a plot spec (curves, asymptotes, points, shading, slope field); `views/graphview.lua` is the full-screen trace/zoom view.
- CAS bridge: `apps/vce/cas.lua`. Formatting: `apps/vce/fmt.lua`. Event parser: `apps/vce/event.lua`.
- UI: `views/sheet.lua` holds the worksheet rows; `ui/mathbox.lua` is the 2D pretty printer; `apps/vce/app.lua` handles screens, menu, history and persistence.
- Entry points: `vce.lua` (English) and `vce_zh.lua` (bilingual) share `apps/vce/entry.lua`; `apps/vce/launcher.lua` adds the toolkit to the rpnspire app list.
- Languages: `apps/vce/i18n.lua` holds the lookup functions and the English help. All Chinese text (interface strings, solver titles, field hints, result terms, note patterns, help) is in `apps/vce/i18n_zh.lua`, which only `vce_zh.lua` loads (`i18n.install`). Without it the toolkit is English only and hides the language setting, so `vce.tns` and `rpn.tns` carry no Chinese; `tools/bundle_smoke.lua` fails if an English bundle contains Chinese characters. Keep Chinese text out of every other module. Working steps are not translated.
- Tests: `lua test_vce.lua` runs the solvers against the numeric mock in `testcas.lua` and drives the UI with key events. `lua5.1 tools/bundle_smoke.lua vce_bundle.lua` runs the built bundle without `require`/`io`/`os`. `tools/render.sh <dir>` renders approximate desktop screenshots (needs Chromium).
