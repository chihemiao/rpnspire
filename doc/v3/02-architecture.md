# 3.0 架构设计

> 状态：设计稿，未开始实现。代码标识符用英文，说明用中文。
> 相关文件：[现有功能总结](01-current-features.md) · [新功能设计](03-features.md) · [调试与测试](04-debug-and-testing.md) · [迁移计划](05-migration-plan.md)

## 1. 为什么要重新设计

2.x 是一个功能一个功能加上去的，现在有 18 个解题器、一个 1400 行的 `apps/vce/app.lua` 和一个 1100 行的 `kinematics.lua`。要加的新东西（逐个答案展开步骤、多函数作图、三维向量工作台）都会碰到同一组结构问题：

| 问题 | 现在的样子 | 后果 |
|---|---|---|
| 数学和界面混在一起 | 解题器直接往 `report` 里写带反引号的显示文本；`app.lua` 既管按键又管缓存、又管行的拼装 | 改界面就要动解题器，反过来也一样 |
| 一切都是字符串 | CAS 表达式靠字符串拼接（`'derivative(' .. fx .. ',' .. X .. ')'`），向量、直线、点各自临时解析 | 括号、负号、变量名的 bug 反复出现；同一种对象有好几套解析代码 |
| 答案不知道自己从哪来 | 只有 kinematics 用 `R:tag()` 给步骤打了标签，其他解题器的步骤是一整串 | 做不了“选中答案按 enter 展开它的步骤” |
| 计算是阻塞的 | 一次分析在一个按键事件里跑完，期间不能重画、不能取消 | 卡；2.4 只能靠“离开输入框再算”绕开 |
| 状态是全局可变的 | `A.*`、`p._cache`、`p._dirty`、图像 spec 被 `auto_range` 原地改写 | 难以推理，出现过缓存被坏的视图结果污染（2.4 修的 y 轴问题） |
| 翻译靠英文原文和正则 | 中文 NOTES 是有序的 Lua pattern 列表，按英文原句匹配 | 改一个英文字就丢翻译，带参数的句子要写正则 |
| 没有可观测性 | 出错只有一条 note；不知道哪次 CAS 调用慢 | 真机上的问题无法复现 |

3.0 的目标是：**新功能能自然地放进去，问题能在真机上被看到、被记录、被复现。**

## 2. 硬约束（不能违背）

1. **运行环境**：TI-Nspire CX II CAS 内置 Lua（5.1）+ TI 脚本 API。没有 `io`、`os`、`package`、`dofile`、`loadfile`；所有模块由 luabundler 打成一个脚本，再由 Luna 转成 `.tns`。一个文档页只有一个脚本，不能在运行时加载别的文件。
2. **CAS 只有一个入口**：`math.evalStr(string) -> string | nil, errcode`。输入输出都是字符串；每次调用是阻塞的，真机上可能要几十到几百毫秒；求值设置（角度、精确/近似）是全局的。
3. **屏幕和输入**：318×212 像素；方向键、enter、esc、tab、menu、ctrl 组合、字母数字键、触摸板点击。
4. **体积和内存**：现在 `vce.tns` 155 KB、`vce_zh.tns` 173 KB（源码打包后 615/666 KB）。3.0 会更大，要设预算并在 CI 里检查（见 §11）。Lua 堆的上限没有公开数字，要在真机上用 `collectgarbage('count')` 实测（调试面板，见调试设计）。
5. **三个产物**：`vce.tns`（只有英文）、`vce_zh.tns`（中英双语）、`rpn.tns`（原 RPN 计算器，通过 launcher 带上工具箱）。英文产物里不能有中文（`tools/bundle_smoke.lua` 检查）。
6. **网站模拟器**：网站用 wasmoon 在浏览器里跑同一份 Lua，CAS 用 mock 加录制好的答案。3.0 必须继续能在这里跑。
7. **已有用户的文档**：`on.save` 保存的 2.x 历史题目要能升级到 3.0 的格式，不能丢。

## 3. 设计原则

