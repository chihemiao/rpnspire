# VCE Specialist Maths toolkit

A TI-Nspire CX II CAS Lua program for VCE Specialist Mathematics (tech-active) calculus, mechanics, probability and statistics questions. You type in the values you know, press **enter**, and it fills in everything that can be worked out. It shows exact values first, and each answer comes with brief working laid out the way VCE marking schemes expect.

The toolkit ships three ways:

- `vce.tns`: a standalone document. Open it and the toolkit starts.
- `vce_zh.tns`: the same toolkit in bilingual mode (中英双语). The interface, field labels and hints, notes, menus, help and the name of every result (for example *variance 方差*, *Type II error 第二类错误*) appear in Chinese and English. The working steps stay in English, the language of the VCE exam. You can switch language in either document under **menu › Settings › Language**; the choice is saved with the document.
- `rpn.tns`: rpnspire with the toolkit built in. Press <kbd>.</kbd> <kbd>a</kbd> and choose **VCE Specialist toolkit**. With **Send to RPN stack** in the context menu you can push a result onto the rpnspire stack.

> Status: the solvers are tested on a desktop against a numeric CAS mock (`testcas.lua`), and the bundled document is smoke-tested in a TI-like Lua 5.1 sandbox. The real TI CAS (exact output, syntax) still has to be checked on a handheld or in the TI-Nspire CX CAS software. Run **Help › Self-test** once on your calculator: it solves 39 known problems and reports any that fail.

## Solvers

Solvers are grouped on the home screen: calculus first, then mechanics, then probability and statistics. Digits open solvers 1–10 directly (0 is the tenth); the last three are opened from the list or from **menu › Solvers**.

| # | Solver | What you can enter | What you get |
|---|--------|--------------------|--------------|
| 1 | Function graph | f(x), x window, optional y window; show/hide choices for asymptotes, turning points, inflection points, intercepts, discontinuities and labels | vertical, horizontal and oblique (or curved) asymptotes; stationary points classified as max/min/stationary inflection; points of inflection; intercepts; holes, jumps, endpoints; points where f is not differentiable (corners, cusps, vertical tangents); f′ and f″; an annotated graph |
| 2 | Area, volume, arc length, surface area | y = f(x), x = g(y) or parametric x(t), y(t); optional second curve; limits; axis of rotation | area (split where the curve crosses the axis or the curves cross) and the signed integral, volume by discs/washers or by the inverse function and shells for the other axis, arc length, surface area, a shaded graph |
| 3 | DE models | model: growth/decay, Newton's cooling, logistic, mixing (tank), general dy/dx, related rates; initial value, a second data point or half-life/doubling time; "find" (`t=10`, `N=200`) | the DE and its solution, k, values and times, doubling/half-life, limiting value, logistic point of fastest growth and maximum rate, mixing amount and concentration (variable volume too), deSolve result and Euler table with a slope field, related-rates chain rule; a graph |
| 4 | SUVAT | any three of s, u, v, a, t | the other two (both roots when there are two, negative t rejected) |
| 5 | Kinematics | a(t), a(v), a(x), v(t), v(x), v²(x) or x(t); known state t₀, x₀, v₀; a second condition (`x(2)=5`); "find when" (`t=3`, `v=0`, `x=5`, `a=0`); time interval | the derived relations (v(t), x(t), v(x), t(v), x(v), ...), terminal velocity, values at the requested instant, displacement, distance (split at turning points), average velocity and speed |
| 6 | Normal distribution | μ, σ or σ², event (`45<X<55`, `X>k`, `X>60\|X>50`), Pr, area | probability, inverse normal (k), unknown μ or σ, z-scores, x for a given area |
| 7 | Normal: find μ and σ | two events with probabilities | μ, σ by solving the standardised equations simultaneously |
| 8 | Binomial | any two of n, p, E(X), Var(X), SD(X); event; Pr (`>=0.95`) | exact probabilities (binomCdf/binomPdf working), conditional probabilities, smallest n, p from a probability |
| 9 | Discrete random variable | x values, probabilities with unknowns (`0.1,k,2k,0.3`), E(X) | unknown constants, E(X), E(X²), Var(X), SD, median, mode, P(event) |
| 0 | Probability density function | up to three pieces f(x) on [a, b] (∞ allowed), E(X), event, Pr, area | constant k (from total area 1), E(X), Var(X), SD, median, mode, P(a<X<b), x for an area, k in P(X<k)=p |
| – | Linear combinations | E, SD/Var of X and Y, W = `2X-3Y+4` or `X1+X2+X3`, event such as `X1+X2>2Y` | E(W), Var(W) (independent variables), normal probabilities |
| – | Sample mean & CI | μ, σ (s), n, x̄, level, z, E, width, interval | SD(X̄), z, margin of error, confidence interval, sample size (rounded up), level from an interval, P(X̄ > a) |
| – | Hypothesis test | μ₀, H₁ (<, >, ≠), σ, n, x̄, α, decision rule c, true μ | z, p-value, decision, critical x̄, P(Type I), P(Type II), power |

