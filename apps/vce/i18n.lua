-- Chinese/English (中英双语) text for the VCE toolkit.
--
-- I.lang is 'en' (English) or 'bi' (bilingual). Working steps stay in English
-- (the language of VCE exams); the interface, field hints, result terms,
-- notes and help are shown in both languages in bilingual mode.
local I = {}

I.lang = 'en'
I.default = 'en'

function I.bi()
   return I.lang == 'bi'
end

-- Interface strings: English -> Chinese
I.UI = {
   ['Specialist Maths toolkit'] = '专项数学工具箱',
   ['menu: options'] = '菜单',
   ['Probability'] = '概率与统计',
   ['Mechanics'] = '力学',
   ['Recent'] = '最近',
   ['More'] = '更多',
   ['History'] = '历史记录',
   ['all problems, tags, search'] = '全部题目、标签、搜索',
   ['Help & keys'] = '帮助与按键',
   ['Self-test'] = '自检',
   ['check the solvers with this calculator\'s CAS'] = '用本机 CAS 检查各解题器',
   ['Results'] = '结果',
   ['Working'] = '步骤',
   ['Help'] = '帮助',
   ['Error'] = '错误',
   ['Yes'] = '是',
   ['No'] = '否',
   ['(empty)'] = '（空）',
   ['No problems yet'] = '暂无题目',
   ['problems'] = '题',
   ['running...'] = '运行中…',
   ['checks passed'] = '项通过',
   ['Select a result first'] = '请先选中一个结果',
   ['Select an input field first'] = '请先选中一个输入框',
   ['No functions defined in this problem (e.g. f11(x):=...)'] = '本题中没有定义函数（例如 f11(x):=…）',
   ['Could not store'] = '无法存储',
   ['Tag / label (e.g. 2023 E2 Q5b)'] = '标签（如 2023 E2 Q5b）',
   ['to variable'] = '存入变量',
   -- context menu
   ['Exact ⇔ decimal'] = '精确值 ⇔ 小数',
   ['Copy value'] = '复制数值',
   ['Store to variable...'] = '存入变量…',
   ['Send to RPN stack'] = '送到 RPN 栈',
   ['Insert document function...'] = '插入文档中的函数…',
   ['Insert symbol...'] = '插入符号…',
   ['Clear field'] = '清空此格',
   ['Copy line'] = '复制此行',
   ['Tag problem...'] = '给题目加标签…',
   -- toolpalette
   ['Problem'] = '题目',
   ['Solvers'] = '解题器',
   ['Result'] = '结果',
   ['Settings'] = '设置',
   ['Home'] = '主页',
   ['New (same type)'] = '新建同类题',
   ['Duplicate'] = '复制本题',
   ['Tag / label...'] = '标签…',
   ['Clear inputs'] = '清空输入',
   ['Previous problem'] = '上一题',
   ['Next problem'] = '下一题',
   ['Delete problem'] = '删除本题',
   ['Back to rpnspire'] = '返回 rpnspire',
   ['Open history'] = '打开历史记录',
   ['Search (type in history)'] = '搜索（在历史中打字）',
   ['Copy value / line'] = '复制数值/行',
   ['Store value to variable...'] = '数值存入变量…',
   ['All exact'] = '全部精确值',
   ['All decimal'] = '全部小数',
   ['decimal places'] = '位小数',
   ['Font small'] = '小字体',
   ['Font normal'] = '中字体',
   ['Font large'] = '大字体',
   ['Language: English'] = '语言：英文',
   ['Language: Chinese + English'] = '语言：中英双语',
}

-- Hint bar text (bilingual: Chinese with English key names)
I.HINTS = {
   input = 'enter 求解 · tab 下一格 · esc 主页 · ctrl+menu 插入',
   choice = 'left/right 切换选项 · menu 菜单',
   result = 'enter/点击 精确⇔小数 · ctrl+C 复制 · n/p 上/下一题',
   step = 'up/down 滚动 · right 长行 · t 标签 · h 历史',
   link = 'enter 打开 · 数字键 快速打开',
   math = 'left/right 滚动',
   history = 'enter 打开 · 打字 搜索 · del 删除 · esc 主页',
   default = 'menu 菜单 · esc 返回',
}