1. **数学不认识界面，界面不认识数学。** 数学层只产出结构化的“结论”（Fact），界面层只负责把结论变成行。
2. **先有数据模型。** 点、向量、直线、平面、函数、区间都是有类型的对象，每种对象只有一个解析器和一组格式化函数。
3. **每个答案都知道自己是怎么来的。** 结论之间有依赖关系，步骤挂在结论上。
4. **计算是任务。** 可以分段执行、可以取消、结果可以缓存，界面在计算时照常重画。
5. **一层只依赖下面的层。** 由脚本检查，违反就让 CI 失败。
6. **可观测是默认功能**，不是出 bug 之后才加：日志、CAS 调用记录、计时、录制/回放都在框架里。
7. **每一层都能单独测试**，靠可替换的后端（CAS、平台、时钟）。

## 4. 分层与目录

```
            ┌──────────────────────────────────────────────────────┐
  L7 ui     │ widgets: sheet, rows, mathbox, plot, viewer, dialogs │  画、量尺寸、命中测试
            ├──────────────────────────────────────────────────────┤
  L6 app    │ store, controller(intents), jobs, viewmodels, screens│  状态、按键 → 意图 → 状态
            ├──────────────────────────────────────────────────────┤
  L5 topics │ form topics (normal, kinematics, …)                  │  每个主题：输入表、求解、
            │ workspaces (graph studio, vector studio)             │  展示选项、例子、自检用例
            ├──────────────────────────────────────────────────────┤
  L4 work   │ Fact, FactGraph, Step, explain rules, needs          │  结论图与步骤
            ├──────────────────────────────────────────────────────┤
  L3 mathx  │ fn + analysis, geom3, prob, kin, de, calc, linsys …  │  纯数学领域对象和算法
            ├──────────────────────────────────────────────────────┤
  L2 cas    │ engine, expr(AST), input, ops, num(numeric)          │  唯一接触 math.evalStr 的层
            ├──────────────────────────────────────────────────────┤
  L1 base   │ class, util, log, prof, i18n core, result, bus       │  无依赖的基础设施
            ├──────────────────────────────────────────────────────┤
  L0 plat   │ host interface: ti / web / test                      │  gc、事件、计时器、var、剪贴板
            └──────────────────────────────────────────────────────┘
```

建议的目录（新代码放在 `v3/` 下，2.x 代码不动，直到 3.0 替换它，见迁移计划）：

```
v3/
  plat/        host.lua (接口), ti.lua, web.lua, test.lua   ← test.lua 取代现在散在 5 处的 TI 运行时桩
  base/        class.lua, util.lua, log.lua, prof.lua, i18n.lua, result.lua, bus.lua, ser.lua
  cas/         engine.lua, expr.lua, input.lua, ops.lua, num.lua, settings.lua
  mathx/       fn.lua, interval.lua, analysis/{asymptote,stationary,inflection,intercept,discont,domain}.lua,
               geom3/{vec,point,line,plane,forms,ops,classify}.lua, prob/*, kin/*, de/*, calc/*,
               transform.lua, linsys.lua, params.lua
  work/        fact.lua, graph.lua, step.lua, rules.lua, needs.lua
  topics/      registry.lua, form.lua, workspace.lua,
               normal/{schema,solve,present,examples,cases}.lua, kinematics/…, graph/…, vectors/…
  app/         store.lua, controller.lua, intents.lua, jobs.lua, screens/*.lua, vm/*.lua, persist.lua, migrate.lua
  ui/          sheet.lua, rows/{field,choice,answer,work,note,group,graph,object,query}.lua,
               mathbox.lua, plot/{spec,draw,cache,auto}.lua, viewer.lua, dialogs/*.lua, theme.lua
  i18n/        en.lua (默认文本), zh/*.lua (只进中文版)
  entry/       vce.lua, vce_zh.lua, launcher.lua, dev.lua
  debug/       panel.lua, trace.lua, recorder.lua, snapshot.lua, asserts.lua   (发布版可裁剪)
```

**依赖规则**（`tools/arch_check.lua` 解析每个文件的 `require`，按下表检查）：

| 层 | 可以 require |
|---|---|
| plat | base（只限 log） |
| base | 无 |
| cas | base |
| mathx | base, cas |
| work | base, cas（只限 expr 格式化） |
| topics | base, cas, mathx, work |
| app | base, work, topics（只通过 registry 和接口）, plat |
| ui | base, plat；以及 app 的 view-model 结构（只读） |
| debug | 任何层（只在 dev 构建里被 entry 引入） |

## 5. 核心概念

### 5.1 值类型与领域对象

字符串只出现在两头：用户输入，以及发给 CAS 的表达式。中间都是对象。

