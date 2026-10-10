-- Language support for the VCE toolkit.
--
-- I.lang is 'en' (English) or 'bi' (bilingual Chinese + English). The Chinese
-- text is in apps/vce/i18n_zh.lua, which only the bilingual document
-- (vce_zh.lua) loads with I.install; without it the toolkit is English only
-- and has no language setting, and its documents carry no Chinese text.
-- Working steps stay in English (the language of VCE exams); in bilingual
-- mode the interface, field hints, result terms, notes and help are shown in
-- both languages.
local I = {}

I.lang = 'en'
I.default = 'en'
I.has_zh = false

-- Tables from i18n_zh (empty when English only):
--   UI       interface strings: English -> Chinese
--   HINTS    hint bar text by kind
--   SOLVERS  solver id -> { short, title, description }
--   BLURBS   solver id -> short home-screen line
--   FIELDS   solver id -> field id -> { label (appended), hint (replaces) }
--   OPTIONS  solver id -> field id -> option key -> text
--   TERMS    solver id (or _) -> result key -> { English, Chinese }
--   NOTES    { pattern, Chinese } for notes
--   SECTIONS { pattern, Chinese } for working-step headings
--   HELP_ZH  English help line -> Chinese line
local TABLES = { 'UI', 'HINTS', 'SOLVERS', 'BLURBS', 'FIELDS', 'OPTIONS', 'TERMS', 'NOTES', 'SECTIONS' }

-- Choose the language: 'bi' only when the Chinese text is loaded. Returns it.
function I.set(lang)
   I.lang = (lang == 'bi' and I.has_zh) and 'bi' or 'en'
   return I.lang
end

-- Load the Chinese text (require 'apps.vce.i18n_zh'); nil: English only
function I.install(zh)
   I.zh = zh
   I.has_zh = zh ~= nil
   for _, k in ipairs(TABLES) do I[k] = zh and zh[k] or {} end
   I.TERMS._ = I.TERMS._ or {}
   I.HELP_ZH = zh and zh.HELP or {}
   I.set(I.lang)
end

function I.bi()
   return I.lang == 'bi'
end

function I.blurb(s)
   if I.lang == 'bi' and I.BLURBS[s.id] then return I.BLURBS[s.id] end
   return s.blurb
end

local function apply(list, text)
   for _, p in ipairs(list) do
      local zh, n = text:gsub(p[1], p[2], 1)
      if n > 0 then return zh end
   end
end

-- "English Chinese" for a UI string (English only when not bilingual)
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
   local t = lookup(key) or lookup((key:gsub('%d+$', ''))) or lookup((key:gsub('_.*$', '')))
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