-- Solver titles: { short, title, description }
I.SOLVERS = {
   normal = { '正态', '正态分布', '求概率、反正态求 k、求 μ 或 σ、面积求 x' },
   normal2 = { '正态求μσ', '正态：两个条件求 μ、σ', '如 P(X<60)=0.9, P(X>40)=0.2' },
   binomial = { '二项', '二项分布', 'Bi(n,p)：P(X=k)、P(X≥k)、求 n 或 p、均值/方差' },
   discrete = { '离散', '离散型随机变量', '分布列含未知数 k：E(X)、Var(X)、P(事件)' },
   pdf = { '密度函数', '概率密度函数', '求 k、E(X)、Var(X)、中位数、众数、P(a<X<b)、面积求 x' },
   lincomb = { '线性组合', '随机变量的线性组合', 'aX+bY+c、X1+X2+…的均值方差；正态时求概率' },
   sampling = { '抽样/置信区间', '样本均值与置信区间', 'X̄ 的分布、误差界、置信区间、样本量' },
   hyptest = { '假设检验', '假设检验（均值）与两类错误', 'p 值、是否拒绝 H0、临界值、第一/二类错误' },
   suvat = { '匀加速', '匀加速运动', 's、u、v、a、t 任给三个（可用其他页面的 f11(2)）' },
   kinematics = { '运动学', '运动学：a(t)、a(v)、a(x)、v(t)、v(x)、x(t)', '积分/求导、由条件定常数、求 t、x、v' },
}

-- Field labels/hints. label: appended to the original label; hint: replaces
-- the hint (written bilingual already).
I.FIELDS = {
   normal = {
      mu = { hint = 'mean 均值' },
      sd = { hint = 'standard deviation 标准差' },
      var = { hint = 'variance 方差（代替 σ）' },
      event = { label = '事件', hint = '事件 45<X<55  X>k  X>60|X>50' },
      p = { label = '概率', hint = '事件概率（用于求 k、μ、σ）' },
      q = { hint = 'area 面积，如 0.99 → x' },
   },
   normal2 = {
      e1 = { label = '事件1' }, p1 = { label = '概率1' },
      e2 = { label = '事件2' }, p2 = { label = '概率2' },
   },
   binomial = {
      n = { hint = 'trials 试验次数' },
      p = { hint = 'P(success) 成功概率' },
      mean = { hint = 'mean 均值 np' },
      var = { hint = 'variance 方差 np(1-p)' },
      sd = { hint = 'standard deviation 标准差' },
      event = { label = '事件', hint = '事件 X=3  X≥2  2≤X<5  X>2|X≥1' },
      pr = { label = '概率', hint = '≥0.95 求最小 n；0.1 求 p' },
   },
   discrete = {
      x = { hint = 'values 取值: 0,1,2,3' },
      px = { hint = 'probs 概率: 0.1,k,2k,0.3' },
      mean = { hint = '已知时填（第二个未知数）' },
      event = { label = '事件', hint = '事件 X≥2  X<3|X>0' },
   },
   pdf = {
      f1 = { hint = '3/8*x^2   k*x*(2-x)' },
      a1 = { label = '从', hint = 'lower end 定义域下端' },
      b1 = { label = '到', hint = 'upper end 上端（可填 inf）' },
      f2 = { label = '第2段', hint = '可选：第二段' },
      a2 = { label = '从' }, b2 = { label = '到' },
      f3 = { label = '第3段', hint = '可选：第三段' },
      a3 = { label = '从' }, b3 = { label = '到' },
      mean = { hint = '已知时填（第二个未知数）' },
      event = { label = '事件', hint = '事件 X<1  0.5<X<1.5  X>k' },
      pr = { label = '概率', hint = '事件概率（用于求 k）' },
      q = { hint = 'area 面积，如 0.99 → x' },
   },
   lincomb = {
      mx = { hint = 'mean of X  X 的均值' },
      sx = { hint = 'SD of X 标准差（或填下方方差）' },
      my = { hint = 'mean of Y  Y 的均值（若有）' },
      sy = { hint = 'SD of Y 标准差（或填下方方差）' },
      comb = { hint = '2X-3Y+4   X1+X2+X3   3X' },
      normal = { label = '正态?' },
      event = { label = '事件', hint = '事件 W>0  X1+X2>2Y' },
   },
   sampling = {
      mu = { hint = 'population mean 总体均值' },
      sd = { hint = 'population/sample SD 标准差' },
      n = { hint = 'sample size 样本量' },
      xbar = { hint = 'sample mean 样本均值' },
      c = { label = '置信水平', hint = 'confidence level 置信水平 95 或 0.95' },
      z = { hint = '可选：如 z = 1.96' },
      e = { label = '误差界', hint = 'margin of error 误差界' },
      w = { label = '宽度', hint = 'width of CI 区间宽度 (=2E)' },
      lo = { label = '下限', hint = '已知区间 (a, b)' },
      hi = { label = '上限' },
      event = { label = '事件', hint = '事件 Xbar>52  49<Xbar<51' },
   },
   hyptest = {
      mu0 = { hint = 'H0: μ = μ0  原假设' },
      h1 = { label = '备择' },
      sd = { hint = 'population SD 总体标准差' },
      n = { hint = 'sample size 样本量' },
      xbar = { hint = 'observed sample mean 样本均值' },
      alpha = { hint = 'significance 显著性水平（默认 0.05）' },
      c = { label = '临界', hint = '决策规则：x̄ 超过 c 则拒绝' },
      mu1 = { label = '真实', hint = 'actual mean 真实均值（第二类错误）' },
   },
   suvat = {
      s = { hint = 'displacement 位移' },
      u = { hint = 'initial velocity 初速度' },
      v = { hint = 'final velocity 末速度' },
      a = { hint = 'acceleration 加速度（如 -9.8）' },
      t = { hint = 'time 时间' },
   },
   kinematics = {
      type = { label = '已知' },
      f = { hint = '例 6t   -(1+v^2)/10   f11(t)' },
      t0 = { hint = '已知值对应的时刻（默认 0）' },
      x0 = { hint = 'position 位置 (t0 时)' },
      v0 = { hint = 'velocity 速度 (t0 时)' },
      c2 = { label = '另一条件', hint = 'x(2)=5   v(1)=3   v=2,x=1' },
      find = { label = '求何时', hint = 't=3   v=0   x=5   a=0' },
      t1 = { label = '从', hint = 'displacement 位移 / distance 路程' },
      t2 = { label = '到' },
   },
}