```lua
-- 一个精确表达式。src 是 TI 中缀（发给 CAS 用），ast 按需解析（格式化、改写用）
Expr = { src = 'x^2-4', ast = <lazy>, approx = <lazy number|nil> }

Vec3   = { x = Expr, y = Expr, z = Expr }
Point3 = { name = 'A', pos = Vec3 }
Line3  = { name = 'l1', point = Vec3, dir = Vec3, param = 'λ' }          -- r = a + λd
Plane3 = { name = 'Π1', normal = Vec3, k = Expr }                        -- r·n = k（规范形式）
         -- 另存一份用户给的形式（点 + 两个方向）用于“原样显示”
Fn     = { name = 'f', var = 'x', expr = Expr, domain = Interval|nil, num = <compiled> }
Interval = { lo = Expr|nil, hi = Expr|nil, lo_closed = bool, hi_closed = bool }
```

每种对象：

- **一个解析器**（`geom3.parse_line(text, ctx)` 接受所有写法，见新功能设计），返回 `Result.ok(obj)` 或 `Result.err{code, at, hint}`；错误带位置，界面直接在输入框下面显示。
- **一组格式化函数**（`Line3:forms(opts)` 返回向量式、参数式、笛卡尔/对称式；`opts` 指定参数字母、变量名）。
- **只读**。运算返回新对象，不改原对象（解决 2.x 中 spec 被原地修改的问题）。

### 5.2 题目、输入框和输入类型

```lua
Problem = { id = 7, topic = 'graph', inputs = { f = 'x^2-4', xmin = '-6' }, tag = 'Q3b',
            ui = { expanded = { max1 = true }, modes = { max1 = 'approx' } } }
```

输入框声明有类型，类型决定解析器、提示、校验和“是否影响数学”：

```lua
schema = {
  { id = 'f',    type = 'expr',   vars = { 'x' }, label = 'f(x) =', hint = '(x^2-1)/(x-2)' },
  { id = 'xwin', type = 'interval', default = '[-10,10]' },
  { id = 'ywin', type = 'interval', optional = true, display = true },   -- display=true：只影响画面
  { id = 'asym', type = 'choice', options = { 'dashed', 'hide' }, display = true, place = 'graph' },
}
```

- `display = true` 取代 2.x 的 `view_fields`：改它不会重新求解。
- `place = 'graph'` 取代 2.4 的 `graph_option`：这些行放在图下面的“图像选项”里。
- `show = function(inputs) … end` 照旧，用于按类型显示/隐藏输入框。
- 解析结果按原始字符串缓存，改一个框只重新解析这个框。

### 5.3 两种主题：表单（Form）和工作台（Workspace）

- **表单主题**：固定的输入框，求出一组答案。概率、SUVAT、运动学、微分方程、面积体积、参数等都是这一种。生命周期：`schema → parse → solve(ctx) → FactGraph → present`。
- **工作台主题**：用户自己添加对象（函数 f、g、h…；点、向量、直线、平面…），再添加“问题”（交点、距离、夹角、面积…）。作图工作台和向量工作台是这一种。生命周期：`objects[] + queries[] → 每个对象的分析 + 每个问题的求解 → FactGraph`。对象和问题各有自己的缓存键，加一个问题不会让别的重算。

两者共用同一个 FactGraph、同一套行渲染和按键，只是 view-model 不同。

```lua
-- 主题接口（表单）
Topic = {
  id = 'normal', course = 'MM SM', group = 'prob',
  schema = {...}, examples = {...}, cases = {...},          -- cases：自检和桌面测试共用的用例
  solve = function(ctx, I) end,                             -- 只写 ctx.facts，不碰界面
  present = function(P, facts, D) end,                      -- 可选：按 display 输入调整分组、图像选项
  defer = true,                                             -- 离开输入框再算（2.4 的行为，变成默认策略之一）
}
-- 工作台额外有：
Workspace = {
  object_kinds = { 'fn', 'point', 'vline', 'hline' },
  analyze = function(ctx, obj) end,                         -- 单个对象的分析（例如函数的驻点）
  queries = { intersect = {...}, area_between = {...} },    -- 每个问题：需要几个、什么类型的对象，solve 函数
}
```

### 5.4 结论图（FactGraph）：取代 `report`

这是 3.0 最核心的变化，直接支撑“选中答案按 enter 展开它的步骤”。