### Graphs

The function graph, area/volume and DE model solvers draw a graph under the results:
- asymptotes are dashed red lines;
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
- Single letters in kinematics, PDF and discrete inputs are local symbols, so a stored document variable called `x` or `k` cannot interfere.
- Calculations use radians and real numbers whatever the document settings, using `math.setEvalSettings` when the OS supports it.

## Keys

| Key | Action |
|-----|--------|
| digits on the home screen | open solver 1–9, 0 (the tenth) |
| up / down | move between rows |
| typing | edits the selected field (a preview shows it in 2D, like the CAS) |
| enter | solve and move to the next field; on a result it switches **exact ⇄ decimal** |
| click (touchpad) | select a row; clicking a result switches exact ⇄ decimal |
| left / right | move the cursor in a field, change a choice, switch a result or scroll a long answer |
| tab / shift+tab | next / previous field |
| esc | undo the unsaved edit, else go back (home) |
| del / clear | delete a character / clear the field |
| ctrl+C | copy the selected value or working line (paste it into a Calculator page) |
| menu | toolbar: new problem, duplicate, tag, clear, previous/next, solvers, history, settings, help |
| ctrl+menu | context menu: insert a document function or symbol, store to a variable, send to the RPN stack |
| on result/working rows: n / p | next / previous problem |
| t / h / d / e | tag the problem / history / all decimal / all exact |

## History and tags

Each problem you open is kept in the history (up to 60), together with its inputs and an optional tag such as `2023 E2 Q5b`. You can tag a problem with **menu › Problem › Tag** or <kbd>t</kbd>. **History** lists every problem, and typing filters it by tag or content. The history and settings are saved with the document.

## Settings

Under **menu › Settings** you can choose 2–6 decimal places for decimal answers and a small, normal or large font. Decimal places affect display only; values keep full precision. Use **All exact / All decimal** to switch every result at once.

## 中英双语版 (vce_zh.tns)

- 界面、输入格的标签和提示、菜单、帮助、提示信息都显示中英两种语言。
- 每个结果旁边用灰色小字标出术语的中英文名称，例如 `σ² = 16    variance 方差`、`P(Type II) = 0.1962    Type II error 第二类错误`。
- 解题步骤（Working）保持英文，与 VCE 考试的答题语言一致。
- 两个文件可以随时在 **menu › 设置 Settings › 语言 Language** 里切换语言，设置会随文档保存。
- 中文显示依赖计算器系统字体中的中文字形。TI-Nspire CX II 系统支持简体中文，一般可以正常显示；如果出现方框，请切换回英文。

## Development

- Solvers: `apps/vce/solvers/*.lua`, listed in `apps/vce/registry.lua`. Each solver declares fields and a `solve(inputs, report)` function that adds results, working lines and notes, and optionally sets `report.graph` to a plot spec.
- Graphs: `apps/vce/numeric.lua` compiles CAS expressions into Lua functions for fast sampling; `ui/plot.lua` draws a plot spec (curves, asymptotes, points, shading, slope field); `views/graphview.lua` is the full-screen trace/zoom view.
- CAS bridge: `apps/vce/cas.lua`. Formatting: `apps/vce/fmt.lua`. Event parser: `apps/vce/event.lua`.
- UI: `views/sheet.lua` holds the worksheet rows; `ui/mathbox.lua` is the 2D pretty printer; `apps/vce/app.lua` handles screens, menu, history and persistence.
- Entry points: `vce.lua` (English) and `vce_zh.lua` (bilingual) share `apps/vce/entry.lua`; `apps/vce/launcher.lua` adds the toolkit to the rpnspire app list.
- Translations: `apps/vce/i18n.lua` (interface strings, solver titles, field hints, result terms, note patterns, help). Working steps are not translated.
- Tests: `lua test_vce.lua` runs the solvers against the numeric mock in `testcas.lua` and drives the UI with key events. `lua5.1 tools/bundle_smoke.lua vce_bundle.lua` runs the built bundle without `require`/`io`/`os`. `tools/render.sh <dir>` renders approximate desktop screenshots (needs Chromium).