-- Choice option text in bilingual mode
I.OPTIONS = {
   lincomb = { normal = { yes = 'yes 是（W 为正态）', no = 'no 否' } },
}

-- Result terms: { English, Chinese }
I.TERMS = {
   _ = {
      p = { 'probability', '概率' }, prob = { 'probability', '概率' },
      mean = { 'mean (expected value)', '均值（期望）' },
      var = { 'variance', '方差' }, sd = { 'standard deviation', '标准差' },
      median = { 'median', '中位数' }, mode = { 'mode', '众数' },
      k = { 'unknown value', '未知数' }, k2 = { 'second unknown', '第二个未知数' },
      mu = { 'mean', '均值' }, q = { 'value for the area', '面积对应的 x' },
      lo = { 'lower bound', '下限' }, hi = { 'upper bound', '上限' },
      n = { 'number of trials', '试验次数' },
      ex2 = { 'E(X squared)', 'X² 的期望' },
      probs = { 'probability distribution', '概率分布' },
      z = { 'z value', 'z 值' },
   },
   normal = { k = { 'unknown bound', '未知界限' } },
   binomial = { p = { 'probability of success', '成功概率' }, p2 = { 'second value of p', 'p 的第二个值' } },
   pdf = { k = { 'unknown constant', '未知常数' } },
   sampling = {
      se = { 'standard error', '标准误差' }, e = { 'margin of error', '误差界' },
      lo = { 'CI lower bound', '置信区间下限' }, hi = { 'CI upper bound', '置信区间上限' },
      n = { 'sample size (rounded up)', '样本量（向上取整）' }, c = { 'confidence level', '置信水平' },
      xbar = { 'sample mean', '样本均值' }, sd = { 'standard deviation', '标准差' },
      z = { 'critical z', '临界 z 值' },
   },
   hyptest = {
      se = { 'standard error', '标准误差' }, z = { 'test statistic', '检验统计量' },
      p = { 'p-value', 'p 值' }, decision = { 'conclusion', '结论' },
      c = { 'critical value', '临界值' }, c1 = { 'lower critical value', '下临界值' },
      c2 = { 'upper critical value', '上临界值' },
      type1 = { 'Type I error', '第一类错误' }, type2 = { 'Type II error', '第二类错误' },
      power = { 'power', '检验功效' },
   },
   suvat = {
      s = { 'displacement', '位移' }, u = { 'initial velocity', '初速度' },
      v = { 'final velocity', '末速度' }, a = { 'acceleration', '加速度' }, t = { 'time', '时间' },
   },
   kinematics = {
      xt = { 'position', '位置' }, vt = { 'velocity', '速度' }, at = { 'acceleration', '加速度' },
      vx = { 'velocity', '速度' }, v2x = { 'velocity squared', '速度平方' }, ax = { 'acceleration', '加速度' },
      av = { 'acceleration', '加速度' }, tv = { 'time', '时间' }, xv = { 'position', '位置' },
      tx = { 'time', '时间' }, vterm = { 'terminal velocity', '极限（终端）速度' },
      q_t = { 'time', '时间' }, q_x = { 'position', '位置' }, q_v = { 'velocity', '速度' },
      q_a = { 'acceleration', '加速度' },
      disp = { 'displacement', '位移' }, dist = { 'distance travelled', '路程' },
      avgv = { 'average velocity', '平均速度' }, avgs = { 'average speed', '平均速率' },
   },
   lincomb = { mean = { 'mean of W', 'W 的均值' }, var = { 'variance of W', 'W 的方差' },
               sd = { 'SD of W', 'W 的标准差' } },
}