```lua
Fact = {
  id = 'max1',                       -- 稳定的键：UI 状态（展开、精确/小数）靠它保存
  kind = 'point',                    -- value | point | formula | equation | object | set | text
  label = { key = 'graph.max', args = {} },   -- i18n 消息，不是拼好的字符串
  value = <typed>,                   -- Expr / {Expr,Expr} / Line3 …
  approx = <number | table | nil>,
  group = 'turning',                 -- 用于分组显示：“转折点 (2)”
  deps = { 'd1', 'crit' },           -- 它用到的其他结论
  steps = { Step, … } | nil,         -- 它自己的步骤（只写本结论新增的推导）
  explain = function(ctx) end,       -- 可选：步骤延迟生成，第一次展开时才算
  domain = Interval | nil, unit = 'm/s' | nil,
  plot = { point = { x = 1, y = 2 }, curve = 'f' },   -- 和图像的联动：选中答案时图上高亮
  primary = true,                    -- 主答案（默认展示），次要的放进“更多”
}
Step = { text = { key = 'rule.stationary', args = { … } } | 'raw `math`', uses = { 'd1' } }
Note = { level = 'warn', msg = { key = 'kin.need', args = { fn = 'v(x)', give = { 'x0', 'v0' } } },
         needs = { 'x0', 'v0' } }      -- needs：界面可以提供“跳到这个输入框”
```

FactGraph 提供：`add`、`get`、`closure(id)`（依赖闭包，按拓扑序）、`groups()`、`notes()`、`needs()`、一致性检查（依赖存在、无环，dev 构建里自动跑）。

“某个答案的步骤” = `closure(id)` 里每个结论的 `steps`，按拓扑序排列；依赖的结论默认折叠成一行（“用到：f′(x) = …，enter 展开”），只有被选中的答案自己的步骤是展开的。这样转折点的步骤不会把导数的推导重复写三遍。

旧的“整页步骤”仍然保留：菜单里的“显示全部步骤”就是按拓扑序列出所有结论的步骤。

### 5.5 计算任务（Job）：分段、可取消

```lua
jobs.run{ key = solve_key, fn = function(ctx) topic.solve(ctx, I) end,
          on_progress = function(phase, facts) … end, on_done = …, on_error = … }
```

- 任务跑在 coroutine 里。`ctx.cas:*` 每次调用 CAS 之后检查时间片，用完就 `coroutine.yield()`；`plat.timer` 的下一次 tick 再继续。界面在两次 tick 之间可以重画（显示“计算中：渐近线…”）并响应按键。
- 新输入到来时取消旧任务（键变了），所以不会出现“结果对应旧输入”。
- 任务可以**分阶段发布结论**：作图主题先发布曲线（马上能看到图），再发布驻点、交点、面积。
- **前提要在真机上验证**：TI Lua 里 coroutine 可用（原 rpnspire 的 `apps/apps.lua` 已经在用 `coroutine.wrap`），`timer.start` 的最小间隔和 `math.evalStr` 能否在 coroutine 里调用。迁移计划的第一个里程碑就是做这个验证；如果不行，任务退化为同步执行（接口不变，只是不分段）。
- 缓存：`solve_key`（只含影响数学的输入 + 设置里的小数位）→ FactGraph。展示类输入（`display = true`）只作用于 present 阶段，不进键。缓存的 FactGraph 是只读的；present 产出新的视图对象，不改缓存（避免 2.4 修过的“视图把缓存弄坏”）。

### 5.6 状态与视图模型

状态分三份，各自独立保存：

| 状态 | 内容 | 保存到文档 |
|---|---|---|
| `doc` | 题目列表（输入、标签）、设置 | 是（`on.save`） |
| `results` | 每个题目的任务状态和 FactGraph | 否（可重新计算） |
| `ui` | 当前屏幕、选中行、滚动、展开了哪些答案、精确/小数选择 | 部分（展开和精确/小数随题目保存） |

**行（Row）由纯函数生成**：`rows = vm.problem(doc_problem, results, ui)`。每一行有稳定的 key：

```
field:f   field:xwin   note:need:x0   header:graph   graph:main   opts:asym
group:turning   fact:max1   work:max1:1   work:max1:dep:d1   fact:min1   header:work …
```

选中、展开、滚动都按 key 记，行重建后能精确恢复（2.x 用 key 找回选中行，但结果行的 key 不稳定，找不到就跳回顶部）。

### 5.7 意图（Intent）与按键

