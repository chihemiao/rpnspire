// The four recommended topics on the website. Each has an exam-style
// question, the way to do it by hand in the TI-Nspire Calculator app (cas:
// what to type and what the CAS returns) and the way to do it in the toolkit
// (app: key scripts played on the live screen). site/test/emu.test.mjs plays
// every app script and checks `expect` against the toolkit's answers.
//
// Key scripts: plain text is typed; {enter} {down} {up} {left} {right} {esc}
// {tab} are keys; {down*3} repeats. $…$ in text is maths (assets/timath.js).
// boxes: how many boxes and choices the toolkit needs for the question.
(function (root) {
  'use strict';

  const TUTORIALS = [
    {
      id: 'graph',
      solver: 'graph',
      boxes: 3,
      course: ['MM', 'SM'],
      title: { zh: '函数图像与特征', en: 'Function graph & features' },
      pitch: {
        zh: '输入 f(x)，自动画图并标出渐近线、驻点、拐点、截距，连步骤一起给你。',
        en: 'Type f(x): it draws the graph and marks asymptotes, turning points, inflection points and intercepts, with the working.',
      },
      question: {
        zh: '设 $f(x)=(x^2-3)/(x-2)$，$x≠2$。画出 $y=f(x)$ 的图像，标出所有渐近线、驻点和坐标轴截距。',
        en: 'Let $f(x)=(x^2-3)/(x-2)$, $x≠2$. Sketch the graph of $y=f(x)$, labelling all asymptotes, stationary points and axis intercepts.',
      },
      answer: {
        zh: '渐近线 $x=2$ 和 $y=x+2$；极大值点 $(1,2)$，极小值点 $(3,6)$；与 x 轴交于 $(−√(3),0)$、$(√(3),0)$，与 y 轴交于 $(0,3/2)$。',
        en: 'Asymptotes $x=2$ and $y=x+2$; local maximum $(1,2)$, local minimum $(3,6)$; x-intercepts $(−√(3),0)$ and $(√(3),0)$, y-intercept $(0,3/2)$.',
      },
      cas: [
        {
          entries: [['Define f(x)=(x^2-3)/(x-2)', 'Done']],
          zh: '先把函数存成 f(x)，后面每一步都要用。',
          en: 'Store the function as f(x); every later step uses it.',
        },
        {
          entries: [['propFrac(f(x))', '1/(x-2)+x+2']],
          zh: '化成真分式：分母 $x-2$ 给出竖直渐近线 $x=2$，剩下的 $x+2$ 给出斜渐近线 $y=x+2$。',
          en: 'Proper fraction: the denominator $x-2$ gives the vertical asymptote $x=2$; the rest, $x+2$, gives the oblique asymptote $y=x+2$.',
        },
        {
          entries: [['solve(derivative(f(x),x)=0,x)', 'x=1 or x=3']],
          zh: '导数等于 0，得到驻点的 x 坐标（d/dx 在 menu › Calculus 里）。',
          en: 'Set the derivative to 0 for the x-coordinates of the stationary points (d/dx is in menu › Calculus).',
        },
        {
          entries: [['f(1)', '2'], ['f(3)', '6']],
          zh: '代回 f(x) 得到 y 坐标。',
          en: 'Substitute back for the y-coordinates.',
        },
        {
          entries: [['derivative(f(x),x,2)|x=1', '−2'], ['derivative(f(x),x,2)|x=3', '2']],
          zh: '用二阶导判断：$−2<0$ → 极大值 $(1,2)$；$2>0$ → 极小值 $(3,6)$。',
          en: 'Second derivative test: $−2<0$ → local maximum $(1,2)$; $2>0$ → local minimum $(3,6)$.',
        },
        {
          entries: [['solve(f(x)=0,x)', 'x=−√(3) or x=√(3)'], ['f(0)', '3/2']],
          zh: '$f(x)=0$ 得到 x 截距，$f(0)$ 得到 y 截距。',
          en: '$f(x)=0$ gives the x-intercepts and $f(0)$ the y-intercept.',
        },
      ],
      casEnd: {
        zh: '最后还要打开 Graphs 页面画出 f(x) 和 $y=x+2$，再自己把这些点标上去。一共 9 条命令，还要记住 propFrac 和二阶导的写法。',
        en: 'Then open a Graphs page, plot f(x) and $y=x+2$ and mark every point yourself: 9 commands, and you must remember propFrac and the second-derivative syntax.',
      },
      app: [
        {
          keys: '1',
          zh: '在首页按 <kbd>1</kbd>，打开 Function graph（函数图像）。',
          en: 'On the home screen press <kbd>1</kbd> for Function graph.',
        },
        {
          keys: '(x^2-3)/(x-2){enter}',
          zh: '在 f(x) 里输入 <code>(x^2-3)/(x-2)</code>，按 <kbd>enter</kbd>。',
          en: 'Type <code>(x^2-3)/(x-2)</code> into f(x) and press <kbd>enter</kbd>.',
        },
        {
          keys: '-6{enter}8{enter}',
          zh: 'x 的范围填 −6 到 8（每格按 <kbd>enter</kbd>）。y 的范围可以不填。',
          en: 'Set x from −6 to 8 (<kbd>enter</kbd> after each). The y range can stay empty.',
        },
        {
          keys: '{down*9}',
          zh: '往下翻：图上已经标好渐近线（虚线）、极值点和截距。',
          en: 'Scroll down: the graph already shows the asymptotes (dashed), turning points and intercepts.',
        },
        {
          keys: '{down*3}',
          zh: '再往下是所有答案（绿色），按 <kbd>enter</kbd> 可在精确值和小数之间切换；最下面是步骤。',
          en: 'Below it are all the answers (green); <kbd>enter</kbd> switches exact ⇔ decimal. The working is underneath.',
        },
      ],
      appEnd: {
        zh: '只填 3 个格子，图像、答案和步骤一起出来。',
        en: 'Three boxes: the graph, the answers and the working appear together.',
      },
      expect: ['va=q9x=2', 'oa=q9y=q9x+2', 'max=pt(1,2)', 'min=pt(3,6)', 'xint=pt(−√(3),0)', 'yint=pt(0,3/2)'],
    },
    {
      id: 'revolution',
      solver: 'revolution',
      boxes: 6,
      course: ['MM', 'SM'],
      title: { zh: '面积与旋转体体积', en: 'Areas & volumes of revolution' },
      pitch: {
        zh: '面积、绕 x 轴或 y 轴的体积、弧长、表面积；范围可以是 x 或 y 的值，还能带字母常数（比如 a）。',
        en: 'Area, volume about the x- or y-axis, arc length and surface area; limits in x or y, even with a letter such as a.',
      },
      question: {
        zh: '曲线 $y=x^2$、y 轴和直线 $y=a$（$a>0$）围成的区域绕 y 轴旋转一周，所得旋转体的体积是 $8π$。求 $a$。',
        en: 'The region bounded by $y=x^2$, the y-axis and the line $y=a$, where $a>0$, is rotated about the y-axis. The volume of the solid is $8π$. Find $a$.',
      },
      answer: {
        zh: '$a=4$（顺便还得到面积 $16/3$、体积 $8π$）。',
        en: '$a=4$ (with the area $16/3$ and the volume $8π$ as well).',
      },
      cas: [
        {
          entries: [['solve(y=x^2,x)', 'x=−√(y) or x=√(y)']],
          zh: '绕 y 轴、对 y 积分，要先把 x 写成 y 的式子：这里取 $x=√(y)$。',
          en: 'Rotating about the y-axis means integrating in y, so first write x in terms of y: here $x=√(y)$.',
        },
        {
          entries: [['π*integral((√(y))^2,y,0,a)', '(π*a^2)/2']],
          zh: '体积公式 $V=π*integral(x^2,y,0,a)$：从 $y=0$ 积到 $y=a$。',
          en: 'Volume $V=π*integral(x^2,y,0,a)$, from $y=0$ to $y=a$.',
        },
        {
          entries: [['solve((π*a^2)/2=8*π,a)|a>0', 'a=4']],
          zh: '令体积等于 $8π$，加上条件 $a>0$ 解出 a。',
          en: 'Set the volume equal to $8π$ and solve with $a>0$.',
        },
      ],
      casEnd: {
        zh: '难点在于自己判断：绕哪条轴、对 x 还是 y 积分、x 要先用 y 表示，公式也要自己写对。',
        en: 'The hard part is deciding yourself: which axis, whether to integrate in x or y, rewriting x in terms of y, and writing the formula correctly.',
      },
      app: [
        {
          keys: '5',
          zh: '在首页按 <kbd>5</kbd>，打开 Area/volume（面积/体积）。曲线类型保持 y = f(x)。',
          en: 'On the home screen press <kbd>5</kbd> for Area/volume. Keep the curve type y = f(x).',
        },
        {
          keys: '{down}x^2{enter}{enter}',
          zh: '按 <kbd>▼</kbd> 到 f(x)，输入 <code>x^2</code> 按 <kbd>enter</kbd>；第二条曲线不用填，再按 <kbd>enter</kbd>。',
          en: 'Press <kbd>▼</kbd> to f(x), type <code>x^2</code> and <kbd>enter</kbd>; leave the second curve empty and press <kbd>enter</kbd>.',
        },
        {
          keys: '{right}{down}',
          zh: '“Limits are” 按 <kbd>▶</kbd> 选 y values（范围是 y 的值），再按 <kbd>▼</kbd>。',
          en: 'At “Limits are” press <kbd>▶</kbd> for y values, then <kbd>▼</kbd>.',
        },
        {
          keys: '0{enter}a{enter}',
          zh: 'y 从 0 到 a：上限直接输入字母 <code>a</code>。',
          en: 'y from 0 to a: type the letter <code>a</code> as the upper limit.',
        },
        {
          keys: '{right}{down}',
          zh: '“Rotate about” 按 <kbd>▶</kbd> 选 y-axis（绕 y 轴），再按 <kbd>▼</kbd>。',
          en: 'At “Rotate about” press <kbd>▶</kbd> for the y-axis, then <kbd>▼</kbd>.',
        },
        {
          keys: 'V=8pi{enter}',
          zh: '在 given（已知）里输入 <code>V=8pi</code> 按 <kbd>enter</kbd>：a = 4，图和步骤一起出来。',
          en: 'In “given” type <code>V=8pi</code> and press <kbd>enter</kbd>: a = 4, with the graph and the working.',
        },
      ],
      appEnd: {
        zh: '不用自己变形、也不用记公式：选好轴和范围就行。',
        en: 'No rearranging and no formula to remember: pick the axis and the limits.',
      },
      expect: ['param_a=4', 'vol=8*π', 'area=16/3'],
    },
    {
      id: 'kinematics',
      solver: 'kinematics',
      boxes: 6,
      course: ['SM'],
      title: { zh: '运动学（变加速度）', en: 'Kinematics (variable acceleration)' },
      pitch: {
        zh: '给出 a(t)、a(v)、a(x)、v(t)、v(x) 或 x(t)，自动选对公式，求 t、x、v、a；要 v(x) 这类指定公式就在“求公式”里选；条件不够时会告诉你还要填什么。',
        en: 'Give a(t), a(v), a(x), v(t), v(x) or x(t): it picks the right form and finds t, x, v and a, or one formula such as v(x) from the Formula row, and tells you which known value is missing.',
      },
      question: {
        zh: '一个质点沿直线运动，加速度 $a=−(1+v^2)$ m/s²，v m/s 是它在 t 秒时的速度。开始时质点在原点，速度为 1 m/s。求它停下来所用的时间，以及这段时间里走过的距离。',
        en: 'A particle moves in a straight line with acceleration $a=−(1+v^2)$ m/s², where v m/s is its velocity at time t s. Initially it is at the origin with velocity 1 m/s. Find the time it takes to come to rest and the distance it travels in that time.',
      },
      answer: {
        zh: '$t=π/4$ s ≈ 0.785 s，距离 $ln(2)/2$ m ≈ 0.347 m。',
        en: '$t=π/4$ s ≈ 0.785 s; distance $ln(2)/2$ m ≈ 0.347 m.',
      },
      cas: [
        {
          entries: [['integral(1/(−(1+v^2)),v,1,0)', 'π/4']],
          zh: 'a 是 v 的函数，求时间要用 $dt/dv=1/a$：从 $v=1$ 积到 $v=0$。',
          en: 'a is a function of v, so for time use $dt/dv=1/a$, from $v=1$ to $v=0$.',
        },
        {
          entries: [['integral(v/(−(1+v^2)),v,1,0)', 'ln(2)/2']],
          zh: '求距离要换成 $v*dv/dx=a$，也就是 $dx/dv=v/a$。',
          en: 'For distance switch to $v*dv/dx=a$, that is $dx/dv=v/a$.',
        },
        {
          entries: [['approx(π/4)', '0.785398'], ['approx(ln(2)/2)', '0.346574']],
          zh: '要小数时再 approx（或按 <kbd>ctrl</kbd>+<kbd>enter</kbd>）。',
          en: 'For decimals use approx (or <kbd>ctrl</kbd>+<kbd>enter</kbd>).',
        },
      ],
      casEnd: {
        zh: '难点是自己判断该用 dt/dv = 1/a 还是 v·dv/dx = a，还要把积分上下限写对方向。',
        en: 'The hard part is choosing between dt/dv = 1/a and v·dv/dx = a, and getting the limits the right way round.',
      },
      app: [
        {
          keys: '8',
          zh: '在首页按 <kbd>8</kbd>，打开 Kinematics（运动学）。',
          en: 'On the home screen press <kbd>8</kbd> for Kinematics.',
        },
        {
          keys: '{right}{down}',
          zh: '“Given” 按 <kbd>▶</kbd> 选 a = f(v)，再按 <kbd>▼</kbd>。',
          en: 'At “Given” press <kbd>▶</kbd> for a = f(v), then <kbd>▼</kbd>.',
        },
        {
          keys: '-(1+v^2){enter}',
          zh: '输入 a(v)：<code>-(1+v^2)</code>，按 <kbd>enter</kbd>。',
          en: 'Type a(v): <code>-(1+v^2)</code> and press <kbd>enter</kbd>.',
        },
        {
          keys: '0{enter}0{enter}1{enter}',
          zh: '开始时的状态：t0 = 0，x0 = 0，v0 = 1。',
          en: 'The starting state: t0 = 0, x0 = 0, v0 = 1.',
        },
        {
          keys: '{enter*3}{down*2}',
          zh: '接下来三格这题用不到，按 <kbd>enter</kbd> 跳过；Formula（求公式）保持 none，Find 保持 everything（全部求），按两次 <kbd>▼</kbd>。',
          en: 'Skip the next three boxes with <kbd>enter</kbd>; keep Formula = none and Find = everything, and press <kbd>▼</kbd> twice.',
        },
        {
          keys: 'v=0{enter}',
          zh: '在 when（何时）里输入 <code>v=0</code> 按 <kbd>enter</kbd>：t = π/4，x = ln(2)/2。',
          en: 'In “when” type <code>v=0</code> and press <kbd>enter</kbd>: t = π/4, x = ln(2)/2.',
        },
        {
          keys: '{down*8}',
          zh: '往下翻是步骤：写明用了 dt/dv = 1/a 和 v·dv/dx = a，以及定义域。',
          en: 'Scroll down for the working: it states dt/dv = 1/a and v·dv/dx = a, and the domains.',
        },
      ],
      appEnd: {
        zh: '不用自己决定用哪个公式，步骤里会写清楚，照抄就是评分要的格式。',
        en: 'You never choose the form yourself, and the working is written the way the marking scheme expects.',
      },
      expect: ['q_t=π/4', 'q_x=ln(2)/2', 'q_a=−1'],
    },
    {
      id: 'suvat',
      solver: 'suvat',
      boxes: 3,
      course: ['SM'],
      title: { zh: '匀加速运动 SUVAT', en: 'Constant acceleration (SUVAT)' },
      pitch: {
        zh: 's、u、v、a、t 任给三个，自动选公式求另外两个，并写出用的是哪个公式。',
        en: 'Give any three of s, u, v, a, t: it picks the formulas, finds the other two and shows which formula it used.',
      },
      question: {
        zh: '一辆汽车以 20 m/s 的速度行驶，刹车后做匀减速运动，行驶 50 m 后停下。求加速度和刹车所用的时间。',
        en: 'A car travelling at 20 m/s brakes with constant deceleration and stops after 50 m. Find its acceleration and the time it takes to stop.',
      },
      answer: {
        zh: '$a=−4$ m/s²（减速度 4 m/s²），$t=5$ s。',
        en: '$a=−4$ m/s² (a deceleration of 4 m/s²), $t=5$ s.',
      },
      cas: [
        {
          entries: [['solve(0^2=20^2+2*a*50,a)', 'a=−4']],
          zh: '已知 s、u、v 求 a：要自己选出 $v^2=u^2+2*a*s$。',
          en: 'Knowing s, u and v, you must pick $v^2=u^2+2*a*s$ for a.',
        },
        {
          entries: [['solve(0=20+(−4)*t,t)', 't=5']],
          zh: '再用 $v=u+a*t$ 求 t。',
          en: 'Then $v=u+a*t$ for t.',
        },
      ],
      casEnd: {
        zh: '要背 5 个 SUVAT 公式，每次选对一个，代入时还不能抄错数。',
        en: 'You need the five SUVAT formulas, the right one each time, and no copying mistakes.',
      },
      app: [
        {
          keys: '7',
          zh: '在首页按 <kbd>7</kbd>，打开 SUVAT（匀加速）。',
          en: 'On the home screen press <kbd>7</kbd> for SUVAT.',
        },
        {
          keys: '50{enter}20{enter}0{enter}',
          zh: 's = 50，u = 20，v = 0，每格按 <kbd>enter</kbd>。a 和 t 不知道，空着。',
          en: 's = 50, u = 20, v = 0, <kbd>enter</kbd> after each. Leave a and t empty.',
        },
        {
          keys: '{down*3}',
          zh: '答案已经出来：a = −4，t = 5；下面的步骤写明了用的公式。',
          en: 'The answers are there: a = −4, t = 5; the working names each formula.',
        },
      ],
      appEnd: {
        zh: '三个数填进去就行，不用选公式。',
        en: 'Three numbers in, no formula to choose.',
      },
      expect: ['a=−4', 't=5'],
    },
  ];

  if (typeof module !== 'undefined' && module.exports) module.exports = TUTORIALS;
  else root.TUTORIALS = TUTORIALS;
})(typeof globalThis !== 'undefined' ? globalThis : this);