-- Notes and errors: Lua pattern -> Chinese (captures as %1, %2)
I.NOTES = {
   { '^Enter (.+) and any known values$', '输入 %1 和已知值' },
   { '^Enter any three of s, u, v, a, t$', '输入 s、u、v、a、t 中任意三个' },
   { '^Enter two of n, p, E%(X%), Var%(X%)$', '输入 n、p、E(X)、Var(X) 中任意两个' },
   { '^Enter an event, e%.g%. (.+)$', '请输入事件，例如 %1' },
   { '^Enter Pr %(probability of the event%)$', '请输入概率 Pr（事件的概率）' },
   { '^Enter the probability Pr to find (.+)$', '请输入概率 Pr 以求 %1' },
   { '^Enter Pr to find (.+)$', '请输入概率 Pr 以求 %1' },
   { '^Enter f%(x%) and its domain$', '请输入 f(x) 及其定义域' },
   { '^Enter the domain of piece (.+)$', '请输入第 %1 段的定义域' },
   { '^Enter the values x and their probabilities$', '请输入取值 x 及其概率' },
   { '^Enter two events with their probabilities$', '请输入两个事件及其概率' },
   { '^Enter the combination W, e%.g%. (.+)$', '请输入组合 W，例如 %1' },
   { '^Enter v0 %(and x0%) to integrate$', '请输入 v0（和 x0）以便积分' },
   { '^Enter (.+)$', '请输入 %1' },
   { '^Need the same number of x values %((%d+)%) and probabilities %((%d+)%)$', 'x 取值个数 (%1) 与概率个数 (%2) 必须相同' },
   { '^Need v at a known x to find c$', '需要已知某 x 处的 v 才能求 c' },
   { '^Need x at a known t to find t%(x%) and x%(t%)$', '需要已知某 t 处的 x 才能求 t(x) 和 x(t)' },
   { '^Need v%(t%) for displacement over a time interval$', '求时间段内的位移需要 v(t)' },
   { '^Need (.+) at a known (.+) to find c for (.+)$', '需要已知某 %2 处的 %1 才能求 %3 中的 c' },
   { '^Need (.+) to find (.+)$', '需要 %1 才能求 %2' },
   { '^Need (.+) for (.+)$', '%2 需要 %1' },
   { '^Need (.+)$', '需要 %1' },
   { '^Could not solve for the two unknowns$', '无法求出两个未知数' },
   { '^Could not solve for (.+)$', '无法求出 %1' },
   { '^Could not find (.+)$', '无法求出 %1' },
   { '^No (.+), (.+): using Z ~ N%(0, 1%)$', '未给 %1、%2：按标准正态 Z ~ N(0, 1) 计算' },
   { '^No value of (.+) gives valid probabilities$', '没有使概率有效的 %1 值' },
   { '^No value of (.+) makes f a valid pdf$', '没有使 f 成为概率密度函数的 %1 值' },
   { '^No valid solution for (.+)$', '%1 没有有效解' },
   { '^No solution for p in %(0, 1%)$', '在 (0, 1) 内 p 无解' },
   { '^No n .+ 2000 satisfies the condition$', '2000 以内没有满足条件的 n' },
   { '^Two unknowns: use (.+)$', '有两个未知数：请用“%1”' },
   { '^Two values of p; using p = (.+) %(enter p to choose%)$', 'p 有两个值；当前用 p = %1（可手动输入 p 选择）' },
   { '^(%d+) solutions: choose the one that fits the question$', '有 %1 组解：选择符合题意的一组' },
   { '^All five values are consistent$', '五个量相互一致' },
   { '^Given values are inconsistent with (.+)$', '已知值与 %1 不一致' },
   { '^Too many unknowns.*$', '未知数太多（第二个未知数需给 E(X)）' },
   { '^Total area = (.+) %(not 1%): not a pdf$', '总面积 = %1（不是 1）：不是概率密度函数' },
   { '^Probabilities sum to (.+), not 1$', '概率之和为 %1，不是 1' },
   { '^Probabilities must be numbers$', '概率必须是数' },
   { '^Probabilities need X and Y normal$', '求概率需要 X、Y 为正态' },
   { '^Probability must be between 0 and 1$', '概率必须在 0 与 1 之间' },
   { '^P%(X=(.+)%) is not in %[0, 1%]$', 'P(X=%1) 不在 [0, 1] 内' },
   { '^x values must be numbers$', 'x 取值必须是数' },
   { '^n must be a whole number$', 'n 必须是整数' },
   { '^Domain ends must be numbers$', '定义域端点必须是数' },
   { '^Use X and Y .*$', '请用 X 和 Y（独立副本用 X1, X2, …）' },
   { '^Conditional events need (.+) and (.+)$', '条件事件需要 %1 和 %2' },
   { '^Area .+ x needs (.+) and (.+)$', '面积求 x 需要 %1 和 %2' },
   { '^Displacement over time needs v%(t%).*$', '时间段位移需要 v(t)；可用“求何时”填 t=…' },
   { '^Find: use t=3, v=0, x=5 or a=0$', '求何时：请填 t=3、v=0、x=5 或 a=0' },
   { '^Not enough information to find when (.+)$', '信息不足，无法求 %1 的时刻' },
   { '^(.+) must be positive: check the event and Pr$', '%1 必须为正：请检查事件和概率' },
   { '^(.+) is not positive: check events/probabilities$', '%1 不为正：请检查事件/概率' },
   { '^Mean/variance: (.+)$', '均值/方差：%1' },
   { '^Error: (.+)$', '错误：%1' },
   -- event parser
   { '^Event needs .+$', '事件需要 <、>、≤、≥ 或 =' },
   { '^Too many relations in event$', '事件中的不等号太多' },
   { '^Cannot find the random variable %(use X%)$', '找不到随机变量（请用 X）' },
   { '^Missing value in event$', '事件中缺少数值' },
   { '^Use the form a < X < b$', '请用 a < X < b 的形式' },
   { '^Only one condition | allowed$', '只能有一个条件 |' },
   { '^Event (%d+) must be X<k or X>k$', '事件%1 必须是 X<k 或 X>k' },
   { '^Cannot evaluate (.+)$', '无法计算 %1' },
}