按键先变成意图，控制器处理意图，所以按键映射可以集中修改、可以测试：

| 意图 | 默认按键 | 说明 |
|---|---|---|
| `move(±1)` | ▲▼ | 离开最后一个输入框时触发 `leave_form` |
| `next_field` | enter（在输入框）、tab | 最后一个输入框之后 → `leave_form` → 求解 → 选中图或第一个答案 |
| `expand(fact)` / `collapse` | enter（在答案上） | **新**：在答案下面展开它的步骤；再按一次收起 |
| `toggle_exact(fact)` | ◀▶（在答案上） | 精确 ⇄ 小数（2.x 的 enter 功能移到这里；长答案先横向滚动，滚到头再切换） |
| `toggle_group(g)` | enter（在分组标题上） | 折叠/展开“转折点 (2)”这类分组 |
| `open_viewer(graph)` | enter（在图上） | 全屏查看 |
| `jump(note.needs)` | enter（在“缺条件”提示上） | 跳到要补的输入框 |
| `add_object` / `add_query` | 工作台里的“+”行、menu | 工作台专用 |
| `copy` / `store` / `send_rpn` | ctrl+C、ctrl+menu | 和 2.x 一样 |
| `debug_panel` | menu › Debug（dev 构建或设置里打开后） | 见调试设计 |

## 6. 一次按键的数据流

```
on.charIn / on.arrowKey / on.enterKey …          (plat)
  → keymap → Intent                               (app/intents)
  → controller.apply(intent)                      (app/controller)
       ├─ 改 doc（输入）→ 解析该框 → 计算 solve_key
       │      └─ 键变了且策略允许 → jobs.run（取消旧任务）
       ├─ 改 ui（选中/展开/模式）
       └─ 标记脏区域
  → vm 重建受影响的行（按 key 增量）              (app/vm)
  → sheet 只重排受影响行的布局，invalidate 脏矩形   (ui)
  → on.paint 画可见行（图像用录制回放，编辑中用占位）
jobs tick（timer）→ 继续任务 → 发布结论 → 同上的 vm/ui 更新
```

## 7. CAS 层

- `cas/engine.lua`：唯一调用 `math.evalStr` 的地方。负责：后端注入（ti / mock / replay / record）、记忆化（沿用 2.x 的规则：只缓存不依赖文档变量的表达式）、计时、调用记录（给调试面板和录制用）、错误码归一化、求值设置（`math.setEvalSettings`）。2.x 的 `cas.init` 会改动全局求值设置，在 rpnspire 里打开工具箱时也改了 rpnspire 的设置；3.0 在进入时记下原设置，退出时恢复（需要能读取当前设置，例如 `math.getEvalSettings`，在 M0 里确认）。
- `cas/expr.lua`：表达式 AST + 构造器 + 打印器。主题代码写 `E.deriv(f, 'x')`、`E.sub(e, { x = E.num(2) })`、`E.eq(a, b)`，不再手写括号。打印器负责最少括号、负号（NEGATE）、TI 的特殊符号。解析器在 2.x 的 `ti/lexer.lua` + `expressiontree.lua` 基础上做。
- `cas/input.lua`：用户输入 → TI 表达式（2.x 的 `cas.input`：别名、负号、隐式乘法、局部变量重命名 `q9x`）。
- `cas/ops.lua`：有类型的高层操作，返回结构化结果：
  - `simplify(e)`, `approx(e)`, `deriv(e, x, n)`, `integrate(e, x, a, b)`, `limit(e, x, a, dir)`
  - `solve(eq, x, { domain })` → `{ sols = { Expr… }, all_reals = bool, none = bool, raw = string }`
  - `zeros`, `factor`, `expand`, `propfrac`, `desolve`, `linsolve(eqs, vars)`
  - 每个操作都有“CAS 读不懂时”的明确返回（不是 nil 混着用）。
- `cas/num.lua`：2.x 的 `numeric.lua`（表达式编译成 Lua 函数、二分、积分）。保留“编译不了就退回 CAS”的路径，但退回时记录一条警告日志（这正是 `f11(x)` 作图很慢的原因）。

## 8. 性能设计