-- Help text, { kind, English }; lang: only when the language can be changed
I.HELP = {
   { 'header', 'Quick start: 3 steps' },
   { 'text', '1. Pick a topic on the home screen (press its number).' },
   { 'text', '2. Type what the question gives into the boxes. Leave unknowns empty.' },
   { 'text', '3. Answers (green) appear at once. The working is under them.' },
   { 'text', 'Not sure what to type? Choose "Try an example" in an empty problem.' },
   { 'text', 'MM = Maths Methods, SM = Specialist Maths. Both are for the tech-active Exam 2.' },
   { 'header', 'New topics' },
   { 'text', "Find unknown constants: type f(x) with letters, e.g. a*x^3+b*x^2+c, then one condition per box: f(1)=3, f'(2)=0, (2,5) (passes through), tp(1,2) (turning point), tangent y=2x+1 at x=1, asymptote x=2 or y=3." },
   { 'text', 'Transformations: type f(x) and the image, either with f (2f(3x-6)+4) or as a rule (3(x-1)^2+2). You get the transformations in order, the mapping (x, y) → (…), its inverse and a graph of both.' },
   { 'text', 'Simultaneous equations: type each equation in its own box (kx+2y=3). It finds when det = 0 and checks each value: no solution or infinitely many.' },
   { 'text', 'Probability: one entry for everything. Choose the kind of question first; switch later with the Type box. Sample proportion (p-hat) gives E, SD, P(p-hat > a), the approximate CI and the sample size.' },
   { 'header', 'Using a solver' },
   { 'text', 'Type the values you know into the fields and press enter: everything that can be worked out is shown under Results, with the Working underneath (written the way VCE marking expects).' },
   { 'text', 'Leave unknowns empty. Events are typed like the question: `45<X<55`, X>k (unknown k), X≥3, X>2|X≥1 (conditional).' },
   { 'text', 'Use functions from other pages of the same problem, e.g. a(t) = f11(t) or u = f11(2). ctrl+menu on a field lists them.' },
   { 'header', 'Keys' },
   { 'text', 'up/down: move · tab / shift+tab: next/previous field · enter: solve and go to next field' },
   { 'text', 'On a result: enter or click switches exact ⇔ decimal; left/right also switch or scroll long answers.' },
   { 'text', 'On results/working: n / p next or previous problem, t tag, h history, d all decimal, e all exact.' },
   { 'text', 'ctrl+C copies the selected line: an answer (as shown, exact or decimal), a working line, what is in a box, or a choice; the bottom bar shows what was copied. menu opens the toolbar menu (new problem, tag, settings). ctrl+menu opens the context menu.' },
   { 'header', 'Tips' },
   { 'text', 'Decimal places: menu > Settings. Answers are rounded only for display; values keep full precision.' },
   { 'text', 'Kinematics: pick what is given (a(t), a(v), a(x), v(t), v(x), v²(x), x(t)), enter t0, x0, v0 (one known state) and optionally a second condition like x(2)=5. Choose what to find (everything, x, v, a or t) and type the instant in "when": t=3, v=0, x=5 or a=0. Find can also be one function, such as v(x), t(x) or x(v): it is worked out from the others. If something is missing, a note says which value to give.' },
   { 'text', 'Kinematics formulas: enter switches exact / decimal like every answer; select a derived formula such as x(v) and press W to see only the working for that formula; its domain is shown under it. Unknown constants (k) come from a condition in "also", e.g. a=-3.5 when v=7 or a(7)=-3.5; several conditions are separated by ;.' },
   { 'text', 'Vector angle: type two vectors (2i-j+3k or (2,-1,3)), or choose three points for angle ABC (the vertex is B). Choose 0 to 180° for the angle between vectors, or acute for the angle between lines (180° − θ when θ is obtuse). With a letter such as m in a vector, type the angle in "given θ" to find m.' },
   { 'text', 'Function graph: enter f(x) and the x window (the y window is optional). It finds asymptotes, turning points, points of inflection, intercepts, holes, jumps, endpoints and points where f is not differentiable; the choices show or hide each feature (asymptotes are dashed).' },
   { 'text', 'Graphs: select a graph and press enter (or click it) for full screen. left/right trace · up/down jump between marked points · tab next curve · + / − zoom · 8 4 6 2 pan · 5 reset · l labels · a asymptotes · esc back.' },
   { 'text', 'Area/volume: y = f(x), x = g(y) or parametric x(t), y(t); a second curve gives the area or volume between the curves. Limits can be y values (choose "Limits are: y values" or type y=1 and y=4) and may contain a letter such as a; type a known volume (V=16pi) or area in "given" to find it. DE models: choose growth/decay, cooling, logistic, mixing, a general dy/dx (with Euler steps) or related rates.' },
   { 'text', 'Run Self-test once on your calculator to check the solvers with its CAS.' },
   { 'text', 'Language: menu > Settings > Language.', lang = true },
}

-- Help rows { kind, text }; bilingual mode adds the Chinese
function I.help()
   local out = {}
   for _, h in ipairs(I.HELP) do
      if I.has_zh or not h.lang then
         local zh = I.lang == 'bi' and I.HELP_ZH[h[2]]
         local sep = h[1] == 'header' and ' ' or '\n'
         table.insert(out, { h[1], zh and (h[2] .. sep .. zh) or h[2] })
      end
   end
   return out
end

I.install(nil)

return I