-- Working-step section headings: pattern -> Chinese
I.SECTIONS = {
   { '^Percentile$', '分位数' },
   { '^Probability$', '概率' },
   { '^Area .+ x$', '面积求 x' },
   { '^When (.+)$', '当 %1 时' },
   { '^From t = (.+) to t = (.+)$', '时间段 %1 → %2' },
}

local function apply(list, text)
   for _, p in ipairs(list) do
      local zh, n = text:gsub(p[1], p[2], 1)
      if n > 0 then return zh end
   end
end

-- Bilingual "English 中文" for a UI string (English only when not bilingual)
function I.t(en, sep)
   if I.lang ~= 'bi' then return en end
   local zh = I.UI[en]
   if not zh then return en end
   return en .. (sep or ' ') .. zh
end

-- Chinese text when bilingual (falls back to English)
function I.z(en)
   if I.lang ~= 'bi' then return en end
   return I.UI[en] or en
end

function I.hint(kind, en)
   if I.lang ~= 'bi' then return en end
   return I.HINTS[kind] or en
end

-- Solver title/short/description
function I.solver(s)
   local zh = I.SOLVERS[s.id]
   if I.lang ~= 'bi' or not zh then
      return s.title, s.short, s.desc
   end
   return s.title .. ' ' .. zh[2], s.short .. ' ' .. zh[1], zh[3]
end

-- Field label and hint
function I.field(sid, f, label, hint)
   if I.lang ~= 'bi' then return label, hint end
   local t = I.FIELDS[sid] and I.FIELDS[sid][f.id]
   if not t then return label, hint end
   if t.label then label = label .. ' ' .. t.label end
   if t.hint then hint = t.hint end
   return label, hint