1. **离开输入框再算**（2.4 的做法）变成表单的默认策略；简单主题（概率）可以声明 `defer = false`，保持“输入就出答案”。
2. **任务分段**（§5.5）：长计算不再冻结界面。
3. **步骤延迟生成**：`explain` 在第一次展开时才执行。很多答案的步骤用户根本不看。
4. **增量行重建**和**脏矩形重画**：编辑一个框时只重排这一行；光标闪动只重画输入框。
5. **图像**：采样结果按窗口缓存（2.x 已有录制回放）；编辑时用占位（2.4 已有）；自适应采样（陡峭处加密，平缓处减少）。
6. **预算测试**：每个主题的示例题在测试里统计 CAS 调用次数、采样次数，超过预算就失败（2.x 做过一次手工统计：314 → 33 次）。

## 9. 存储与迁移

```lua
saved = { schema = 3, problems = { … }, settings = { … }, next_id = 12 }
```

- `app/migrate.lua`：按 schema 版本逐级升级。`2 → 3`：解题器 id 映射到主题 id、旧字段映射到新字段（例如 `xmin`/`xmax` → `xwin`，`want = 'vx'` → `fn = 'vx'`，2.3 已经有类似的 `upgrade`）。映射表放在一个文件里，并有测试：每个 2.x 主题的示例题保存后，用 3.0 读回来，结果一致。
- 保存的东西只有字符串和数字；不保存计算结果。
- 展开状态、精确/小数选择随题目保存（重新打开时恢复）。2.x 的 `p.modes` 没有保存，是一个已知问题。
- 在 `rpn.tns` 里，rpnspire 的 `on.save` 把工具箱的状态放在 `vce` 字段下；3.0 保持这个嵌套方式，迁移代码同时处理两种文档。

## 10. 多语言

- 2.x：英文原文就是键，中文按原文或正则匹配。改一个英文字就丢翻译。
- 3.0：**消息 id + 参数**。

```lua
-- i18n/en.lua（进所有产物）
['kin.need'] = 'Not enough conditions to find {fn}: give {give}',
-- i18n/zh/kinematics.lua（只进 vce_zh）
['kin.need'] = '条件不够：求 {fn} 还要填 {give}',
```

- 双语显示规则不变（英文一行、中文一行；步骤只用英文）。
- 测试：每个 en 消息在 zh 里都有；每个 `{参数}` 两边一致；英文产物里没有中文字符。
- 迁移期间提供一个兼容函数，把 2.x 的英文原句查成 id，方便逐个主题搬。

## 11. 构建与发布

- 一个构建脚本产出：`vce.tns`、`vce_zh.tns`、`rpn.tns`，以及网站用的 bundle。
- **dev / release 两种构建**：dev 带调试面板、断言、详细日志；release 去掉 `debug/` 和断言（`--release` 时 entry 不 require 它们）。
- CI 检查：luacheck、`tools/arch_check.lua`（层次依赖）、体积预算（例如 `vce_zh.tns ≤ 300 KB`，按实测调整）、Lua 5.1 沙盒冒烟、英文产物无中文、测试、网站测试。
- 版本号仍然只有一个来源（`version.lua`），`changelog.json` 第一项必须一致。

## 12. 2.x 里可以直接复用的部分

| 2.x 模块 | 3.0 位置 | 处理方式 |
|---|---|---|
| `ui/mathbox.lua`（漂亮的数学排版） | `ui/mathbox.lua` | 基本照搬，加 key 化的缓存 |
| `ui/plot.lua` + 录制回放 | `ui/plot/*` | 拆成 spec/auto/draw/cache；auto_range 改成纯函数（返回窗口，不改 spec） |
| `views/graphview.lua` | `ui/viewer.lua` | 重写交互（多曲线、交点、区域），保留追踪/缩放代码 |
| `apps/vce/numeric.lua` | `cas/num.lua` | 照搬，加日志 |
| `cas.input`、记忆化规则 | `cas/input.lua`、`cas/engine.lua` | 照搬，补测试 |
| `views/sheet.lua` | `ui/sheet.lua` + `ui/rows/*` | 按行类型拆分渲染器；编辑模型保留（commit/to、占位） |
| 各解题器的数学 | `mathx/*` + `topics/*` | 搬数学部分，重写输出（Fact 代替 report 文本）；用 2.x 结果做对照测试 |
| `testcas.lua`（数值 CAS mock） | `plat/test` 的 CAS 后端之一 | 保留，另加“真机录制回放”后端 |
| 网站模拟器 host | `plat/web.lua` | 改成实现新的 host 接口 |