end

function I.option(sid, fid, key, text)
   if I.lang ~= 'bi' then return text end
   local o = I.OPTIONS[sid] and I.OPTIONS[sid][fid]
   return o and o[key] or text
end

-- Bilingual term for a result key (nil in English mode)
function I.term(sid, key)
   if I.lang ~= 'bi' or not key then return nil end
   local function lookup(k)
      return (I.TERMS[sid] and I.TERMS[sid][k]) or I.TERMS._[k]
   end
   local t = lookup(key) or lookup((key:gsub('%d+$', '')))
   if not t then return nil end
   return t[1] .. ' ' .. t[2]
end

-- Note text: English plus Chinese translation on a new line
function I.note(text)
   if I.lang ~= 'bi' or not text then return text end
   local plain = text:gsub('`', '')
   local zh = apply(I.NOTES, plain)
   if not zh then return text end
   return text .. '\n' .. zh
end

-- Section heading inside the working
function I.section(text)
   if I.lang ~= 'bi' or not text then return text end
   local zh = apply(I.SECTIONS, text)
   if not zh then return text end
   return text .. '  ' .. zh
end

-- Help text (English, Chinese) pairs
I.HELP = {
   { 'header', 'Using a solver', '使用解题器' },
   { 'text', 'Type the values you know into the fields and press enter: everything that can be worked out is shown under Results, with the Working underneath (written the way VCE marking expects).',
     '在各格输入已知量后按 enter：能算出的都会显示在“结果”中，下方的“步骤”按 VCE 评分要求书写（步骤保持英文）。' },
   { 'text', 'Leave unknowns empty. Events are typed like the question: `45<X<55`, X>k (unknown k), X≥3, X>2|X≥1 (conditional).',
     '未知量留空。事件照题目输入：45<X<55、X>k（k 未知）、X≥3、X>2|X≥1（条件概率）。' },
   { 'text', 'Use functions from other pages of the same problem, e.g. a(t) = f11(t) or u = f11(2). ctrl+menu on a field lists them.',
     '可以使用同一问题中其他页面定义的函数，如 a(t) = f11(t) 或 u = f11(2)。在输入格上按 ctrl+menu 可列出这些函数。' },
   { 'header', 'Keys', '按键' },
   { 'text', 'up/down: move · tab / shift+tab: next/previous field · enter: solve and go to next field',
     '上/下：移动 · tab / shift+tab：下一格/上一格 · enter：求解并跳到下一格' },
   { 'text', 'On a result: enter or click switches exact ⇔ decimal; left/right also switch or scroll long answers.',
     '在结果上：enter 或点击切换 精确值 ⇔ 小数；左右键也可切换或滚动长答案。' },
   { 'text', 'On results/working: n / p next or previous problem, t tag, h history, d all decimal, e all exact.',
     '在结果/步骤上：n / p 下一题/上一题，t 标签，h 历史，d 全部小数，e 全部精确值。' },
   { 'text', 'ctrl+C copies the selected value or working line. menu opens the toolbar menu (new problem, tag, settings). ctrl+menu opens the context menu.',
     'ctrl+C 复制选中的数值或步骤行。menu 打开菜单（新建、标签、设置）。ctrl+menu 打开快捷菜单。' },
   { 'header', 'Tips', '提示' },
   { 'text', 'Decimal places: menu > Settings. Answers are rounded only for display; values keep full precision.',
     '小数位数：menu › 设置。只在显示时四舍五入，内部保持全精度。' },
   { 'text', 'Kinematics: pick what is given (a(t), a(v), a(x), v(t), v(x), v²(x), x(t)), enter t0, x0, v0 (one known state) and optionally a second condition like x(2)=5. "Find when" accepts t=3, v=0, x=5 or a=0.',
     '运动学：选择已知类型（a(t)、a(v)、a(x)、v(t)、v(x)、v²(x)、x(t)），输入 t0、x0、v0（一个已知状态），可再加一个条件如 x(2)=5。“求何时”可填 t=3、v=0、x=5 或 a=0。' },
   { 'text', 'Run Self-test once on your calculator to check the solvers with its CAS.',
     '请在你的计算器上运行一次“自检”，用本机 CAS 检查各解题器。' },
   { 'text', 'Language: menu > Settings > Language.', '语言：menu › 设置 › 语言。' },
}

return I
